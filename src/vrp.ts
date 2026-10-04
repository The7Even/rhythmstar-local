import { Rgb565Framebuffer } from "./framebuffer";

export type VrpSprite = Readonly<{
  width: number;
  height: number;
  pixels: Uint16Array;
  opaque: Uint8Array;
  runs: readonly (readonly { skip: number; length: number }[])[];
}>;

export type VrpArchive = Readonly<{
  sprites: readonly VrpSprite[];
  animations: readonly (VrpAnimation | undefined)[];
}>;

export type VrpObject = Readonly<{
  sprite: number;
  scaleX: number;
  scaleY: number;
  drawMode: number;
  effect: number;
  rotation: number;
  left: number;
  right: number;
  top: number;
  bottom: number;
}>;

export type VrpFrame = Readonly<{
  objects: readonly VrpObject[];
  markers: readonly { id: number; x: number; y: number }[];
}>;

export type VrpAnimation = Readonly<{
  firstFrame: number;
  durationTicks: number;
  durationMilliseconds: number;
  frames: readonly VrpFrame[];
}>;

const MAGIC = 0x0ab60000;
const VERSION = 0x00021000;
const OBJECT_SCALE_ONE = 64;
// 0x00126046 multiplies the signed object rotation by 0x0006487e,
// which is 2π in 16.16 fixed point. The stored rotation is therefore a
// signed 16.16 fraction of one turn, not a 12-bit (4096-step) angle.
const OBJECT_ROTATION_TURN = 65536;

// 0x1001 is the native renderer's direct-copy fast path. Other combinations
// index the four 17-level channel tables built by 0x11e1fc.
const blendMode = (object: VrpObject): number => object.drawMode === 1 && object.effect === 16 && object.rotation === 0 ? 0 : object.drawMode;

const readU32 = (view: DataView, offset: number): number => view.getUint32(offset, true);

export const parseVrp = (bytes: Uint8Array): VrpArchive => {
  if (bytes.byteLength < 36) throw new Error("VRP header is truncated");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (readU32(view, 0) !== MAGIC || readU32(view, 4) !== VERSION) throw new Error("Unsupported VRP format");
  if (readU32(view, 8) !== bytes.byteLength) throw new Error("VRP file size does not match its header");

  const paletteTable = readU32(view, 24);
  const spriteTable = readU32(view, 28);
  const spriteDataEnd = readU32(view, 32);
  const paletteCount = readU32(view, paletteTable);
  const palettes: Uint16Array[] = [];
  for (let paletteIndex = 0;paletteIndex < paletteCount;paletteIndex += 1) {
    const paletteOffset = readU32(view, paletteTable + 4 + paletteIndex * 4);
    if (paletteOffset + 516 > bytes.byteLength) throw new Error(`VRP palette ${paletteIndex} is truncated`);
    const colors = new Uint16Array(256);
    for (let color = 0;color < colors.length;color += 1) colors[color] = view.getUint16(paletteOffset + 4 + color * 2, true);
    palettes.push(colors);
  }

  const spriteCount = readU32(view, spriteTable);
  const spriteOffsets = Array.from({ length: spriteCount }, (_, index) => readU32(view, spriteTable + 4 + index * 4));
  const sprites = spriteOffsets.map((offset, index) => {
    const end = spriteOffsets[index + 1] ?? spriteDataEnd;
    return decodeSprite(view, offset, end, palettes, index);
  });

  const animationTable = readU32(view, 16);
  const animationCount = readU32(view, animationTable);
  const animations = Array.from({ length: animationCount }, (_, index) => {
    const offset = readU32(view, animationTable + 4 + index * 4);
    if (offset === 0) return undefined;
    try {
      return decodeAnimation(view, offset, index);
    } catch {
      // Some shipped VRPs leave non-zero garbage pointers in unused animation
      // slots. The native resource loader treats those slots as absent.
      return undefined;
    }
  });
  return { sprites, animations };
};

