import { CachedStorage } from "./cached-storage";

/** preload 브리지를 PersistBackend로 감싸 CachedStorage를 연다. */
export const openElectronStorage = (bridge: RhythmStarBridge): Promise<CachedStorage> =>
  CachedStorage.open({
    load: () => bridge.loadSave(),
    save: files => bridge.writeSave(files),
    saveSync: files => bridge.writeSaveSync(files),
  });
