import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmstar_flutter/framebuffer.dart';

void main() {
  test('RGB565 converts to opaque RGBA', () {
    final buffer = Rgb565Framebuffer(3, 1);
    buffer.pixels.setAll(0, [0xf800, 0x07e0, 0x001f]);
    expect(buffer.toRgba(), [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]);
  });
}
