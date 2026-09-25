import 'dart:typed_data';
import 'encoding.dart';

class SequenceEvent {
  SequenceEvent(this.channel, this.value, this.holdIndex, this.speed,
      this.holdSpeed, this.timeMs, this.spawnMs);
  int channel, value, holdIndex, speed, holdSpeed, timeMs, spawnMs;
  SequenceEvent copy({int? channel, int correction = 0}) => SequenceEvent(
      channel ?? this.channel,
      value,
      holdIndex,
      speed,
      holdSpeed,
      timeMs + correction,
      spawnMs + correction);
  List<int> get values =>
      [channel, value, holdIndex, speed, holdSpeed, timeMs, spawnMs];
}

class ChartSequence {
  ChartSequence(this.bpm, this.speedScale, this.audioStartMs, this.events);
  final int bpm, speedScale, audioStartMs;
  final List<SequenceEvent> events;
}

int? _laneChannel(int c) {
  if (c >= 11 && c <= 15) return c - 11;
  if (c >= 18 && c <= 19) return c - 13;
  if (c >= 21 && c <= 22) return c - 14;
  if (c >= 51 && c <= 55) return c - 41;
  if (c >= 58 && c <= 59) return c - 43;
  if (c >= 61 && c <= 62) return c - 44;
  return c == 16 ? 20 : null;
}

int _lead(int speed) => ((250 * 4294967296 ~/ speed) * 1000).toSigned(32) >> 16;

ChartSequence compileSequence(String text,
    [int scrollScale = 65536, int speedScale = 65536]) {
  var bpm = 120,
      audioStart = 0,
      measureTime = 240000 * 65536 ~/ 120,
      previousMeasure = -1;
  final events = <SequenceEvent>[], holds = <int, SequenceEvent>{};
  SequenceEvent add(int channel, int value, int time, [int holdIndex = 0]) {
    final speed =
        ((scrollScale * 120 * bpm ~/ 120) * speedScale / 65536).floor();
    final e = SequenceEvent(
        channel,
        value,
        holdIndex,
        speed,
        channel >= 10 && channel < 20 && speedScale > 65536 ? speedScale : 0,
        time,
        time - _lead(speed));
    events.add(e);
    return e;
  }

  for (final source in text.split(RegExp(r'[\r\n]+'))) {
    final line = source.trim();
    final header = RegExp(r'^#(BPM|MMF_START)\s+(-?\d+)').firstMatch(line);
    if (header != null) {
      if (header[1] == 'BPM') {
        bpm = int.parse(header[2]!);
        measureTime = 240000 * 65536 ~/ bpm;
      } else {
        audioStart = int.parse(header[2]!);
      }
      continue;
    }
    final match = RegExp(r'^#(\d{3})(\d{2}):\s*(\S+)').firstMatch(line);
    if (match == null) continue;
    final measure = int.parse(match[1]!);
    if (measure != previousMeasure) {
      add(21, 0, (measure * measureTime / 65536).floor());
      previousMeasure = measure;
    }
    final channel = _laneChannel(int.parse(match[2]!));
    if (channel == null) continue;
    final data = match[3]!;
    for (var offset = 0; offset < data.length; offset += 2) {
      final value = int.tryParse(
              data.substring(offset, (offset + 2).clamp(0, data.length))) ??
          0;
      if (value <= 0) continue;
      final time =
          ((measure * measureTime + offset * measureTime ~/ data.length) /
                  65536)
              .floor();
      final event = add(channel, value, time);
      if (channel < 10 || channel >= 20) continue;
      final start = holds[channel];
      if (start == null) {
        holds[channel] = event;
        continue;
      }
      final interval = ((measureTime ~/ 64) / 65536).floor();
      if (interval <= 0) throw const FormatException('Invalid hold interval');
      var index = 1;
      for (var ms = start.timeMs + interval;
          ms < event.timeMs;
          ms += interval, index++) {
        final tick = add(channel, start.value, ms, index);
        tick.speed = start.speed;
        tick.spawnMs = ms - _lead(tick.speed);
      }
      event.holdIndex = -1;
      holds.remove(channel);
    }
  }
  // Exchange sort is intentional: equal-time ordering affects hold judgement.
  for (var i = 0; i < events.length; i++) {
    for (var j = 0; j < i; j++) {
      if (events[i].timeMs < events[j].timeMs) {
        final temp = events[i];
        events[i] = events[j];
        events[j] = temp;
      }
    }
  }
  return ChartSequence(bpm, speedScale, audioStart, events);
}

class RhythmChart {
  RhythmChart(
      this.id,
      this.title,
      this.subtitle,
      this.artist,
      this.bpm,
      this.keyCount,
      this.level,
      this.rank,
      this.audioFilename,
      this.sequence,
      this.durationMs);
  final String id, title, subtitle, artist, audioFilename;
  final int bpm, keyCount, level, rank, durationMs;
  final ChartSequence sequence;
}

RhythmChart parseMus(String id, Uint8List bytes, Cp949 encoding,
    [int speedScale = 65536]) {
  final length = ByteData.sublistView(bytes).getUint32(0, Endian.little);
  final text = encoding.decode(Uint8List.sublistView(bytes, 4, 4 + length));
  String directive(String name) =>
      RegExp('^#$name\\s+(.+?)\\s*\$', multiLine: true, caseSensitive: false)
          .firstMatch(text)?[1]
          ?.replaceAll(RegExp(r'^"|"$'), '') ??
      '';
  int number(String name) => int.tryParse(directive(name)) ?? 0;
  final bpm = number('BPM'), keys = number('KEY');
  if (bpm <= 0 || ![3, 6, 9].contains(keys)) {
    throw FormatException('$id: unsupported MUS header');
  }
  final seq = compileSequence(text, 65536, speedScale);
  final end = seq.events.where((e) => e.channel == 20);
  return RhythmChart(
      id,
      directive('TITLE').isEmpty ? id : directive('TITLE'),
      directive('SUBTITLE'),
      directive('ARTIST'),
      bpm,
      keys,
      number('PLAYLEVEL'),
      number('RANK'),
      directive('MMF'),
      seq,
      end.isEmpty ? 0 : end.first.timeMs);
}
