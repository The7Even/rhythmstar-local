import type { PresentationSprite } from './presentation';

// Catmull–Rom cubic convolution, with pixel centers aligned on both axes.
function kernel(distance: number): number {
  const x = Math.abs(distance);
  if (x < 1) return (1.5 * x - 2.5) * x * x + 1;
  if (x < 2) return ((-.5 * x + 2.5) * x - 4) * x + 2;
  return 0;
}

/** Runtime-only 2x resampling. Premultiplied color avoids transparent-edge halos. */
export function bicubic2x(source: PresentationSprite): Uint8ClampedArray {
  const { width, height, pixels, opaque } = source;
  const outputWidth = width * 2, outputHeight = height * 2;
  const horizontal = new Float32Array(outputWidth * height * 4);
  for (let y = 0; y < height; y++) for (let x = 0; x < outputWidth; x++) {
    const sx = (x + .5) / 2 - .5, base = Math.floor(sx);
    const offset = (y * outputWidth + x) * 4;
    for (let tap = -1; tap <= 2; tap++) {
      const index = y * width + Math.max(0, Math.min(width - 1, base + tap));
      if (!opaque[index]) continue;
      const weight = kernel(sx - base - tap), color = pixels[index];
      horizontal[offset] += weight * (color >>> 11) * 255 / 31;
      horizontal[offset + 1] += weight * ((color >>> 5) & 63) * 255 / 63;
      horizontal[offset + 2] += weight * (color & 31) * 255 / 31;
      horizontal[offset + 3] += weight;
    }
  }
  const output = new Uint8ClampedArray(outputWidth * outputHeight * 4);
  for (let y = 0; y < outputHeight; y++) for (let x = 0; x < outputWidth; x++) {
    const sy = (y + .5) / 2 - .5, base = Math.floor(sy);
    let red = 0, green = 0, blue = 0, alpha = 0;
    for (let tap = -1; tap <= 2; tap++) {
      const offset = (Math.max(0, Math.min(height - 1, base + tap)) * outputWidth + x) * 4;
      const weight = kernel(sy - base - tap);
      red += horizontal[offset] * weight;
      green += horizontal[offset + 1] * weight;
      blue += horizontal[offset + 2] * weight;
      alpha += horizontal[offset + 3] * weight;
    }
    const offset = (y * outputWidth + x) * 4;
    if (alpha <= 0) continue;
    output[offset] = red / alpha;
    output[offset + 1] = green / alpha;
    output[offset + 2] = blue / alpha;
    output[offset + 3] = Math.min(1, alpha) * 255;
  }
  return output;
}
