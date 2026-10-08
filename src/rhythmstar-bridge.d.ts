/** preload(electron/preload.ts)가 contextBridge로 노출하는 영속 저장 API. 브라우저 환경에서는 undefined. */
interface RhythmStarBridge {
  loadSave(): Promise<Record<string, Uint8Array>>;
  writeSave(files: Record<string, Uint8Array>): Promise<void>;
  /** 창을 닫는 순간(beforeunload) 전용 동기 쓰기. */
  writeSaveSync(files: Record<string, Uint8Array>): void;
}

interface Window {
  rhythmstar?: RhythmStarBridge;
}
