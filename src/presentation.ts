export type PresentationSprite = Readonly<{
  width: number; height: number; pixels: Uint16Array; opaque: Uint8Array; resourceKey?: string;
}>;
export type PresentationClip = Readonly<{ x: number; y: number; width: number; height: number }>;

/** Optional visual mirror; the native framebuffer and game coordinates stay unchanged. */
export interface FramebufferPresentation {
  clear(color: number): void;
  setPixel(x: number, y: number, color: number): void;
  blit(source: PresentationSprite, x: number, y: number): void;
  blitScaled(source: PresentationSprite, left: number, top: number, right: number, bottom: number, mode: number, effect: number): void;
  blitTransformed(source: PresentationSprite, x: number, y: number, scaleX: number, scaleY: number, rotation: number, mode: number, effect: number): void;
  glyph(character: string, x: number, y: number, color: number, clip?: PresentationClip): void;
}
