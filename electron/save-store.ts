import { promises as fsp, copyFileSync, existsSync, mkdirSync, openSync, writeSync, fsyncSync, closeSync, renameSync, readFileSync } from "node:fs";
import path from "node:path";
import { encodeSaveFile, parseSaveFile, type RawFiles } from "./save-file";

/** userData/save_data.json 의 원자적 읽기/쓰기. 쓰기는 tmp → fsync → rename 순서이며 직전 정상본은 .bak로 보존. */
export class SaveStore {
  readonly file: string;
  readonly backup: string;
  readonly #tmp: string;
  #queue: Promise<void> = Promise.resolve();

  constructor(directory: string) {
    this.file = path.join(directory, "save_data.json");
    this.backup = this.file + ".bak";
    this.#tmp = this.file + ".tmp";
    mkdirSync(directory, { recursive: true });
  }

  async load(): Promise<RawFiles> {
    for (const candidate of [this.file, this.backup]) {
      let text: string;
      try { text = await fsp.readFile(candidate, "utf8"); } catch { continue; }
      try {
        return parseSaveFile(text);
      } catch (error) {
        console.error(`세이브 파일을 읽지 못했습니다(${candidate}):`, error);
        // 손상본은 덮어써지기 전에 보존한다.
        await fsp.copyFile(candidate, `${candidate}.corrupt-${Date.now()}`).catch(() => undefined);
      }
    }
    return {};
  }

  /** 쓰기 요청을 직렬화한다. */
  write(files: RawFiles): Promise<void> {
    const text = encodeSaveFile(files);
    this.#queue = this.#queue.then(async () => {
      const handle = await fsp.open(this.#tmp, "w");
      try { await handle.writeFile(text, "utf8"); await handle.sync(); } finally { await handle.close(); }
      await fsp.copyFile(this.file, this.backup).catch(() => undefined);
      await fsp.rename(this.#tmp, this.file);
    });
    // 한 번의 실패가 이후 쓰기를 막지 않도록 큐는 살리고, 호출자에게는 오류를 전달한다.
    const result = this.#queue;
    this.#queue = this.#queue.catch(() => undefined);
    return result;
  }

  /** 창 종료 직전 전용. */
  writeSync(files: RawFiles): void {
    const text = encodeSaveFile(files);
    const fd = openSync(this.#tmp, "w");
    try { writeSync(fd, text); fsyncSync(fd); } finally { closeSync(fd); }
    if (existsSync(this.file)) copyFileSync(this.file, this.backup);
    renameSync(this.#tmp, this.file);
  }

  /** 디버깅용 */
  readRawText(): string | undefined {
    try { return readFileSync(this.file, "utf8"); } catch { return undefined; }
  }
}
