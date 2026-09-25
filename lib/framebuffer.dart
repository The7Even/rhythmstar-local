import 'dart:math' as math;
import 'dart:typed_data';
import 'native_math.dart';

abstract interface class VrpSpriteLike {
  int get width;
  int get height;
  Uint16List get pixels;
  Uint8List get opaque;
}

class RenderSprite implements VrpSpriteLike {
  RenderSprite(this.width, this.height, this.pixels, this.opaque, this.runs);
  @override
  final int width, height;
  @override
  final Uint16List pixels;
  @override
  final Uint8List opaque;
  final List<List<(int, int)>>? runs;
}

/// Exact port of rhythmstar-web/src/framebuffer.ts, including native rounding.
class Rgb565Framebuffer {
  static const cacheEnabled =
      bool.fromEnvironment('RHYTHMSTAR_TRANSFORM_CACHE', defaultValue: true);
  static const cacheLimitBytes = 2 * 1024 * 1024;
  static final _scaled =
      <(RenderSprite, double, double), (RenderSprite, int)>{};
  static final _solidTables = <(int, int, int), Uint16List>{};
  static int _cacheBytes = 0;
  static int get cacheBytes => _cacheBytes;
  static void clearTransformCache() {
    _scaled.clear();
    _solidTables.clear();
    _cacheBytes = 0;
  }

  static const profileEnabled =
      bool.fromEnvironment('RHYTHMSTAR_RENDER_PROFILE');
  static final profile = <String, (int, int)>{};
  static void resetProfile() => profile.clear();
  Rgb565Framebuffer(this.width, this.height,
      {this.cacheTransforms = cacheEnabled})
      : pixels = Uint16List(width * height);
  final bool cacheTransforms;
  final int width, height;
  final Uint16List pixels;
  void clear([int color = 0]) =>
      pixels.fillRange(0, pixels.length, color & 0xffff);
  void setPixel(int x, int y, int color) {
    if (x >= 0 && y >= 0 && x < width && y < height) {
      pixels[y * width + x] = color & 0xffff;
    }
  }

  static int _channel(int s, int d, int mode, int effect) {
    final scaled = (s * effect / 16).floor();
    switch (mode) {
      case 1:
        return ((s * effect + d * (16 - effect)) / 16).floor();
      case 2:
        return math.min(31, scaled + (d * (31 - scaled) / 31).floor());
      case 3:
        return math.min(
            31, (d * scaled / 31).floor() + (d * (16 - effect) / 16).floor());
      case 4:
        return math.min(31, d + scaled);
      default:
        return s;
    }
  }

  static Int16List? _blendTable(int mode, int effect) {
    if (mode == 0) return null;
    final key = mode * 32 + effect;
    var table = _blendTables[key];
    if (table == null) {
      table = Int16List(1024);
      for (var a = 0; a < 32; a++) {
        for (var b = 0; b < 32; b++) {
          table[a * 32 + b] = _channel(a, b, mode, effect);
        }
      }
      _blendTables[key] = table;
    }
    return table;
  }

  @pragma('vm:prefer-inline')
  static int _blend(int s, int d, Int16List? table) {
    if (table == null) return s;
    return (table[(s >> 11) * 32 + (d >> 11)] << 11) |
        (table[((s >> 6) & 31) * 32 + ((d >> 6) & 31)] << 6) |
        table[(s & 31) * 32 + (d & 31)];
  }

  static final _blendTables = <int, Int16List>{};

  void blit(VrpSpriteLike source, int x, int y) {
    for (var sy = 0; sy < source.height; sy++) {
      final dy = y + sy;
      if (dy < 0 || dy >= height) continue;
      for (var sx = 0; sx < source.width; sx++) {
        final dx = x + sx, at = sy * source.width + sx;
        if (dx >= 0 && dx < width && source.opaque[at] != 0) {
          pixels[dy * width + dx] = source.pixels[at];
        }
      }
    }
  }

  void blitScaled(VrpSpriteLike source, double left, double top, double right,
      double bottom, int mode, int effect) {
    final table = _blendTable(mode, effect);
    final dl = math.min(left, right).floor(), dr = math.max(left, right).ceil();
    final dt = math.min(top, bottom).floor(), db = math.max(top, bottom).ceil();
    final w = dr - dl, h = db - dt;
    if (w == 0 || h == 0) return;
    for (var y = math.max(0, dt); y < math.min(height, db); y++) {
      var sy = math.min(source.height - 1, (y - dt) * source.height ~/ h);
      if (bottom < top) sy = source.height - 1 - sy;
      for (var x = math.max(0, dl); x < math.min(width, dr); x++) {
        var sx = math.min(source.width - 1, (x - dl) * source.width ~/ w);
        if (right < left) sx = source.width - 1 - sx;
        final at = sy * source.width + sx, dest = y * width + x;
        if (source.opaque[at] != 0) {
          pixels[dest] = _blend(source.pixels[at], pixels[dest], table);
        }
      }
    }
  }

