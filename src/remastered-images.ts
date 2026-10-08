import { unzipSync } from 'fflate';
import archiveUrl from '../assets/upscaled/images.zip?url';

let archive: Promise<Record<string, Uint8Array>> | undefined;
const images = new Map<string, Promise<HTMLImageElement>>();

// 수백 장을 한꺼번에 decode()하면 Chromium(Electron)이 일시적으로 EncodingError를 내는 경우가 있어 동시 실행 수를 제한한다.
const MAX_CONCURRENT_DECODES = 8;
let activeDecodes = 0;
const waiting: Array<() => void> = [];

async function withDecodeSlot<T>(task: () => Promise<T>): Promise<T> {
  if (activeDecodes >= MAX_CONCURRENT_DECODES) await new Promise<void>(resolve => waiting.push(resolve));
  activeDecodes++;
  try {
    return await task();
  } finally {
    activeDecodes--;
    waiting.shift()?.();
  }
}

function loadArchive(): Promise<Record<string, Uint8Array>> {
  return archive ??= (async () => {
    const response = await fetch(archiveUrl);
    if (!response.ok) throw new Error(`Remastered image archive failed (${response.status})`);
    return unzipSync(new Uint8Array(await response.arrayBuffer()));
  })();
}

/** decode()가 실패하면 load 이벤트 방식 → createImageBitmap/canvas 경유 순으로 다시 시도한다. */
async function decodePng(bytes: Uint8Array): Promise<HTMLImageElement> {
  const blob = new Blob([new Uint8Array(bytes)], { type: 'image/png' });
  let lastError: unknown;
  for (let attempt = 0; attempt < 3; attempt++) {
    const url = URL.createObjectURL(blob);
    try {
      const image = new Image();
      image.src = url;
      if (attempt === 0) {
        await image.decode();
      } else {
        await new Promise<void>((resolve, reject) => {
          image.onload = () => resolve();
          image.onerror = () => reject(new Error('image load error'));
        });
      }
      return image;
    } catch (error) {
      lastError = error;
    } finally {
      URL.revokeObjectURL(url);
    }
  }
  try {
    const bitmap = await createImageBitmap(blob);
    const canvas = document.createElement('canvas');
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    canvas.getContext('2d')!.drawImage(bitmap, 0, 0);
    bitmap.close();
    const image = new Image();
    image.src = canvas.toDataURL('image/png');
    await image.decode();
    return image;
  } catch {
    throw lastError;
  }
}

/** One ZIP request shared by title, sprites and fonts; decode each image once. */
export function loadRemasteredImage(path: string): Promise<HTMLImageElement> {
  const cached = images.get(path);
  if (cached) return cached;
  const pending = (async () => {
    const bytes = (await loadArchive())[path];
    if (!bytes) throw new Error(`Missing image in remastered archive: ${path}`);
    try {
      return await withDecodeSlot(() => decodePng(bytes));
    } catch (error) {
      const head = Array.from(bytes.subarray(0, 8)).map(b => b.toString(16).padStart(2, '0')).join(' ');
      throw new Error(`이미지 디코드 실패: ${path} (${bytes.length}바이트, 앞 8바이트: ${head})`, { cause: error });
    }
  })();
  images.set(path, pending);
  return pending;
}
