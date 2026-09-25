import 'dart:convert';
import 'dart:typed_data';
import 'package:rhythmstar_flutter/framebuffer.dart';

class DisplayListRenderer {
  final screen = Rgb565Framebuffer(240, 320);
  final _sprites = <int, RenderSprite>{};
  void draw(Map<String, dynamic> packet) {
    for (final value in packet['sprites'] as List) {
      final bytes = base64Decode(value[3] as String);
      final data = ByteData.sublistView(bytes);
      final pixels = Uint16List(bytes.length ~/ 2);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = data.getUint16(i * 2, Endian.little);
      }
      final runs = value[5] as List?;
      _sprites[value[0] as int] = RenderSprite(
          value[1] as int,
          value[2] as int,
          pixels,
          base64Decode(value[4] as String),
          runs
              ?.map((row) => (row as List)
                  .map((r) => (r['skip'] as int, r['length'] as int))
                  .toList())
              .toList());
    }
    for (final raw in packet['frame'] as List) {
      final c = (raw as List).cast<num>();
      switch (c[0].toInt()) {
        case 5:
          screen.pixels.fillRange(c[2].toInt(), c[3].toInt(), c[1].toInt());
        case 0:
          screen.clear(c[1].toInt());
        case 1:
          for (var i = 1; i < c.length; i += 3) {
            screen.setPixel(c[i].toInt(), c[i + 1].toInt(), c[i + 2].toInt());
          }
        case 2:
          screen.blit(_sprites[c[1]]!, c[2].toInt(), c[3].toInt());
        case 3:
          screen.blitScaled(_sprites[c[1]]!, c[2].toDouble(), c[3].toDouble(),
              c[4].toDouble(), c[5].toDouble(), c[6].toInt(), c[7].toInt());
        case 4:
          screen.blitTransformed(
              _sprites[c[1]]!,
              c[2].toInt(),
              c[3].toInt(),
              c[4].toDouble(),
              c[5].toDouble(),
              c[6].toDouble(),
              c[7].toInt(),
              c[8].toInt());
        default:
          throw FormatException('Unknown drawing command ${c[0]}');
      }
    }
  }
}