  void blitTransformed(VrpSpriteLike source, int originX, int originY,
      double scaleX, double scaleY, double rotation,
      [int mode = 0, int effect = 16]) {
    if (!profileEnabled) {
      _blitTransformed(
          source, originX, originY, scaleX, scaleY, rotation, mode, effect);
      return;
    }
    final watch = Stopwatch()..start();
    _blitTransformed(
        source, originX, originY, scaleX, scaleY, rotation, mode, effect);
    final kind =
        '${rotation != 0 ? 'rotate' : scaleX.abs() == 1 && scaleY.abs() == 1 ? 'unit' : 'scale'}/$mode';
    final previous = profile[kind] ?? (0, 0);
    profile[kind] = (previous.$1 + 1, previous.$2 + watch.elapsedMicroseconds);
  }

  void _blitTransformed(VrpSpriteLike source, int originX, int originY,
      double scaleX, double scaleY, double rotation, int mode, int effect) {
    if (cacheTransforms &&
        rotation == 0 &&
        source.width == 1 &&
        source.height == 1) {
      if (source.opaque[0] == 0) return;
      final unit = (scaleX * scaleY * 65536).floor().abs() == 65536;
      _solidRect(originX, originY, unit ? 1 : scaleX.abs().floor(),
          unit ? 1 : scaleY.abs().floor(), source.pixels[0], mode, effect);
      return;
    }
    if (cacheTransforms && rotation == 0 && source is RenderSprite) {
      final unit = (scaleX * scaleY * 65536).floor().abs() == 65536;
      final mx = unit ? 1.0 : scaleX.abs(), my = unit ? 1.0 : scaleY.abs();
      final w = (source.width * mx).floor(), h = (source.height * my).floor();
      // Cache geometry only. Blending still uses this frame's destination.
      // Rotated forward mapping can hit one pixel repeatedly, so it is excluded.
      if ((mx != 1 || my != 1 || scaleX < 0) &&
          w > 0 &&
          h > 0 &&
          w <= 512 &&
          h <= 640 &&
          w * h <= 153600) {
        if (originX >= width ||
            originY >= height ||
            originX + w <= 0 ||
            originY + h <= 0) return;
        final key = (source, scaleX, scaleY);
        var entry = _scaled.remove(key);
        if (entry == null) {
          final sprite = _rasterizeScale(source, w, h, scaleX, scaleY);
          final bytes = w * h * 3 +
              h * 32 +
              sprite.runs!.fold<int>(0, (sum, row) => sum + row.length * 32);
          if (bytes > cacheLimitBytes) {
            _blitUnit(sprite, originX, originY, mode, effect);
            return;
          }
          while (_scaled.isNotEmpty && _cacheBytes + bytes > cacheLimitBytes) {
            final oldest = _scaled.remove(_scaled.keys.first)!;
            _cacheBytes -= oldest.$2;
          }
          entry = (sprite, bytes);
          _cacheBytes += bytes;
        }
        _scaled[key] = entry;
        _blitUnit(entry.$1, originX, originY, mode, effect);
        return;
      }
    }
    _blitUncached(
        source, originX, originY, scaleX, scaleY, rotation, mode, effect);
  }

  void _solidRect(
      int ox, int oy, int w, int h, int color, int mode, int effect) {
    final left = math.max(0, ox), right = math.min(width, ox + w);
    final top = math.max(0, oy), bottom = math.min(height, oy + h);
    if (left >= right || top >= bottom) return;
    if (mode == 0) {
      for (var y = top; y < bottom; y++) {
        pixels.fillRange(y * width + left, y * width + right, color);
      }
      return;
    }
    // The pause overlay is black at 8/16 opacity. Preserve the original
    // five-bit green blend, including its discarded low green bit.
    if (mode == 1 && effect == 8 && color == 0) {
      for (var y = top; y < bottom; y++) {
        for (var at = y * width + left; at < y * width + right; at++) {
          pixels[at] = (pixels[at] >> 1) & 0x7bcf;
        }
      }
      return;
    }
    final key = (mode, effect, color);
    var table = _solidTables.remove(key);
    if (table == null) {
      final channels = _blendTable(mode, effect)!;
      table = Uint16List(32768);
      for (var d = 0; d < table.length; d++) {
        table[d] = _blend(color, ((d & 0x7fe0) << 1) | (d & 31), channels);
      }
      if (_solidTables.length == 8) {
        _solidTables.remove(_solidTables.keys.first);
      }
    }
    _solidTables[key] = table;
    for (var y = top; y < bottom; y++) {
      for (var at = y * width + left; at < y * width + right; at++) {
        final d = pixels[at];
        pixels[at] = table[((d >> 1) & 0x7fe0) | (d & 31)];
      }
    }
  }

