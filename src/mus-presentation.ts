import type { PresentationSprite } from './presentation';
import type { VrpArchive } from './vrp';

const pictures = new WeakSet<PresentationSprite>();

/** Mark decoded song artwork without changing MUS bytes or native sprites. */
export function registerMusPicture(archive: VrpArchive): VrpArchive {
  for (const sprite of archive.sprites) pictures.add(sprite);
  return archive;
}

export const isMusPicture = (sprite: PresentationSprite): boolean => pictures.has(sprite);
