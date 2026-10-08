import type { StoragePort } from "./io";

/** 기존 localStorage 구현. Electron 밖(웹 배포, vite dev)에서의 폴백으로 유지한다. */
export class BrowserStorage implements StoragePort {
  readonly #prefix = "rhythmstar1:";

  read(name: string): Uint8Array | undefined {
    const encoded = localStorage.getItem(this.#prefix + name);
    if (encoded === null) return undefined;
    return Uint8Array.from(atob(encoded), character => character.charCodeAt(0));
  }

  write(name: string, data: Uint8Array): void {
    let binary = "";
    for (const byte of data) binary += String.fromCharCode(byte);
    localStorage.setItem(this.#prefix + name, btoa(binary));
  }
}