const decodeAnimation = (view: DataView, offset: number, animationIndex: number): VrpAnimation => {
  if (offset + 12 > view.byteLength) throw new Error(`VRP animation ${animationIndex} header is truncated`);
  const durationTicks = readU32(view, offset);
  const firstFrame = readU32(view, offset + 4);
  const durationMilliseconds = (durationTicks * 1000) / 65536;
  const frameCount = readU32(view, offset + 8);
  if (offset + 12 + frameCount * 4 > view.byteLength) throw new Error(`VRP animation ${animationIndex} frame table is truncated`);
  const frames = Array.from({ length: frameCount }, (_, frameIndex) => {
    const frameOffset = readU32(view, offset + 12 + frameIndex * 4);
    if (frameOffset + 8 > view.byteLength) throw new Error(`VRP animation ${animationIndex} frame ${frameIndex} is truncated`);
    const objectCount = view.getInt16(frameOffset, true);
    const objectOffset = readU32(view, frameOffset + 4);
    if (objectOffset + objectCount * 20 > view.byteLength) throw new Error(`VRP animation ${animationIndex} frame ${frameIndex} objects are truncated`);
    const objects = Array.from({ length: objectCount }, (_, objectIndex): VrpObject => {
      const object = objectOffset + objectIndex * 20;
      const topFixed = view.getInt16(object + 18, true);
      const bottomFixed = view.getInt16(object + 16, true);
      return {
        sprite: readU32(view, object),
        // The native renderer at 0x125e44 reads both fields with LDRSH.
        scaleX: view.getInt16(object + 4, true) / OBJECT_SCALE_ONE,
        scaleY: view.getInt16(object + 6, true) / OBJECT_SCALE_ONE,
        drawMode: view.getUint8(object + 8),
        effect: view.getUint8(object + 9) & 0x1f,
        rotation: view.getInt16(object + 10, true),
        left: view.getInt16(object + 12, true) / 16,
        right: view.getInt16(object + 14, true) / 16,
        top: -topFixed / 16,
        bottom: -bottomFixed / 16,
      };
    });
    const markerCount = view.getInt16(frameOffset + 2, true);
    const markerOffset = readU32(view, frameOffset + 8);
    const markers = Array.from({ length: markerCount }, (_, index) => {
      const at = markerOffset + index * 8;
      return { id: view.getInt16(at + 6, true), x: view.getInt16(at + 2, true) / 16, y: -view.getInt16(at + 4, true) / 16 };
    });
    return { objects, markers };
  });
  return { firstFrame, durationTicks, durationMilliseconds, frames };
};

// When repeated sprites keep the same count, their source order preserves
// identity even if brightness changes. Otherwise use pose and effect together.
const matchingObject = (
  objects: readonly VrpObject[], object: VrpObject, used: ReadonlySet<number> = new Set(),
  spriteGroups: readonly (readonly number[])[] = [], sourceObjects: readonly VrpObject[] = [],
): number => {
  const compatible = (candidate: VrpObject): boolean => {
    const sameSprite = candidate.sprite === object.sprite || spriteGroups.some(group => group.includes(object.sprite) && group.includes(candidate.sprite));
    return sameSprite && candidate.drawMode === object.drawMode
      && object.scaleX * candidate.scaleX >= 0 && object.scaleY * candidate.scaleY >= 0;
  };
  const source = sourceObjects.filter(compatible);
  const candidates = objects.map((candidate, i) => compatible(candidate) ? i : -1).filter(i => i >= 0);
  if (!spriteGroups.some(group => group.includes(object.sprite)) && source.length > 1 && source.length === candidates.length) {
    const index = candidates[source.indexOf(object)];
    if (index !== undefined && !used.has(index)) return index;
  }
  let match = -1;
  let distance = Infinity;
  for (const i of candidates) {
    if (used.has(i)) continue;
    const candidate = objects[i];
    const delta = (candidate.left - object.left) ** 2 + (candidate.top - object.top) ** 2
      + (candidate.effect - object.effect) ** 2 * 16
      + ((candidate.scaleX - object.scaleX) ** 2 + (candidate.scaleY - object.scaleY) ** 2) * 4096;
    if (delta < distance) { match = i; distance = delta; }
  }
  return match;
};

