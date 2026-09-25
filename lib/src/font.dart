import 'dart:typed_data';
import '../framebuffer.dart';
import 'encoding.dart';

class BitmapFont {
  BitmapFont(this.bytes, [this.width = 8]);
  final Uint8List bytes;
  final int width;
  final _cache = <int, RenderSprite>{};
  RenderSprite glyph(int index, int color) =>
      _cache.putIfAbsent(index * 65536 + color, () {
        final v = ByteData.sublistView(bytes),
            p = ByteData.sublistView(bytes)
                .getUint32(4 + index * 4, Endian.little);
        final pixels = Uint16List(width * 12), opaque = Uint8List(width * 12);
        for (var row = 0; row < 12; row++) {
          final bits = width == 8
              ? v.getUint8(p + row)
              : v.getUint16(p + row * 2, Endian.little);
          for (var col = 0; col < width; col++) {
            if ((bits & (1 << col)) != 0) {
              pixels[row * width + col] = color;
              opaque[row * width + col] = 1;
            }
          }
        }
        return RenderSprite(width, 12, pixels, opaque, null);
      });
  void draw(Rgb565Framebuffer t, String text, int x, int y, int color,
      [int? outline]) {
    if (outline != null) {
      for (final (dx, dy) in [
        (1, 0),
        (-1, 0),
        (0, -1),
        (0, 1),
        (-1, -1),
        (1, 1)
      ]) {
        draw(t, text, x + dx, y + dy, outline);
      }
    }
    var cx = x;
    for (final c in text.codeUnits) {
      if (c >= 33 && c <= 126) t.blit(glyph(c - 33, color), cx, y);
      cx += 8;
    }
  }
}

class GameFont {
  GameFont(Uint8List korean, Uint8List english, Cp949 encoding)
      : hangul = BitmapFont(korean, 12),
        english = BitmapFont(english) {
    for (var i = 0; i < 51; i++) {
      indices[encoding.code(0xa4, 0xa1 + i)] = i;
    }
    for (var i = 0; i < 2350; i++) {
      indices[encoding.code(0xb0 + i ~/ 94, 0xa1 + i % 94)] = 51 + i;
    }
  }
  final BitmapFont hangul, english;
  final indices = <int, int>{};
  void draw(
      Rgb565Framebuffer t, String text, int x, int y, int width, int height,
      [int color = 0xffff, ({int x, int y, int width, int height})? clip]) {
    var cx = x, cy = y;
    final initial = color;
    final source = text.replaceAll('\r\n', '\n').replaceAll(r'\n', '\n');
    for (var i = 0; i < source.length; i++) {
      final c = source.codeUnitAt(i);
      if (c == 13) {
        color = {
              'D': 53203,
              'E': 65491,
              'F': 64716,
              'B': 31,
              'R': 0xf800,
              'g': 0x7bef,
              'V': 0x9999,
              'Y': 0xffe0,
              'U': initial
            }[source[++i]] ??
            initial;
        continue;
      }
      if (c == 10) {
        cx = x;
        cy += 14;
        continue;
      }
      final ascii = c < 128, advance = c < 128 ? 8 : 12;
      if (cx + advance > x + width) {
        cx = x;
        cy += 14;
      }
      if (cy >= y + height) break;
      if (c != 32) {
        final index = ascii ? c - 33 : indices[c];
        if (index != null && index >= 0) {
          final sprite = (ascii ? english : hangul).glyph(index, color);
          if (cy + 12 <= y + height && clip == null) {
            t.blit(sprite, cx, cy);
          } else {
            for (var row = 0; row < 12 && cy + row < y + height; row++) {
              for (var col = 0; col < advance; col++) {
                if (sprite.opaque[row * advance + col] != 0 &&
                    (clip == null ||
                        cx + col >= clip.x &&
                            cx + col < clip.x + clip.width &&
                            cy + row >= clip.y &&
                            cy + row < clip.y + clip.height)) {
                  t.setPixel(cx + col, cy + row, color);
                }
              }
            }
          }
        }
      }
      cx += advance;
    }
  }
}