  static RenderSprite _rasterizeScale(
      RenderSprite source, int w, int h, double sx, double sy) {
    final raster = Rgb565Framebuffer(w, h);
    raster._blitUncached(source, 0, 0, sx, sy, 0, 0, 16);
    // Coverage is independent of color: opaque black must remain opaque.
    final coverage = Rgb565Framebuffer(w, h);
    final ones = RenderSprite(
        source.width,
        source.height,
        Uint16List(source.width * source.height)
          ..fillRange(0, source.width * source.height, 1),
        source.opaque,
        source.runs);
    coverage._blitUncached(ones, 0, 0, sx, sy, 0, 0, 16);
    final opaque = Uint8List(w * h), runs = <List<(int, int)>>[];
    for (var y = 0; y < h; y++) {
      final row = <(int, int)>[];
      var x = 0;
      while (x < w) {
        final start = x;
        while (x < w && coverage.pixels[y * w + x] == 0) {
          x++;
        }
        final skip = x - start, left = x;
        while (x < w && coverage.pixels[y * w + x] != 0) {
          opaque[y * w + x] = 1;
          x++;
        }
        row.add((skip, x - left));
      }
      runs.add(row);
    }
    return RenderSprite(w, h, raster.pixels, opaque, runs);
  }

  void _blitUnit(RenderSprite source, int ox, int oy, int mode, int effect) {
    final table = _blendTable(mode, effect);
    final data = source.pixels, runs = source.runs!;
    final top = math.max(0, -oy), bottom = math.min(source.height, height - oy);
    for (var y = top; y < bottom; y++) {
      var x = ox;
      final destRow = (oy + y) * width, sourceRow = y * source.width;
      for (final run in runs[y]) {
        x += run.$1;
        final left = math.max(0, x), right = math.min(width, x + run.$2);
        if (left < right) {
          var at = sourceRow + left - ox;
          if (table == null) {
            pixels.setRange(destRow + left, destRow + right, data, at);
          } else {
            for (var dest = destRow + left; dest < destRow + right; dest++) {
              final s = data[at++], d = pixels[dest];
              pixels[dest] = (table[(s >> 11) * 32 + (d >> 11)] << 11) |
                  (table[((s >> 6) & 31) * 32 + ((d >> 6) & 31)] << 6) |
                  table[(s & 31) * 32 + (d & 31)];
            }
          }
        }
        x += run.$2;
        if (x >= width) break;
      }
    }
  }

