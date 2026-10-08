import { app, BrowserWindow, ipcMain, net, protocol, type IpcMainEvent, type IpcMainInvokeEvent } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { sanitizeIncoming } from "./save-file";
import { SaveStore } from "./save-store";

const DEV_URL = "http://localhost:8000"; // vite.config.ts의 server.port
const isDev = !app.isPackaged && process.argv.includes("--dev");
const APP_ORIGIN = "app://game";

// file:// 에서는 type="module" 스크립트/ fetch 가 CORS로 막히므로 전용 스킴으로 dist를 서빙한다.
protocol.registerSchemesAsPrivileged([
  { scheme: "app", privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } },
]);

// 같은 세이브 파일에 두 프로세스가 쓰는 것을 막는다.
if (!app.requestSingleInstanceLock()) app.quit();

let store: SaveStore;
let mainWindow: BrowserWindow | undefined;

const trusted = (event: IpcMainEvent | IpcMainInvokeEvent): boolean => {
  const url = event.senderFrame?.url ?? "";
  return url.startsWith(APP_ORIGIN + "/") || (isDev && url.startsWith(DEV_URL));
};

const registerIpc = (): void => {
  ipcMain.handle("save:load", async event => {
    if (!trusted(event)) throw new Error("untrusted sender");
    return store.load();
  });
  ipcMain.handle("save:write", async (event, payload: unknown) => {
    if (!trusted(event)) throw new Error("untrusted sender");
    await store.write(sanitizeIncoming(payload));
  });
  ipcMain.on("save:write-sync", (event, payload: unknown) => {
    try {
      if (!trusted(event)) throw new Error("untrusted sender");
      store.writeSync(sanitizeIncoming(payload));
      event.returnValue = true;
    } catch (error) {
      console.error("동기 세이브 실패:", error);
      event.returnValue = false;
    }
  });
};

const registerAppProtocol = (): void => {
  const root = path.join(app.getAppPath(), "dist");
  protocol.handle("app", request => {
    const { pathname } = new URL(request.url);
    const relative = decodeURIComponent(pathname === "/" ? "/index.html" : pathname);
    const target = path.normalize(path.join(root, relative));
    if (target !== root && !target.startsWith(root + path.sep)) return new Response("forbidden", { status: 403 });
    return net.fetch(pathToFileURL(target).toString());
  });
};

const createWindow = (): void => {
  mainWindow = new BrowserWindow({
    useContentSize: true,
    width: 480,
    height: 640,
    minWidth: 240,
    minHeight: 320,
    backgroundColor: "#000000",
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      autoplayPolicy: "no-user-gesture-required",
    },
  });
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (!url.startsWith(APP_ORIGIN) && !(isDev && url.startsWith(DEV_URL))) event.preventDefault();
  });
  void mainWindow.loadURL(isDev ? DEV_URL : `${APP_ORIGIN}/index.html`);
  if (isDev) mainWindow.webContents.openDevTools({ mode: "detach" });
  mainWindow.on("closed", () => { mainWindow = undefined; });
};

app.on("second-instance", () => {
  if (mainWindow) { if (mainWindow.isMinimized()) mainWindow.restore(); mainWindow.focus(); }
});

void app.whenReady().then(() => {
  store = new SaveStore(app.getPath("userData"));
  console.log("세이브 파일:", store.file);
  registerIpc();
  if (!isDev) registerAppProtocol();
  createWindow();
});

app.on("window-all-closed", () => app.quit());
