import songPaths from "../assets/songs.json";
import { parseMus, type RhythmChart } from "./chart";

export function loadSongCatalog(read: (path: string) => Uint8Array, paths: readonly string[] = songPaths): RhythmChart[][] {
  const catalog: RhythmChart[][] = [[], [], []];
  const seen = new Set<string>();
  for (const path of paths) {
    if (seen.has(path)) throw new Error(`Duplicate song ID: ${path}`);
    seen.add(path);
    const chart = parseMus(path, read(path));
    read(`res/Mmf/${chart.audioFilename}`);
    catalog[chart.keyCount / 3 - 1].push(chart);
  }
  if (catalog.some(charts => !charts.length)) throw new Error("Song catalog needs at least one chart for each key mode");
  return catalog;
}