  void _blitUncached(VrpSpriteLike source, int originX, int originY,
      double scaleX, double scaleY, double rotation, int mode, int effect) {
    if (rotation != 0) {
      _rotated(
          source, originX, originY, scaleX, scaleY, rotation, mode, effect);
      return;
    }
    final table = _blendTable(mode, effect);
    final unitArea = (scaleX * scaleY * 65536).floor().abs() == 65536;
    final mx = unitArea ? 1.0 : scaleX.abs(),
        my = unitArea ? 1.0 : scaleY.abs();
    if (mx == 0 || my == 0) return;
    if (mx == 1 && my == 1 && (mode != 0 || scaleX < 0)) {
      final sw = source.width;
      final sourcePixels = source.pixels, opaque = source.opaque;
      for (var sy = math.max(0, -originY);
          sy < math.min(source.height, height - originY);
          sy++) {
        final row = (originY + sy) * width;
        for (var x = math.max(0, originX);
            x < math.min(width, originX + sw);
            x++) {
          final sx = scaleX < 0 ? sw - 1 - (x - originX) : x - originX;
          final at = sy * sw + sx;
          if (opaque[at] != 0) {
            pixels[row + x] = _blend(sourcePixels[at], pixels[row + x], table);
          }
        }
      }
      return;
    }
    if (mode == 0 &&
        mx == 1 &&
        my == 1 &&
        scaleX > 0 &&
        source is RenderSprite &&
        source.runs != null) {
      final sourcePixels = source.pixels;
      final runs = source.runs!;
      final w = source.width;
      for (var sy = math.max(0, -originY);
          sy < math.min(source.height, height - originY);
          sy++) {
        var sx = 0;
        final destRow = (originY + sy) * width;
        final sourceRow = sy * w;
        for (final run in runs[sy]) {
          sx += run.$1;
          final left = math.max(0, originX + sx);
          final right = math.min(width, originX + sx + run.$2);
          if (left < right) {
            pixels.setRange(destRow + left, destRow + right, sourcePixels,
                sourceRow + left - originX);
          }
          sx += run.$2;
        }
      }
      return;
    }
    var dy = originY;
    var rowFraction = 0.0;
    for (var sy = 0; sy < source.height; sy++) {
      rowFraction += my;
      final rows = rowFraction.floor();
      rowFraction -= rows;
      var dx = scaleX < 0 ? originX + (source.width * mx).floor() - 1 : originX;
      var fraction = 0.0;
      var sx = 0;
      final List<(int, int)>? runs =
          source is RenderSprite && source.runs != null
              ? source.runs![sy]
              : null;
      for (final run in runs ?? [(0, source.width)]) {
        fraction += run.$1 * mx;
        final skipped = fraction.floor();
        fraction -= skipped;
        dx += scaleX < 0 ? -skipped : skipped;
        sx += run.$1;
        fraction += run.$2 * mx;
        final end = dx + (scaleX < 0 ? -1 : 1) * fraction.floor();
        fraction -= fraction.floor();
        var pixelFraction = 0.0;
        for (var i = 0; i < run.$2; i++, sx++) {
          pixelFraction += mx;
          final columns = pixelFraction.floor();
          pixelFraction -= columns;
          final at = sy * source.width + sx;
          if (source.opaque[at] != 0 && columns > 0 && rows > 0) {
            final left = math.max(0, scaleX < 0 ? dx - columns + 1 : dx);
            final right = math.min(width, scaleX < 0 ? dx + 1 : dx + columns);
            final top = math.max(0, dy), bottom = math.min(height, dy + rows);
            if (left < right && top < bottom) {
              final color = source.pixels[at];
              for (var y = top; y < bottom; y++) {
                final start = y * width + left, end = y * width + right;
                if (mode == 0) {
                  pixels.fillRange(start, end, color);
                } else {
                  for (var dest = start; dest < end; dest++) {
                    pixels[dest] = _blend(color, pixels[dest], table);
                  }
                }
              }
            }
          }
          dx += (scaleX < 0 ? -1 : 1) * columns;
        }
        dx = end;
      }
      dy += rows;
    }
  }

  void _rotated(VrpSpriteLike source, int ox, int oy, double sx, double sy,
      double rotation, int mode, int effect) {
    final table = _blendTable(mode, effect);
    final angle =
        ((rotation * 65536 / (2 * math.pi) + 0.5).floor() * 411774 / 65536)
            .floor();
    final cx = (sx * nativeCosine(angle)).truncate(),
        sinX = (sx * nativeSine(angle)).truncate();
    final sinY = (sy * nativeCosine(angle + 102943)).truncate(),
        cy = (sy * nativeSine(angle + 102943)).truncate();
    for (var y = 0; y < source.height; y++) {
      final rx = ox * 65536 + y * sinY, ry = oy * 65536 + y * cy;
      for (var x = 0; x < source.width; x++) {
        final at = y * source.width + x;
        if (source.opaque[at] == 0) continue;
        final dx = ((rx + x * cx) / 65536).floor(),
            dy = ((ry + x * sinX) / 65536).floor();
        if (dx < 0 || dy < 0 || dx >= width || dy >= height) continue;
        final dest = dy * width + dx;
        pixels[dest] = _blend(source.pixels[at], pixels[dest], table);
      }
    }
  }

  Uint8List toRgba() {
    // Signed opaque RGBA values fit ARMv7's small integers and avoid boxing.
    final out = Int32List(width * height);
    writeRgba(out);
    return out.buffer.asUint8List();
  }

  /// Caller-owned staging memory; copy/transfer it before the next write.
  void writeRgba(Int32List out) {
    if (out.length != pixels.length) throw ArgumentError('RGBA buffer size');
    final colors = _rgbaTable;
    for (var i = 0; i < pixels.length; i++) {
      out[i] = colors[pixels[i]];
    }
  }

  static final _rgbaTable = Int32List.fromList(List.generate(65536, (p) {
    final r = ((p >> 11) * 255 / 31).round();
    final g = (((p >> 5) & 63) * 255 / 63).round();
    final b = ((p & 31) * 255 / 31).round();
    return Endian.host == Endian.little
        ? r | (g << 8) | (b << 16) | -16777216
        : (r << 24) | (g << 16) | (b << 8) | 255;
  }));
}
