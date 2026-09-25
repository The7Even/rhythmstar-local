import 'dart:math' as math;
import 'dart:typed_data';
import '../framebuffer.dart';

class VrpObject {
  VrpObject(this.sprite, this.scaleX, this.scaleY, this.drawMode, this.effect,
      this.rotation, this.left, this.right, this.top, this.bottom);
  final int sprite, drawMode, effect, rotation;
  final double scaleX, scaleY, left, right, top, bottom;
}

class VrpMarker {
  VrpMarker(this.id, this.x, this.y);
  final int id;
  final double x, y;
}

class VrpFrame {
  VrpFrame(this.objects, this.markers);
  final List<VrpObject> objects;
  final List<VrpMarker> markers;
  VrpMarker? marker(int id) {
    for (final m in markers) {
      if (m.id == id) return m;
    }
    return null;
  }
}

class VrpAnimation {
  VrpAnimation(this.firstFrame, this.durationTicks, this.frames);
  final int firstFrame, durationTicks;
  final List<VrpFrame> frames;
  VrpFrame? frame(int index) =>
      index >= 0 && index < frames.length ? frames[index] : null;
}

class VrpArchive {
  VrpArchive(this.sprites, this.animations);
  final List<RenderSprite> sprites;
  final List<VrpAnimation?> animations;
  VrpAnimation? animation(int id) =>
      id >= 0 && id < animations.length ? animations[id] : null;
  VrpFrame? frame(int id, int index) => animation(id)?.frame(index);
}

VrpArchive parseVrp(Uint8List bytes) {
  final v = ByteData.sublistView(bytes);
  int u32(int p) => v.getUint32(p, Endian.little);
  int i16(int p) => v.getInt16(p, Endian.little);
  if (bytes.length < 36 ||
      u32(0) != 0x0ab60000 ||
      u32(4) != 0x21000 ||
      u32(8) != bytes.length) throw const FormatException('Invalid VRP header');
  final pt = u32(24), st = u32(28), spriteEnd = u32(32);
  final palettes = List.generate(u32(pt), (i) {
    final at = u32(pt + 4 + i * 4);
    return Uint16List.fromList(
        List.generate(256, (j) => v.getUint16(at + 4 + j * 2, Endian.little)));
  });
  final offsets = List.generate(u32(st), (i) => u32(st + 4 + i * 4));
  final sprites = List.generate(offsets.length, (index) {
    final offset = offsets[index],
        end = index + 1 < offsets.length ? offsets[index + 1] : spriteEnd;
    if (offset + 16 > end || end > bytes.length) {
      throw const FormatException('Truncated VRP sprite');
    }
    final width = u32(offset + 4),
        height = u32(offset + 8),
        palette = palettes[u32(offset + 12)];
    final pixels = Uint16List(width * height),
        opaque = Uint8List(width * height),
        runs = <List<(int, int)>>[];
    var cursor = offset + 16;
    for (var y = 0; y < height; y++) {
      final row = <(int, int)>[];
      runs.add(row);
      var x = 0;
      while (x < width) {
        if (cursor + 2 > end) throw const FormatException('Truncated VRP row');
        final skip = bytes[cursor++], length = bytes[cursor++];
        row.add((skip, length));
        x += skip;
        if (x + length > width || cursor + length > end || skip + length == 0) {
          throw const FormatException('Invalid VRP row');
        }
        for (var n = 0; n < length; n++) {
          final at = y * width + x++;
          pixels[at] = palette[bytes[cursor++]];
          opaque[at] = 1;
        }
      }
    }
    return RenderSprite(width, height, pixels, opaque, runs);
  });
  final at = u32(16);
  final animations = List<VrpAnimation?>.generate(u32(at), (index) {
    try {
      final p = u32(at + 4 + index * 4);
      if (p == 0) return null;
      final duration = u32(p), first = u32(p + 4), count = u32(p + 8);
      if (p + 12 + count * 4 > bytes.length) return null;
      final frames = List.generate(count, (index) {
        final f = u32(p + 12 + index * 4), objectsAt = u32(f + 4);
        final objects = List.generate(i16(f), (i) {
          final o = objectsAt + i * 20;
          return VrpObject(
              u32(o),
              i16(o + 4) / 64,
              i16(o + 6) / 64,
              bytes[o + 8],
              bytes[o + 9] & 31,
              i16(o + 10),
              i16(o + 12) / 16,
              i16(o + 14) / 16,
              -i16(o + 18) / 16,
              -i16(o + 16) / 16);
        });
        final ma = u32(f + 8);
        return VrpFrame(
            objects,
            List.generate(
                i16(f + 2),
                (i) => VrpMarker(i16(ma + i * 8 + 6), i16(ma + i * 8 + 2) / 16,
                    -i16(ma + i * 8 + 4) / 16)));
      });
      return VrpAnimation(first, duration, frames);
    } on RangeError {
      return null;
    }
  });
  return VrpArchive(sprites, animations);
}

