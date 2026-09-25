import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmstar_flutter/src/context.dart';
import 'package:rhythmstar_flutter/src/gameplay_engine.dart';
import 'package:rhythmstar_flutter/src/scoring.dart';
import 'package:rhythmstar_flutter/src/session.dart';

int digest(Iterable<int> values) {
  var hash = 2166136261;
  for (final n in values) {
    hash = ((hash ^ n.toSigned(32)) * 16777619) & 0xffffffff;
  }
  return hash;
}

List<Object?> snapshot(GameplayEngine e) {
  final s = e.scoring;
  return [
    e.phase,
    e.startedAt,
    e.cursor,
    e.heldMask,
    e.holdStartedMask,
    s.score,
    s.gauge,
    s.gaugeDebt,
    s.combo,
    s.maxCombo,
    s.multiplier,
    s.missStreak,
    s.missPenalty,
    ...s.counts,
    s.rank(),
    digest(e.notes.expand((n) => [
          n.free ? 1 : 0,
          n.state,
          n.nextState,
          n.counter,
          n.elapsed,
          n.y,
          n.bonus,
          ...(n.event == null
              ? [-1]
              : [
                  n.event!.channel,
                  n.event!.holdIndex,
                  n.event!.timeMs,
                  n.event!.spawnMs
                ])
        ])),
    e.feedback
        .map((f) => [
              f.kind,
              f.channel,
              f.grade,
              f.holdIndex,
              f.combo,
              f.previousCombo,
              f.value
            ])
        .toList()
  ];
}

void main() {
  final paths =
      jsonDecode(File('assets/resource_manifest.json').readAsStringSync())
          as List;
  final resources = <String, Uint8List>{
    for (final p in paths) p as String: File('assets/$p').readAsBytesSync()
  };
  final fixture = jsonDecode(utf8.decode(gzip.decode(
      File('test/fixtures/dart-logic.json.gz').readAsBytesSync()))) as Map;
  test('all 32 MUS charts at four planet speeds match original compiler', () {
    final c = GameContext(resources, {});
    for (final expected in fixture['charts']) {
      final chart = parseMus(expected['path'], c.read(expected['path']),
          c.encoding, expected['speed']);
      expect([
        chart.title,
        chart.subtitle,
        chart.artist,
        chart.bpm,
        chart.keyCount,
        chart.level,
        chart.rank,
        chart.audioFilename,
        chart.durationMs
      ], expected['header']);
      expect(chart.sequence.bpm, expected['bpm']);
      expect(chart.sequence.audioStartMs, expected['audioStart']);
      expect(chart.sequence.events.map((e) => e.values).toList(),
          expected['events'],
          reason: '${chart.id} speed ${expected['speed']}');
    }
  });
  test(
      'judgement boundaries, combo multipliers, hold misses, debt and rank match original',
      () {
    expect(
        List.generate(803, (i) => judgeTiming(i - 401)), fixture['judgement']);
    for (final scenario in fixture['scoring']) {
      final s = GameScoring(scenario['mode'], 163840);
      for (final step in scenario['steps']) {
        if (step[0]) {
          s.miss(step[2]);
        } else {
          s.hit(step[1], step[3]);
        }
        expect([
          s.score,
          s.gauge,
          s.gaugeDebt,
          s.combo,
          s.maxCombo,
          s.multiplier,
          s.missStreak,
          s.missPenalty,
          ...s.counts,
          s.rank()
        ], step[4]);
      }
    }
  });
  for (final expected in fixture['sessions']) {
    test(
        'complete session ${expected['scenario']}: timing, hold, planet, result, binary saves and pixels',
        () {
      final c = GameContext(resources, {}),
          save = SaveData(base64Decode(expected['initial']));
      final records = MusicRecords(c.catalog, c.read, null),
          chart = c.catalog.firstWhere((chart) => chart.id == expected['path']);
      var rng = 1234;
      int random() {
        rng = (rng * 0x343fd + 0x269ec3) & 0xffffffff;
        return rng >> 16;
      }

      final s = GameSession(chart, expected['mode'], save, records, c, random),
          target = Rgb565Framebuffer(240, 320);
      for (final step in expected['steps']) {
        s.engine.scoring.gauge = 1000;
        final next = s.update(
            step['time'],
            step['delta'],
            (step['keys'] as List).cast<String>().toSet(),
            (step['held'] as List).cast<String>().toSet());
        final reason = 'scenario ${expected['scenario']} at ${step['time']}';
        expect(snapshot(s.engine), step['state'], reason: reason);
        expect(rng, step['randomState'], reason: reason);
        expect(next, step['next'], reason: reason);
        expect(c.commands, step['commands'], reason: reason);
        c.commands.clear();
        if (step['pixels'] != null) {
          target.clear();
          s.draw(target);
          expect(digest(target.pixels), step['pixels'],
              reason: 'pixels $reason');
        }
      }
      expect(base64Encode(save.bytes), expected['saved']);
      expect(base64Encode(records.bytes), expected['records']);
      expect(SaveData(save.bytes).bytes, save.bytes);
      expect(
          MusicRecords(c.catalog, c.read, records.bytes).bytes, records.bytes);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
  test('releasing a long note clears its held judgement state', () {
    final e = GameplayEngine(
        ChartSequence(120, 65536, 0, [
          SequenceEvent(10, 1, 0, 65536, 0, 300, 0),
          SequenceEvent(10, 1, 1, 65536, 0, 450, 150)
        ]),
        0,
        () => 100);
    for (var t = 0; t <= 350; t += 50) {
      e.update(t, 50, 1, 1);
    }
    expect(e.holdStartedMask & 1, 1);
    e.update(400, 50, 0, 0);
    expect(e.holdStartedMask, 0);
    expect(e.heldMask, 0);
  });
}
