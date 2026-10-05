import { compileSequence, ChartSequence } from "./chart-sequence";

export type RhythmChart = {
  id: string;
  title: string;
  subtitle: string;
  artist: string;
  bpm: number;
  keyCount: 3 | 6 | 9;
  level: number;
  rank: number;
  audioFilename: string;
  sequence: ChartSequence;
  durationMs: number;
};

const decoder = new TextDecoder("euc-kr");

const directive = (text: string, name: string): string => {
  // Horizontal whitespace only: an empty directive must not consume the next
  // header line. Quoted values end before any trailing // comment.
  const match = text.match(new RegExp(`^#${name}(?:[ \\t]+([^\\r\\n]*))?[ \\t]*$`, "im"));
  const value = match?.[1]?.trim() ?? "";
  if (value.startsWith('"')) {
    const closing = value.indexOf('"', 1);
    return closing < 0 ? value.slice(1) : value.slice(1, closing);
  }
  return value.split('//', 1)[0].trim();
};

const chartText = (data: Uint8Array): string => {
  const length = new DataView(data.buffer, data.byteOffset, data.byteLength).getUint32(0, true);
  return decoder.decode(data.subarray(4, 4 + length));
};

export const parseMus = (id: string, data: Uint8Array, speedScale = 65536): RhythmChart => {
  const text = chartText(data);
  const bpm = Number(directive(text, "BPM"));
  const keyCount = Number(directive(text, "KEY"));
  if (!Number.isFinite(bpm) || bpm <= 0 || (keyCount !== 3 && keyCount !== 6 && keyCount !== 9)) {
    throw new Error(`${id}: unsupported MUS header`);
  }

  const sequence = compileSequence(text, 65536, speedScale);
  const end = sequence.events.find(event => event.channel === 20);
  return {
    id,
    title: directive(text, "TITLE").split(/\r\n|\n|\\n/, 1)[0] || id,
    subtitle: directive(text, "SUBTITLE"),
    artist: directive(text, "ARTIST"),
    bpm,
    keyCount,
    level: Number(directive(text, "PLAYLEVEL")) || 0,
    rank: Number(directive(text, "RANK")) || 0,
    audioFilename: directive(text, "MMF"),
    sequence,
    durationMs: end?.timeMs ?? 0,
  };
};
