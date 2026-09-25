import 'dart:math' as math;
import 'chart.dart';
import 'scoring.dart';

class PlayingNote {
  SequenceEvent? event;
  int state = 0,
      nextState = 0,
      counter = 0,
      elapsed = 0,
      y = 320 * 65536,
      bonus = 0;
  bool free = true;
}

class GameFeedback {
  GameFeedback(this.kind,
      {this.channel = 0,
      this.grade = 0,
      this.holdIndex = 0,
      this.combo = 0,
      this.previousCombo = 0,
      this.value = 0});
  final String kind;
  final int channel, grade, holdIndex, combo, previousCombo, value;
}

class GameplayEngine {
  GameplayEngine(this.sequence, this.mode, this.random,
      [int planetMultiplier = 65536,
      this.sync = 0,
      this.delay = 0,
      this.mirror = false,
      this.randomLanes = false])
      : scoring = GameScoring(mode, planetMultiplier);
  final ChartSequence sequence;
  final int mode, sync, delay;
  final int Function() random;
  final bool mirror, randomLanes;
  final GameScoring scoring;
  final notes = List.generate(256, (_) => PlayingNote());
  final feedback = <GameFeedback>[];
  String phase = 'ready';
  int? startedAt;
  int cursor = 0, heldMask = 0, holdStartedMask = 0, _poolCursor = 0;
  bool _prepared = false;
  void _request(PlayingNote note, int state) {
    note.nextState = state;
    note.counter = 0;
  }

  void _spawn(SequenceEvent event, int time) {
    if (event.channel < 10) {
      var channel = mirror ? 2 + mode * 3 - event.channel : event.channel;
      if (randomLanes) channel = (channel / 3).floor() * 3 + random() % 3;
      event = event.copy(channel: math.max(0, math.min(2 + mode * 3, channel)));
    }
    var slot = _poolCursor;
    while (slot < 256 && !notes[slot].free) {
      slot++;
    }
    if (slot == 256) {
      slot = 0;
      while (slot < _poolCursor && !notes[slot].free) {
        slot++;
      }
      if (slot == _poolCursor) return;
    }
    _poolCursor = slot;
    final note = notes[slot];
    note.event = event;
    note.elapsed = time - event.spawnMs;
    note.y = 320 * 65536;
    note.free = false;
    note.bonus = 0;
    if (event.channel < 10) {
      if (random() % 5000 <= 9) {
        note.bonus = 1;
      } else if (random() % 50000 <= 9) {
        note.bonus = 10;
      }
    }
    _request(note, 1);
  }

  void _hit(PlayingNote note, int grade) {
    final event = note.event!,
        hold = event.channel >= 10,
        previous = scoring.combo;
    scoring.hit(grade, !hold || event.holdIndex % 10 == 0);
    feedback.add(GameFeedback('hit',
        channel: event.channel,
        grade: grade,
        holdIndex: event.holdIndex,
        combo: scoring.combo,
        previousCombo: previous));
    _request(note, hold ? 2 : 5);
  }

  int _judge(int pressed) {
    if (pressed == 0 && heldMask == 0) return 0;
    var consumed = 0, lastGrade = 0;
    for (final note in notes) {
      final event = note.event;
      if (note.free ||
          note.state == 2 ||
          note.state == 5 ||
          event == null ||
          event.channel > 19) continue;
      final hold = event.channel >= 10,
          bit = 1 << (event.channel - (event.channel >= 10 ? 10 : 0));
      if ((consumed & bit) != 0 || ((hold ? heldMask : pressed) & bit) == 0) {
        continue;
      }
      if (!hold || event.holdIndex == 0) {
        lastGrade = judgeTiming(note.elapsed - (event.timeMs - event.spawnMs));
        if (lastGrade == 0) continue;
        if (hold) holdStartedMask |= bit;
      }
      if (lastGrade == 0) continue;
      _hit(note, lastGrade);
      consumed |= bit;
    }
    return lastGrade;
  }

  void update(int now, int delta, int pressedMask, int held,
      [void Function()? beforeSpawn]) {
    feedback.clear();
    if (!_prepared) {
      _prepared = true;
      return;
    }
    if (phase == 'ready') {
      phase = 'playing';
      startedAt = now;
    }
    final playing = phase == 'playing';
    if (playing) {
      beforeSpawn?.call();
      final time = now - startedAt! + delay;
      final correction = (time / 256).floor() * sync;
      while (cursor < sequence.events.length &&
          time > sequence.events[cursor].spawnMs + correction) {
        _spawn(sequence.events[cursor++].copy(correction: correction), time);
      }
      holdStartedMask &= held;
      heldMask = held;
      _judge(pressedMask);
    }
    for (final note in notes) {
      note.counter++;
      note.state = note.nextState;
      final event = note.event;
      if (note.state == 2 && note.counter == 1) {
        note.free = true;
      } else if (note.state == 5) {
        if (note.counter == 1 && note.bonus != 0 && event != null) {
          feedback.add(
              GameFeedback('bonus', channel: event.channel, value: note.bonus));
        }
        _request(note, 2);
      } else if (note.state == 1 && event != null) {
        if (!playing) _request(note, 2);
        if (note.counter != 1) note.elapsed += delta;
        note.y = 320 * 65536 - event.speed * note.elapsed ~/ 1000;
        final due = event.timeMs - event.spawnMs;
        if (event.channel >= 20) {
          if (note.elapsed > due) {
            _request(note, 2);
            if (event.channel == 20) {
              phase = 'complete';
              scoring.multiplier = 65536;
            }
          }
        } else if (note.elapsed > due + 200) {
          final hold = event.channel >= 10;
          final rescued = hold && _judge(pressedMask) != 0;
          if (!rescued) {
            scoring.miss(hold ? event.holdIndex : null);
            feedback.add(GameFeedback('miss'));
          }
          _request(note, 2);
          if (scoring.gauge <= 0) phase = 'failed';
        } else if (event.channel >= 10 && note.elapsed > due) {
          final bit = 1 << (event.channel - 10);
          if ((heldMask & holdStartedMask & bit) != 0) _hit(note, 4);
        }
      }
    }
  }
}
