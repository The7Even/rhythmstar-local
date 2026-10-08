import manifest from '../assets/upscaled/manifest.json';
import fontManifest from '../assets/upscaled/fonts/manifest.json';
import { loadRemasteredImage } from './remastered-images';
import type { FramebufferPresentation, PresentationClip, PresentationSprite } from './presentation';
import { drawVectorUi } from './vector-ui';
import { isMusPicture } from './mus-presentation';
import { bicubic2x } from './bicubic';

const rgb = (value: number): string => `rgb(${(value >>> 11) * 255 / 31},${((value >>> 5) & 63) * 255 / 63},${(value & 31) * 255 / 31})`;

export class UpscaledRenderer implements FramebufferPresentation {
  readonly canvas = document.createElement('canvas');
  readonly context: CanvasRenderingContext2D;
  readonly #originals = new WeakMap<PresentationSprite, HTMLCanvasElement>();
  readonly #glyphs = new Map(fontManifest.glyphs.map(glyph => [glyph.character, glyph]));
  readonly #coloredGlyphs = new Map<string, HTMLCanvasElement>();

  private constructor(readonly images: ReadonlyMap<string, HTMLImageElement>, readonly font: HTMLImageElement) {
    this.canvas.width = 480; this.canvas.height = 640;
    this.context = this.canvas.getContext('2d')!;
    this.context.setTransform(2, 0, 0, 2, 0, 0);
  }

  static async load(): Promise<UpscaledRenderer> {
    const entries = await Promise.all(manifest.unique.map(async sprite => {
      const image = await loadRemasteredImage(`sprites/${sprite.key}.png`);
      return [sprite.key, image] as const;
    }));
    const byKey = new Map(entries);
    const images = new Map<string, HTMLImageElement>();
    for (const ref of manifest.refs) {
      if (!ref.archive.toLowerCase().endsWith('.vrp') || ref.archive.toLowerCase().startsWith('mus/')) throw new Error('Only fixed VRP resources may be upscaled');
      images.set(`${ref.archive}:${ref.sprite}`, byKey.get(ref.key)!);
    }
    const font = await loadRemasteredImage('fonts/glyphs-2x.png');
    return new UpscaledRenderer(images, font);
  }

  clear(color: number): void {
    const ctx = this.context;
    ctx.setTransform(2, 0, 0, 2, 0, 0);
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = rgb(color); ctx.fillRect(0, 0, 240, 320);
  }

  setPixel(x: number, y: number, color: number): void {
    this.context.fillStyle = rgb(color); this.context.fillRect(x, y, 1, 1);
  }

  #image(source: PresentationSprite): CanvasImageSource {
    if (source.resourceKey) {
      const replacement = this.images.get(source.resourceKey);
      if (!replacement) throw new Error(`Missing upscaled VRP sprite: ${source.resourceKey}`);
      // The image supplies both its colors and coverage. Never reconstruct or
      // clip a fixed sprite with the native opaque/RLE data, even on fallback.
      return replacement;
    }
    // MUS files remain untouched. Cache a cubic resampling of decoded artwork
    // for presentation only; other dynamic sprites keep their original pixels.
    let canvas = this.#originals.get(source);
    if (!canvas) {
      const cubic = isMusPicture(source), scale = cubic ? 2 : 1;
      canvas = document.createElement('canvas'); canvas.width = source.width * scale; canvas.height = source.height * scale;
      const ctx = canvas.getContext('2d')!;
      const image = ctx.createImageData(canvas.width, canvas.height);
      if (cubic) image.data.set(bicubic2x(source));
      else for (let index = 0; index < source.pixels.length; index++) {
        const pixel = source.pixels[index], offset = index * 4;
        image.data[offset] = (pixel >>> 11) * 255 / 31;
        image.data[offset + 1] = ((pixel >>> 5) & 63) * 255 / 63;
        image.data[offset + 2] = (pixel & 31) * 255 / 31;
        image.data[offset + 3] = source.opaque[index] ? 255 : 0;
      }
      ctx.putImageData(image, 0, 0); this.#originals.set(source, canvas);
    }
    return canvas;
  }

  #mode(mode: number, effect: number): void {
    this.context.globalCompositeOperation = mode === 2 ? 'screen' : mode === 3 ? 'multiply' : mode === 4 ? 'lighter' : 'source-over';
    this.context.globalAlpha = mode === 0 ? 1 : Math.max(0, Math.min(1, effect / 16));
  }

  blit(source: PresentationSprite, x: number, y: number): void {
    this.blitScaled(source, x, y, x + source.width, y + source.height, 0, 16);
  }

  blitScaled(source: PresentationSprite, left: number, top: number, right: number, bottom: number, mode: number, effect: number): void {
    const ctx = this.context; ctx.save(); this.#mode(mode, effect);
    ctx.translate(left, top); ctx.scale((right - left) / source.width, (bottom - top) / source.height);
    ctx.imageSmoothingEnabled = isMusPicture(source) || Boolean(source.resourceKey && this.images.has(source.resourceKey));
    if (!drawVectorUi(ctx, source)) ctx.drawImage(this.#image(source), 0, 0, source.width, source.height);
    ctx.restore();
  }

  blitTransformed(source: PresentationSprite, x: number, y: number, scaleX: number, scaleY: number, rotation: number, mode: number, effect: number): void {
    if (!scaleX || !scaleY) return;
    const ctx = this.context; ctx.save(); this.#mode(mode, effect);
    if (rotation === 0) {
      // Retain the native unit-area shortcut and unrotated Y traversal.
      const unit = Math.abs(Math.floor(scaleX * scaleY * 65536)) === 65536;
      const sx = unit ? 1 : Math.abs(scaleX), sy = unit ? 1 : Math.abs(scaleY);
      ctx.translate(x + (scaleX < 0 ? source.width * sx : 0), y);
      ctx.scale(scaleX < 0 ? -sx : sx, sy);
    } else {
      ctx.translate(x, y); ctx.rotate(rotation); ctx.scale(scaleX, scaleY);
    }
    ctx.imageSmoothingEnabled = isMusPicture(source) || Boolean(source.resourceKey && this.images.has(source.resourceKey));
    if (!drawVectorUi(ctx, source)) ctx.drawImage(this.#image(source), 0, 0, source.width, source.height);
    ctx.restore();
  }

  glyph(character: string, x: number, y: number, color: number, clip?: PresentationClip): void {
    const glyph = this.#glyphs.get(character); if (!glyph) return;
    const key = `${character}:${color}`;
    let image = this.#coloredGlyphs.get(key);
    if (!image) {
      image = document.createElement('canvas'); image.width = glyph.width; image.height = glyph.height;
      const context = image.getContext('2d')!;
      context.drawImage(this.font, glyph.x, glyph.y, glyph.width, glyph.height, 0, 0, glyph.width, glyph.height);
      context.globalCompositeOperation = 'source-in'; context.fillStyle = rgb(color); context.fillRect(0, 0, glyph.width, glyph.height);
      this.#coloredGlyphs.set(key, image);
    }
    const ctx = this.context; ctx.save();
    if (clip) { ctx.beginPath(); ctx.rect(clip.x, clip.y, clip.width, clip.height); ctx.clip(); }
    ctx.imageSmoothingEnabled = true; ctx.drawImage(image, x, y, glyph.width / 2, glyph.height / 2); ctx.restore();
  }
}
