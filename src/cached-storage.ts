import type { StoragePort } from "./io";

/** 실제 영속 계층(디스크 등). 모든 메서드는 게임 루프 밖에서만 호출된다. */
export interface PersistBackend {
  load(): Promise<Record<string, Uint8Array>>;
  save(files: Record<string, Uint8Array>): Promise<void>;
  /** 종료 직전 마지막 저장용(선택). */
  saveSync?(files: Record<string, Uint8Array>): void;
}

/**
 * 동기 StoragePort 계약을 유지하면서 디스크 I/O를 렌더 루프에서 분리한다.
 * - read(): 시작 시 한 번 채운 메모리 캐시에서 즉시 반환
 * - write(): 스냅샷 복사 후 캐시에 반영하고 디바운스된 비동기 저장을 예약
 * - 저장은 직렬화(이전 저장이 끝난 뒤 다음 저장)되며, 실패하면 dirty로 남겨 재시도한다.
 */
export class CachedStorage implements StoragePort {
  readonly #files = new Map<string, Uint8Array>();
  readonly #backend: PersistBackend;
  readonly #delayMs: number;
  #dirty = false;
  #timer: ReturnType<typeof setTimeout> | undefined;
  #chain: Promise<void> = Promise.resolve();

  private constructor(backend: PersistBackend, delayMs: number) {
    this.#backend = backend;
    this.#delayMs = delayMs;
  }

  static async open(backend: PersistBackend, delayMs = 400): Promise<CachedStorage> {
    const storage = new CachedStorage(backend, delayMs);
    const loaded = await backend.load();
    for (const [name, data] of Object.entries(loaded)) storage.#files.set(name, data.slice());
    return storage;
  }

  read(name: string): Uint8Array | undefined {
    return this.#files.get(name)?.slice();
  }

  write(name: string, data: Uint8Array): void {
    // 호출자는 this.save.bytes 같은 가변 버퍼를 그대로 넘기므로 반드시 복사한다.
    this.#files.set(name, data.slice());
    this.#dirty = true;
    this.#timer ??= setTimeout(() => { void this.flush(); }, this.#delayMs);
  }

  /** 대기 중인 변경을 즉시 비동기로 저장한다. */
  flush(): Promise<void> {
    if (this.#timer !== undefined) { clearTimeout(this.#timer); this.#timer = undefined; }
    if (!this.#dirty) return this.#chain;
    this.#dirty = false;
    const snapshot = Object.fromEntries(this.#files);
    this.#chain = this.#chain.then(() => this.#backend.save(snapshot)).catch(error => {
      console.error("세이브 저장 실패, 다음 기회에 재시도합니다:", error);
      this.#dirty = true;
    });
    return this.#chain;
  }

  /** beforeunload 전용. 비동기 저장은 창이 닫히면 끊길 수 있으므로 동기 경로를 쓴다. */
  flushSync(): void {
    if (this.#timer !== undefined) { clearTimeout(this.#timer); this.#timer = undefined; }
    if (!this.#dirty || !this.#backend.saveSync) return;
    this.#dirty = false;
    try {
      this.#backend.saveSync(Object.fromEntries(this.#files));
    } catch (error) {
      console.error("종료 시 세이브 저장 실패:", error);
    }
  }
}
