import manifest from '../assets/upscaled/manifest.json';
import gradients from '../assets/upscaled/vector-ui-gradients.json';
import laneGradients from '../assets/upscaled/lane-press-gradients.json';
import type { PresentationSprite } from './presentation';

// Stops remain continuous even when VRP stretches a one-pixel source strip.
const gradientStops = new Map([...gradients.gradients, ...laneGradients.gradients.map(gradient => ({
  ...gradient, stops: fadeLaneTop(gradient.stops),
}))].map(gradient => [gradient.key, {
  horizontal: gradient.horizontal,
  stops: gradient.stops.map(stop => [Number(stop[0]), String(stop[1])] as const),
}]));

function fadeLaneTop(stops: (string | number)[][]): (string | number)[][] {
  const fadeEnd = .3;
  const faded: (string | number)[][] = [];
  // Smoothstep removes the hard top edge without introducing a new edge at
  // the end of the fade. Sample the original color ramp so its hue is retained.
  for (let step = 0; step <= 24; step++) {
    const t = step / 24;
    const position = t * fadeEnd;
    const index = stops.findIndex(stop => Number(stop[0]) >= position);
    const right = stops[Math.max(1, index)];
    const left = stops[Math.max(1, index) - 1];
    const mix = (position - Number(left[0])) / (Number(right[0]) - Number(left[0]));
    const rgb = [1, 3, 5].map(offset => {
      const a = parseInt(String(left[1]).slice(offset, offset + 2), 16);
      const b = parseInt(String(right[1]).slice(offset, offset + 2), 16);
      return Math.round(a + (b - a) * mix);
    });
    faded.push([position, `rgba(${rgb.join(',')},${t * t * (3 - 2 * t)})`]);
  }
  return [...faded, ...stops.filter(stop => Number(stop[0]) > fadeEnd)];
}
const resourceKeys = new Map(manifest.refs.map(ref => [`${ref.archive}:${ref.sprite}`, ref.key]));
const arrowKey = 'a9c9b0e8cf7a6d16';

/** Draw at the current VRP transform, so gradients and glyphs stay scalable. */
export function drawVectorUi(context: CanvasRenderingContext2D, sprite: PresentationSprite): boolean {
  const key = sprite.resourceKey && resourceKeys.get(sprite.resourceKey);
  if (!key) return false;
  const gradient = gradientStops.get(key);
  if (gradient) {
    const fill = context.createLinearGradient(0, 0, gradient.horizontal ? sprite.width : 0, gradient.horizontal ? 0 : sprite.height);
    for (const [position, color] of gradient.stops) fill.addColorStop(position, color);
    context.fillStyle = fill;
    context.fillRect(0, 0, sprite.width, sprite.height);
    return true;
  }
  if (key === arrowKey) {
    context.fillStyle = '#ffffff';
    context.beginPath();
    context.moveTo(.35, sprite.height / 2);
    context.lineTo(sprite.width - .35, .35);
    context.lineTo(sprite.width - .35, sprite.height - .35);
    context.closePath(); context.fill();
    return true;
  }
  return false;
}