class VrpPlayer {
  VrpPlayer(this.archive, this.animation, [this.looping = true]);
  final VrpArchive archive;
  int animation, frame = 0, position = 0;
  bool looping;
  VrpFrame? get current => archive.frame(
      animation, frame - (archive.animation(animation)?.firstFrame ?? 0));
  void select(int id, [bool loop = true]) {
    animation = id;
    looping = loop;
    position = 0;
    frame = 0;
  }

  bool update(int ms) {
    final a = archive.animation(animation);
    if (a == null || a.frames.isEmpty || a.durationTicks == 0) return true;
    position += (ms * 65536 / 1000).floor();
    final complete = position > a.durationTicks;
    if (complete) {
      position = looping ? position - a.durationTicks : a.durationTicks;
    }
    frame = math.min(
        a.firstFrame + a.frames.length - 1,
        (position * (a.firstFrame + a.frames.length) / a.durationTicks)
            .floor());
    return complete;
  }

  void draw(Rgb565Framebuffer target,
      [num x = 0, num? originY, num scaleY = 1]) {
    final a = archive.animation(animation);
    if (a != null) {
      drawVrpFrame(
          target, archive, animation, frame - a.firstFrame, x, originY, scaleY);
    }
  }
}

void drawVrpFrame(
    Rgb565Framebuffer target, VrpArchive archive, int id, int frame,
    [num x = 0, num? originY, num scaleY = 1]) {
  final f = archive.frame(id, frame);
  if (f == null) return;
  final y = originY ?? target.height;
  for (final o in f.objects) {
    final left = o.left + x,
        right = o.right + x,
        top = y - o.bottom * scaleY,
        bottom = y - o.top * scaleY;
    target.blitTransformed(
        archive.sprites[o.sprite],
        (o.scaleX >= 0 ? left : right).floor(),
        (o.scaleY >= 0 ? top : bottom).floor(),
        o.scaleX,
        o.scaleY * scaleY,
        o.rotation * math.pi * 2 / 65536,
        o.drawMode == 1 && o.effect == 16 && o.rotation == 0 ? 0 : o.drawMode,
        o.effect);
  }
}

Uint8List musPicture(Uint8List bytes) {
  final view = ByteData.sublistView(bytes),
      start = ByteData.sublistView(bytes).getUint32(0, Endian.little) + 4;
  if (view.getUint32(start, Endian.little) != 0xab0c0de0) {
    throw const FormatException('Invalid MUS picture');
  }
  final out = Uint8List(view.getUint32(start + 4, Endian.little));
  var input = start + 12, cursor = 0, bits = 0, lastOffset = 1;
  int byte() => bytes[input++];
  int bit() {
    bits = (bits & 0x7f) != 0 ? bits * 2 : byte() * 2 + 1;
    return (bits >> 8) & 1;
  }

  while (cursor < out.length) {
    if (bit() != 0) {
      out[cursor++] = byte();
      continue;
    }
    var offset = 1;
    do {
      offset = offset * 2 + bit();
    } while (bit() == 0);
    if (offset == 2) {
      offset = lastOffset;
    } else {
      offset = (offset - 3) * 256 + byte();
      if (offset == 0xffffffff) break;
      lastOffset = ++offset;
    }
    var length = bit() * 2 + bit();
    if (length == 0) {
      length = 1;
      do {
        length = length * 2 + bit();
      } while (bit() == 0);
      length += 2;
    }
    if (offset > 0xd00) length++;
    length++;
    if (offset > cursor || cursor + length > out.length) {
      throw const FormatException('Invalid MUS picture reference');
    }
    while (length-- > 0) {
      out[cursor] = out[cursor - offset];
      cursor++;
    }
  }
  return out;
}
