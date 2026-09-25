import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'chart.dart';
import 'scoring.dart';

class SaveData {
  SaveData(Uint8List? saved) {
    if (saved?.length == bytes.length) {
      bytes.setAll(0, saved!);
    } else {
      volume = 3;
      set(0x224, -1);
      bytes.setAll(0x210, utf8.encode('Emulator'));
    }
  }
  final bytes = Uint8List(0x334);
  late final view = ByteData.sublistView(bytes);
  int get(int offset) => view.getInt32(offset, Endian.little);
  void set(int offset, int value) =>
      view.setInt32(offset, value, Endian.little);
  void increment(int offset, [int amount = 1]) =>
      set(offset, get(offset) + amount);
  int get volume => get(0);
  set volume(int v) => set(0, v);
  bool get vibrationEnabled => view.getInt16(4, Endian.little) != 0;
  set vibrationEnabled(bool v) => view.setInt16(4, v ? 1 : 0, Endian.little);
  int get sync => get(8);
  set sync(int v) => set(8, v);
  int get delay => get(12);
  set delay(int v) => set(12, v);
  int get playTime => view.getInt64(0x2c4, Endian.little);
  set playTime(int v) => view.setInt64(0x2c4, v, Endian.little);
}

class MusicRecords {
  MusicRecords(List<RhythmChart> charts, Uint8List Function(String) read,
      Uint8List? saved)
      : bytes = Uint8List(4 + charts.length * 0x7c) {
    ByteData.sublistView(bytes).setInt32(0, charts.length, Endian.little);
    for (var i = 0; i < charts.length; i++) {
      final chart = charts[i], offset = 4 + i * 0x7c;
      final dest = Uint8List.sublistView(bytes, offset, offset + 0x7c);
      dest.setAll(0, utf8.encode(chart.id).take(31));
      final source = read(chart.id),
          length =
              ByteData.sublistView(read(chart.id)).getUint32(0, Endian.little);
      final text = latin1.decode(source.sublist(4, 4 + length));
      final title = RegExp(r'^#TITLE\s+"?([^\r\n"]+)',
              multiLine: true, caseSensitive: false)
          .firstMatch(text);
      if (title != null) {
        final start = title.start + title[0]!.indexOf(title[1]!);
        dest.setAll(0x40,
            source.sublist(4 + start, 4 + start + min(31, title[1]!.length)));
      }
      dest[0x60] = chart.keyCount;
      dest[0x61] = chart.level;
      final view = ByteData.sublistView(dest);
      for (var j = 0x64; j <= 0x6c; j += 2) {
        view.setInt16(j, 6, Endian.little);
      }
      _records[chart.id] = view;
    }
    if (saved != null && saved.length >= 4) {
      final count = ByteData.sublistView(saved).getInt32(0, Endian.little);
      if (count >= 0 && saved.length == 4 + count * 0x7c) {
        for (var i = 0; i < count; i++) {
          final b = saved.sublist(4 + i * 0x7c, 4 + (i + 1) * 0x7c);
          final end = b.sublist(0, 32).indexOf(0);
          final path = utf8.decode(b.sublist(0, end < 0 ? 32 : end),
              allowMalformed: true);
          final view = _records[path];
          if (view != null) {
            view.buffer
                .asUint8List(view.offsetInBytes + 0x62, 0x1a)
                .setAll(0, b.sublist(0x62));
          }
        }
      }
    }
  }
  final Uint8List bytes;
  final _records = <String, ByteData>{};
  int score(String path) => _records[path]!.getInt32(0x70, Endian.little);
  int combo(String path) => _records[path]!.getInt16(0x62, Endian.little);
  int grade(String path) => [0x64, 0x66, 0x68, 0x6a, 0x6c]
      .map((o) => _records[path]!.getInt16(o, Endian.little))
      .reduce(min);
  int complete(String path, GameScoring s, SaveData save,
      [bool mirror = false, bool random = false, int speed = 65536]) {
    final r = _records[path]!, rank = s.rank();
    r.setInt16(0x62, max(combo(path), s.maxCombo), Endian.little);
    r.setInt32(0x70, max(score(path), s.score), Endian.little);
    bool improve(int o) {
      if (r.getInt16(o, Endian.little) <= rank) return false;
      r.setInt16(o, rank, Endian.little);
      return true;
    }

    if (!(mirror && improve(0x64)) && !(random && improve(0x66))) improve(0x68);
    if (!(speed <= 65535 && improve(0x6a)) && speed > 131072) improve(0x6c);
    r.setInt32(0x78, 1, Endian.little);
    final trophy = awardTrophy(save);
    save.increment(0x2d0);
    save.increment(0x2cc);
    save.set(
        0x2e4,
        _records.values
            .fold(0, (int a, v) => a + v.getInt32(0x70, Endian.little)));
    save.increment(0x2e8 + rank * 4);
    final total = s.counts.reduce((a, b) => a + b);
    final ratio = total == 0 ? 0 : s.maxCombo * 100 ~/ total;
    save.increment(0x308 +
        (ratio >= 100
                ? 0
                : ratio >= 90
                    ? 1
                    : ratio >= 80
                        ? 2
                        : ratio >= 70
                            ? 3
                            : ratio >= 60
                                ? 4
                                : 5) *
            4);
    return trophy;
  }

  int awardTrophy(SaveData save) {
    int count(int o) =>
        _records.values.where((r) => r.getInt16(o, Endian.little) <= 1).length;
    int grades(int g) => _records.keys.where((p) => grade(p) == g).length;
    final candidates = <(int, int)>[
      (0, min(12, save.playTime ~/ 18000000)),
      (1, min(12, save.get(0x230) ~/ 5000)),
      (2, min(12, save.get(0x22c) ~/ 500)),
      (3, min(99, grades(1) ~/ 5)),
      (4, min(99, grades(0) ~/ 5)),
      (5, _records.keys.every((p) => grade(p) == 0) ? 1 : save.get(0x2a0)),
      (6, min(99, count(0x64) ~/ 5)),
      (7, min(99, count(0x66) ~/ 5)),
      (8, min(99, count(0x6a) ~/ 5)),
      (9, min(99, count(0x6c) ~/ 5)),
      (11, 0),
      (
        10,
        List.generate(11, (i) => save.get(0x260 + i * 4)).every((v) => v != 0)
            ? 1
            : save.get(0x2b4)
      )
    ];
    for (final (i, c) in candidates) {
      final o = 0x28c + i * 4, previous = save.get(0x28c + i * 4);
      save.set(o, c);
      if (c > previous) return i;
    }
    return -1;
  }
}
