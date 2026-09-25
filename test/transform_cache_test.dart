import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmstar_flutter/framebuffer.dart';

RenderSprite sprite(Random random, int w, int h) {
  final pixels = Uint16List(w * h),
      opaque = Uint8List(w * h),
      runs = <List<(int, int)>>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      pixels[y * w + x] = random.nextInt(4) == 0 ? 0 : random.nextInt(65536);
      opaque[y * w + x] = random.nextInt(3) == 0 ? 0 : 1;
    }
    var x = 0;
    final row = <(int, int)>[];
    while (x < w) {
      final start = x;
      while (x < w && opaque[y * w + x] == 0) {
        x++;
      }
      final left = x;
      while (x < w && opaque[y * w + x] != 0) {
        x++;
      }
      row.add((left - start, x - left));
    }
    runs.add(row);
  }
  return RenderSprite(w, h, pixels, opaque, runs);
}

void main() {
  test(
      'cached transforms preserve clipping, black coverage, RLE rounding and destination blending',
      () {
    final random = Random(1234),
        cached = Rgb565Framebuffer(29, 31),
        reference = Rgb565Framebuffer(29, 31, cacheTransforms: false);
    Rgb565Framebuffer.clearTransformCache();
    final sources = List.generate(12,
        (_) => sprite(random, 1 + random.nextInt(15), 1 + random.nextInt(15)));
    const scales = [
      0.0,
      .25,
      .5,
      .75,
      1.0,
      1.25,
      1.5,
      2.0,
      3.0,
      -.5,
      -1.0,
      -2.0,
      1.0 / 3,
      1.000001,
      -1.000001
    ];
    for (var trial = 0; trial < 3000; trial++) {
      for (var i = 0; i < cached.pixels.length; i++) {
        final value = random.nextInt(65536);
        cached.pixels[i] = value;
        reference.pixels[i] = value;
      }
      final source = sources[trial % sources.length],
          sx = scales[random.nextInt(scales.length)],
          sy = scales[random.nextInt(scales.length)];
      final x = random.nextInt(55) - 20,
          y = random.nextInt(55) - 20,
          mode = random.nextInt(5),
          effect = random.nextInt(17);
      cached.blitTransformed(source, x, y, sx, sy, 0, mode, effect);
      reference.blitTransformed(source, x, y, sx, sy, 0, mode, effect);
      expect(cached.pixels, reference.pixels,
          reason: 'trial $trial, $sx/$sy, $x/$y, mode $mode effect $effect');
      expect(Rgb565Framebuffer.cacheBytes,
          lessThanOrEqualTo(Rgb565Framebuffer.cacheLimitBytes));
    }
  });
  test('cache evicts old transforms within its budget', () {
    Rgb565Framebuffer.clearTransformCache();
    final target = Rgb565Framebuffer(240, 320);
    for (var i = 0; i < 30; i++) {
      final s = RenderSprite(
          2, 1, Uint16List.fromList([i, i]), Uint8List.fromList([1, 1]), [
        [(0, 2)]
      ]);
      target.blitTransformed(s, 0, 0, 120, 320, 0);
      expect(target.pixels.every((p) => p == i), isTrue);
      expect(Rgb565Framebuffer.cacheBytes,
          lessThanOrEqualTo(Rgb565Framebuffer.cacheLimitBytes));
    }
    expect(Rgb565Framebuffer.cacheBytes, greaterThan(0));
  });
  test('solid overlay and reusable RGBA preserve every RGB565 color', () {
    final cached = Rgb565Framebuffer(256, 256),
        reference = Rgb565Framebuffer(256, 256, cacheTransforms: false);
    for (final (color, mode, effect) in [
      (0, 1, 8),
      (0, 1, 0),
      (0xffff, 3, 12),
      (0x592a, 2, 7)
    ]) {
      for (var i = 0; i < 65536; i++) {
        cached.pixels[i] = i;
        reference.pixels[i] = i;
      }
      final s = RenderSprite(
          1, 1, Uint16List.fromList([color]), Uint8List.fromList([1]), [
        [(0, 1)]
      ]);
      cached.blitTransformed(s, 0, 0, 256, 256, 0, mode, effect);
      reference.blitTransformed(s, 0, 0, 256, 256, 0, mode, effect);
      expect(cached.pixels, reference.pixels);
      final buffer = Int32List(65536);
      cached.writeRgba(buffer);
      expect(buffer.buffer.asUint8List(), reference.toRgba());
    }
  });
}