// Star paths overlap at the turnaround frame. Keep one physical star there
// rather than interpolating both source copies along different paths.
const distinctVariants = (frame: VrpFrame | undefined, groups: readonly (readonly number[])[]): VrpFrame | undefined => {
  if (!frame || !groups.length) return frame;
  return { ...frame, objects: frame.objects.filter((object, i, objects) => {
    const group = groups.find(group => group.includes(object.sprite));
    if (!group) return true;
    return !objects.slice(i + 1).some(other => group.includes(other.sprite)
      && other.drawMode === object.drawMode && other.effect === object.effect
      && other.scaleX === object.scaleX && other.scaleY === object.scaleY
      && Math.abs((other.left + other.right - object.left - object.right) / 2) <= 1.5
      && Math.abs((other.top + other.bottom - object.top - object.bottom) / 2) <= 1.5);
  }) };
};

// Scrolling strips include their periodic endpoint as the last source frame.
const scrollingEndpoints = new WeakMap<VrpAnimation, boolean>();
const hasScrollingEndpoint = (animation: VrpAnimation): boolean => {
  const cached = scrollingEndpoints.get(animation);
  if (cached !== undefined) return cached;
  const first = animation.frames[0]?.objects ?? [];
  const last = animation.frames.at(-1)?.objects ?? [];
  const displacement = last[0] && first[0] ? last[0].left - first[0].left : 0;
  const scrolling = first.length > 2 && first.length === last.length && Math.abs(displacement) > 1
    && first.every((object, i) => {
      const end = last[i];
      return object.sprite === first[0].sprite && end.sprite === object.sprite
        && end.drawMode === object.drawMode && end.scaleX === object.scaleX && end.scaleY === object.scaleY
        && end.top === object.top && end.bottom === object.bottom && end.rotation === object.rotation
        && Math.abs(end.left - object.left - displacement) <= 1;
    });
  scrollingEndpoints.set(animation, scrolling);
  return scrolling;
};

/** Semantic translation of the player at 0x125b9c / 0x125d6c. */
export class VrpPlayer {
  frame = 0;
  position = 0;
  #updatedFrame: number | undefined;
  #updatedAnimation: number | undefined;
  constructor(readonly archive: VrpArchive, public animation: number, public looping = true, readonly visualSpriteGroups: readonly (readonly number[])[] = []) { }

  select(animation: number, looping = true): void {
    this.animation = animation;
    this.looping = looping;
    this.position = 0;
    this.frame = 0;
    this.#updatedFrame = undefined;
  }

  update(milliseconds: number): boolean {
    const animation = this.archive.animations[this.animation];
    if (!animation || !animation.frames.length || !animation.durationTicks) return true;
    this.position += Math.floor(milliseconds * 65536 / 1000);
    const complete = this.position > animation.durationTicks;
    if (complete) this.position = this.looping ? this.position - animation.durationTicks : animation.durationTicks;
    this.frame = Math.min(animation.firstFrame + animation.frames.length - 1,
      Math.floor(this.position * (animation.firstFrame + animation.frames.length) / animation.durationTicks));
    this.#updatedFrame = this.frame;
    this.#updatedAnimation = this.animation;
    return complete;
  }

