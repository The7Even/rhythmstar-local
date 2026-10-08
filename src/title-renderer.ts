import type { VrpArchive, VrpFrame, VrpObject } from './vrp';

import { loadRemasteredImage } from './remastered-images';

/** High-resolution presentation of the existing title animation poses. */
export class TitleRenderer {
  private constructor(readonly images: readonly HTMLImageElement[]) {}

  static async load(): Promise<TitleRenderer> {
    const images = await Promise.all(Array.from({ length: 19 }, (_, id) =>
      loadRemasteredImage(`title/sprite-${String(id).padStart(2, '0')}.png`)));
    return new TitleRenderer(images);
  }

  draw(canvas: HTMLCanvasElement, archive: VrpArchive, frames: readonly (VrpFrame | undefined)[], elapsed: number, showVersion: boolean): void {
    if (canvas.width !== 480 || canvas.height !== 640) {canvas.width = 480;canvas.height = 640;}
    const context = canvas.getContext('2d')!;
    context.setTransform(2, 0, 0, 2, 0, 0);
    context.globalCompositeOperation = 'source-over';context.globalAlpha = 1;
    context.fillStyle = 'black';context.fillRect(0, 0, 240, 320);
    const ship = frames[3]?.objects.find(object => object.sprite === 2);
    frames.forEach((frame, index) => {
      for (const object of frame?.objects ?? []) {
        if (object.sprite === 17) continue;
        const sprite = archive.sprites[object.sprite];
        context.save();
        context.translate(object.scaleX >= 0 ? object.left : object.right, 320 - (object.scaleY >= 0 ? object.bottom : object.top));
        context.rotate(object.rotation * Math.PI * 2 / 65536);
        context.scale(object.scaleX, object.scaleY);
        if (object.scaleX < 0) context.translate(-sprite.width, 0);
        if (object.scaleY < 0) context.translate(0, -sprite.height);
        context.globalCompositeOperation = object.drawMode === 2 ? 'screen' : object.drawMode === 3 ? 'multiply' : object.drawMode === 4 ? 'lighter' : 'source-over';
        context.globalAlpha = object.effect / 16;
        context.imageSmoothingEnabled = true;
        context.drawImage(this.images[object.sprite], 0, 0, sprite.width, sprite.height);
        context.restore();
      }
      if (ship && index === 3) { this.light(context, ship, elapsed, 0);this.light(context, ship, elapsed, 1); }
      if (ship && index === 5) this.light(context, ship, elapsed, 2);
    });
    if (showVersion) {
      context.save();
      // Rasterize scalable text directly into the 2x title canvas.
      context.font = 'bold 12px Arial, sans-serif';
      context.textBaseline = 'top';
      context.lineJoin = 'round';
      context.lineWidth = 1.5;
      context.strokeStyle = 'black';
      context.fillStyle = 'white';
      context.strokeText('Ver Remastered', 2, 28);
      context.fillText('Ver Remastered', 2, 28);
      context.restore();
    }
    context.setTransform(1, 0, 0, 1, 0, 0);
  }

  private light(context: CanvasRenderingContext2D, ship: VrpObject, elapsed: number, index: number): void {
    // Window centers measured in the approved artwork, in game coordinates.
    const windows = [[24.1321,32.3149],[40.1362,43.2922],[30.1147,39.9736]];
    const [x, y] = windows[index];
    const sweep = (1 - Math.cos(elapsed / 2000 * Math.PI * 2 - (index === 1 ? .55 : 0))) / 2;
    const angle = index === 0 ? 25 + 25 * sweep : index === 1 ? 36 * sweep : 46.8 - 25.2 * sweep;
    context.save();context.translate(ship.left + x * ship.scaleX, 320 - ship.bottom + y * ship.scaleY);
    context.rotate(angle * Math.PI / 180);context.globalCompositeOperation = 'screen';
    const gradient = context.createLinearGradient(0, 0, 0, 340);
    const strength = .18 + .10 * sweep;
    gradient.addColorStop(0, `rgba(255,252,220,${strength})`);
    gradient.addColorStop(.35, `rgba(255,252,230,${strength * .7})`);
    gradient.addColorStop(1, 'rgba(255,255,245,0)');
    context.fillStyle = gradient;context.beginPath();context.moveTo(-2.5, 0);context.lineTo(2.5, 0);
    context.lineTo(43, 340);context.lineTo(-43, 340);context.closePath();context.fill();context.restore();
  }
}
