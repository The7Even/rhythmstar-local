import { unzipSync } from 'fflate';
import archiveUrl from '../assets/upscaled/images.zip?url';

let archive: Promise<Record<string, Uint8Array>> | undefined;
const images = new Map<string, Promise<HTMLImageElement>>();

function loadArchive(): Promise<Record<string, Uint8Array>> {
  return archive ??= (async () => {
    const response = await fetch(archiveUrl);
    if (!response.ok) throw new Error(`Remastered image archive failed (${response.status})`);
    return unzipSync(new Uint8Array(await response.arrayBuffer()));
  })();
}

/** One ZIP request shared by title, sprites and fonts; decode each image once. */
export function loadRemasteredImage(path: string): Promise<HTMLImageElement> {
  const cached = images.get(path);
  if (cached) return cached;
  const pending = (async () => {
    const bytes = (await loadArchive())[path];
    if (!bytes) throw new Error(`Missing image in remastered archive: ${path}`);
    const url = URL.createObjectURL(new Blob([new Uint8Array(bytes)], {type:'image/avif'}));
    try {
      const image = new Image();
      image.src = url;
      await image.decode();
      return image;
    } finally {
      URL.revokeObjectURL(url);
    }
  })();
  images.set(path, pending);
  return pending;
}