  visualFrame(milliseconds = 0): VrpFrame | undefined {
    const animation = this.archive.animations[this.animation];
    if (!animation) return;
    if (this.#updatedFrame !== this.frame || this.#updatedAnimation !== this.animation || !animation.durationTicks) {
      return animation.frames[this.frame - animation.firstFrame];
    }
    let position = this.position + Math.floor(milliseconds * 65536 / 1000);
    if (position >= animation.durationTicks) position = this.looping ? position % animation.durationTicks : animation.durationTicks;
    const interpolateLoop = this.looping && this.visualSpriteGroups.length > 0;
    const index = Math.min(animation.frames.length - (interpolateLoop ? 0 : 1),
      position * (animation.firstFrame + animation.frames.length - (this.looping && hasScrollingEndpoint(animation) ? 1 : 0)) / animation.durationTicks - animation.firstFrame);
    const current = distinctVariants(animation.frames[Math.floor(index)], this.visualSpriteGroups);
    const next = distinctVariants(animation.frames[Math.floor(index) + 1] ?? (interpolateLoop ? animation.frames[0] : undefined), this.visualSpriteGroups);
    if (!current || !next) return current;
    const fraction = index - Math.floor(index);
    const mix = (from: number, to: number) => from + (to - from) * fraction;
    const used = new Set<number>();
    return {
      objects: current.objects.map(object => {
        // Object indices are draw order, not identity. Insertions/removals can
        // shift labels and arrows to different slots in the next frame.
        const match = matchingObject(next.objects, object, used, this.visualSpriteGroups, current.objects);
        if (match < 0) {
          const previousObjects = animation.frames[Math.floor(index) - 1]?.objects ?? [];
          const previous = previousObjects[matchingObject(previousObjects, object)];
          if (!previous || object.drawMode < 2 || object.effect >= previous.effect) return object;
          const dx = (object.left - previous.left) * fraction;
          const dy = (object.top - previous.top) * fraction;
          return { ...object, left: object.left + dx, right: object.right + dx,
            top: object.top + dy, bottom: object.bottom + dy, effect: mix(object.effect, 0) };
        }
        used.add(match);
        const following = next.objects[match];
        // Only interpolate the same sprite and compositor; cuts stay discrete.
        if (!following || following.drawMode !== object.drawMode) return object;
        // A sprite can be reused for a new effect at another location. Do not
        // turn a relocated, restarting effect into motion (3330's dots).
        const separatedX = Math.max(Math.min(object.left, object.right), Math.min(following.left, following.right))
          > Math.min(Math.max(object.left, object.right), Math.max(following.left, following.right));
        const separatedY = Math.max(Math.min(object.top, object.bottom), Math.min(following.top, following.bottom))
          > Math.min(Math.max(object.top, object.bottom), Math.max(following.top, following.bottom));
        const restarting = Math.abs(following.scaleX) > Math.abs(object.scaleX)
          || Math.abs(following.scaleY) > Math.abs(object.scaleY)
          || object.effect === 0 && following.effect > 0;
        if ((separatedX || separatedY) && restarting) return object;
        // Variant bitmaps have different sizes. Keep their centers aligned
        // while interpolating the current bitmap toward the next pose.
        const sprite = this.archive.sprites[object.sprite];
        const variant = object.sprite !== following.sprite;
        const halfWidth = variant ? sprite.width * following.scaleX / 2 : (following.right - following.left) / 2;
        const halfHeight = variant ? sprite.height * following.scaleY / 2 : (following.bottom - following.top) / 2;
        const centerX = (following.left + following.right) / 2;
        const centerY = (following.top + following.bottom) / 2;
        const turn = OBJECT_ROTATION_TURN;
        const rotationDelta = ((following.rotation - object.rotation + turn / 2) % turn + turn) % turn - turn / 2;
        return { ...object,
          left: mix(object.left, centerX - halfWidth), right: mix(object.right, centerX + halfWidth),
          top: mix(object.top, centerY - halfHeight), bottom: mix(object.bottom, centerY + halfHeight),
          scaleX: mix(object.scaleX, following.scaleX), scaleY: mix(object.scaleY, following.scaleY),
          effect: mix(object.effect, following.effect), rotation: object.rotation + rotationDelta * fraction,
        };
      }).concat(next.objects.flatMap((object, i) => {
        if (used.has(i) || object.drawMode < 2 || object.effect >= 16) return [];
        const afterObjects = animation.frames[Math.floor(index) + 2]?.objects ?? [];
        const after = afterObjects[matchingObject(afterObjects, object)];
        if (!after || after.effect <= object.effect) return [];
        const dx = (after.left - object.left) * (fraction - 1);
        const dy = (after.top - object.top) * (fraction - 1);
        return [{ ...object, left: object.left + dx, right: object.right + dx,
          top: object.top + dy, bottom: object.bottom + dy, effect: object.effect * fraction }];
      })),
      markers: current.markers.map(marker => {
        const following = next.markers.find(item => item.id === marker.id);
        return following ? { id: marker.id, x: mix(marker.x, following.x), y: mix(marker.y, following.y) } : marker;
      }),
    };
  }

