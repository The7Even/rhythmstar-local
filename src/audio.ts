import { Sequencer, WorkletSynthesizer } from "spessasynth_lib";
import processorUrl from "spessasynth_lib/dist/spessasynth_processor.min.js?url";
import soundBankUrl from "../assets/1mgm.sf2?url";
import type { MusicPort } from "./io";
import { parseSmaf, smafToMidi } from "./smaf";

export class BrowserMusic implements MusicPort {
  readonly #context = new AudioContext();
  readonly #ready: Promise<void>;
  #synth: WorkletSynthesizer | undefined;
  #sequencer: Sequencer | undefined;
  #current: { midi: Uint8Array<ArrayBuffer>; repeat: boolean } | undefined;
  #pcmSource: AudioBufferSourceNode | undefined;
  #pcmActive = false;
  #generation = 0;
  readonly #pcmBuffers = new WeakMap<Uint8Array, AudioBuffer>();
  readonly #pcmPending = new WeakMap<Uint8Array, Promise<void>>();
  readonly #effectSources = new Set<AudioBufferSourceNode>();
  readonly #effectBuffers = new WeakMap<Uint8Array, { time: number; buffer: AudioBuffer }[]>();
  readonly #musicGain = this.#context.createGain();
  readonly #effectGain = this.#context.createGain();

  constructor(readonly onError: (error: unknown) => void) {
    this.#effectGain.gain.value = 0.5;
    this.#effectGain.connect(this.#context.destination);
    this.#musicGain.connect(this.#effectGain);
    // Prepare the bank while the opening screens run. A keyboard/pointer
    // gesture resumes the context without inventing a game input event.
    this.#ready = this.#initialize().catch(onError);
  }

  async #initialize(): Promise<void> {
    const [response] = await Promise.all([
      fetch(soundBankUrl),
      this.#context.audioWorklet.addModule(processorUrl),
    ]);
    if (!response.ok) throw new Error(`Sound bank request failed (${response.status})`);
    const synth = new WorkletSynthesizer(this.#context);
    await synth.soundBankManager.addSoundBank(await response.arrayBuffer(), "gm");
    await synth.isReady;
    synth.connect(this.#musicGain);
    this.#synth = synth;
    this.#sequencer = new Sequencer(synth, { skipToFirstNoteOn: false });
    this.#apply();
  }

  unlock(): void {
    if (this.#context.state === "closed") return;
    // Where supported, treat game audio as media playback, including on iOS
    // devices with the ring/silent switch enabled.
    const session = (navigator as Navigator & { audioSession?: { type: string } }).audioSession;
    if (session && session.type !== "playback") {
      try { session.type = "playback"; } catch (error) { this.onError(error); }
    }
    // Safari can enter "interrupted" after switching apps or locking the phone.
    if (this.#context.state !== "running") void this.#context.resume().catch(this.onError);
  }

  play(data: Uint8Array, repeat: boolean): void {
    if (this.#isOgg(data)) {
      this.stop();
      this.#pcmActive = true;
      this.#musicGain.gain.value = 1;
      const generation = this.#generation;
      const requestedAt = this.#context.currentTime;
      const start = () => {
        if (generation !== this.#generation) return;
        const buffer = this.#pcmBuffers.get(data)!;
        const elapsed = Math.max(0, this.#context.currentTime - requestedAt);
        if (!repeat && elapsed >= buffer.duration) return;
        const source = this.#context.createBufferSource();
        source.buffer = buffer;
        source.loop = repeat;
        source.connect(this.#musicGain);
        source.onended = () => {
          source.disconnect();
          if (this.#pcmSource === source) this.#pcmSource = undefined;
        };
        this.#pcmSource = source;
        source.start(0, repeat ? elapsed % buffer.duration : elapsed);
      };
      if (this.#pcmBuffers.has(data)) start();
      else void this.prepare(data).then(start).catch(this.onError);
      return;
    }
    this.#stopPcm();
    this.#current = { midi: smafToMidi(parseSmaf(data)), repeat };
    this.#apply();
  }

  #isOgg(data: Uint8Array): boolean {
    return data[0] === 0x4f && data[1] === 0x67 && data[2] === 0x67 && data[3] === 0x53;
  }

  /** Decode before gameplay so starting music does not wait for the decoder. */
  async prepare(data: Uint8Array): Promise<void> {
    if (!this.#isOgg(data) || this.#pcmBuffers.has(data)) return;
    let pending = this.#pcmPending.get(data);
    if (!pending) {
      pending = this.#context.decodeAudioData(new Uint8Array(data).buffer).then(buffer => {
        this.#pcmBuffers.set(data, buffer);
      }).finally(() => this.#pcmPending.delete(data));
      this.#pcmPending.set(data, pending);
    }
    await pending;
  }

  #stopPcm(): void {
    this.#generation++;
    this.#pcmActive = false;
    this.#pcmSource?.stop();
    this.#pcmSource?.disconnect();
    this.#pcmSource = undefined;
  }

  stop(): void {
    this.#stopPcm();
    this.#stopEffect();
    this.#current = undefined;
    this.#apply();
  }

  setVolume(level: number): void {
    this.#effectGain.gain.value = level;
  }

  playEffect(data: Uint8Array): void {
    let buffers = this.#effectBuffers.get(data);
    if (!buffers) {
      const sequence = parseSmaf(data);
      if (!sequence.waves?.length || sequence.events.some(event => (event.data[0] & 0xf0) === 0x90)) {
        throw new Error("Expected a PCM-only menu effect");
      }
      buffers = sequence.waves.map(wave => {
        const buffer = this.#context.createBuffer(1, wave.samples.length, wave.samplingRate);
        const samples = buffer.getChannelData(0);
        wave.samples.forEach((sample, index) => { samples[index] = sample / 32768; });
        return { time: wave.time / 1000, buffer };
      });
      this.#effectBuffers.set(data, buffers);
    }
    // Replacing a PCM effect must not pause or reset the MIDI sequencer.
    this.#stopEffect();
    const start = this.#context.currentTime;
    for (const { time, buffer } of buffers) {
      const source = this.#context.createBufferSource();
      source.buffer = buffer;
      source.connect(this.#effectGain);
      this.#effectSources.add(source);
      source.onended = () => { this.#effectSources.delete(source); source.disconnect(); };
      source.start(start + time);
    }
  }

  #stopEffect(): void {
    for (const source of this.#effectSources) { source.stop(); source.disconnect(); }
    this.#effectSources.clear();
  }

  #apply(): void {
    // Gate BGM independently, including while worklet messages are in flight.
    this.#musicGain.gain.value = this.#current || this.#pcmActive ? 1 : 0;
    const sequencer = this.#sequencer;
    if (!sequencer) return;
    if (!this.#current) {
      sequencer.pause();
      this.#synth?.stopAll(true);
      return;
    }
    // The installed core uses Infinity; the wrapper's -1 JSDoc is stale.
    sequencer.loopCount = this.#current.repeat ? Infinity : 0;
    sequencer.loadNewSongList([{ binary: this.#current.midi.buffer, fileName: "Rhythm Star BGM.mid" }]);
    sequencer.play();
  }

  close(): void {
    this.stop();
    void this.#ready.then(() => this.#context.close()).catch(this.onError);
  }
}
