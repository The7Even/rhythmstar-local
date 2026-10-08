import { contextBridge, ipcRenderer } from "electron";

// 렌더러에는 이 3개 함수만 노출한다. (contextIsolation: true, nodeIntegration: false)
contextBridge.exposeInMainWorld("rhythmstar", {
  loadSave: (): Promise<Record<string, Uint8Array>> => ipcRenderer.invoke("save:load"),
  writeSave: (files: Record<string, Uint8Array>): Promise<void> => ipcRenderer.invoke("save:write", files),
  writeSaveSync: (files: Record<string, Uint8Array>): void => { ipcRenderer.sendSync("save:write-sync", files); },
});