  draw(target: Rgb565Framebuffer, x = 0, originY = target.height, scaleY = 1): void {
    const frame = this.visualFrame(target.visualElapsed);
    if (frame) drawVrpObjects(target, this.archive, this.animation, frame, x, originY, scaleY);
  }
}

const decodeSprite = (
  view: DataView,
  offset: number,
  end: number,
  palettes: readonly Uint16Array[],
  spriteIndex: number,
): VrpSprite => {
  if (offset + 16 > end || end > view.byteLength) throw new Error(`VRP sprite ${spriteIndex} header is truncated`);
  const width = readU32(view, offset + 4);
  const height = readU32(view, offset + 8);
  const paletteIndex = readU32(view, offset + 12);
  const palette = palettes[paletteIndex];
  if (!palette) throw new Error(`VRP sprite ${spriteIndex} uses missing palette ${paletteIndex}`);

  const pixels = new Uint16Array(width * height);
  const opaque = new Uint8Array(width * height);
  const runs: { skip: number; length: number }[][] = [];
  let cursor = offset + 16;
  for (let y = 0;y < height;y += 1) {
    const row: { skip: number; length: number }[] = [];
    runs.push(row);
    let x = 0;
    while (x < width) {
      if (cursor + 2 > end) throw new Error(`VRP sprite ${spriteIndex} row ${y} is truncated`);
      const transparent = view.getUint8(cursor);
      const literal = view.getUint8(cursor + 1);
      row.push({ skip: transparent, length: literal });
      cursor += 2;
      x += transparent;
      if (x + literal > width || cursor + literal > end) throw new Error(`VRP sprite ${spriteIndex} row ${y} is invalid`);
      for (let count = 0;count < literal;count += 1) {
        const destination = y * width + x;
        pixels[destination] = palette[view.getUint8(cursor)];
        opaque[destination] = 1;
        cursor += 1;
        x += 1;
      }
      if (transparent === 0 && literal === 0) throw new Error(`VRP sprite ${spriteIndex} row ${y} does not advance`);
    }
  }
  return { width, height, pixels, opaque, runs };
};

export const drawVrpFrameBottomUp = (
  target: Rgb565Framebuffer,
  archive: VrpArchive,
  animationIndex: number,
  frameIndex: number,
  offsetX = 0,
  originY = target.height,
  scaleY = 1,
): void => {
  const animation = archive.animations[animationIndex];
  const frame = animation?.frames[frameIndex];
  if (frame) drawVrpObjects(target, archive, animationIndex, frame, offsetX, originY, scaleY);
};

const drawVrpObjects = (
  target: Rgb565Framebuffer, archive: VrpArchive, animationIndex: number,
  frame: VrpFrame, offsetX: number, originY: number, scaleY: number,
): void => {
  for (const object of frame.objects) {
    const sprite = archive.sprites[object.sprite];
    if (!sprite) throw new Error(`VRP animation ${animationIndex} uses missing sprite ${object.sprite}`);
    const left = object.left + offsetX;
    const right = object.right + offsetX;
    const top = originY - object.bottom * scaleY;
    const bottom = originY - object.top * scaleY;
    const startX = Math.floor(object.scaleX >= 0 ? left : right);
    const startY = Math.floor(object.scaleY >= 0 ? top : bottom);
    target.blitTransformed(
      sprite,
      startX,
      startY,
      object.scaleX,
      object.scaleY * scaleY,
      (object.rotation * Math.PI * 2) / OBJECT_ROTATION_TURN,
      blendMode(object),
      object.effect,
    );
  }
};
