import { defineConfig } from "vite";

export default defineConfig(({ mode }) => ({
  root: import.meta.dirname,
  // Electron 빌드(--mode electron)만 상대 경로. 기존 웹 빌드는 그대로 "/" 유지.
  base: mode === "electron" ? "./" : "/",
  server: {
    port: 8000,
  },
  build: {
    outDir: "dist",
    assetsInlineLimit: 0,
    emptyOutDir: true,
  },
}));
