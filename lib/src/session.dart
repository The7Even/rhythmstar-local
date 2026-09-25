import 'context.dart';
import 'dialogs.dart';
import 'gameplay_engine.dart';
import 'gameplay_view.dart';

class GameSession {
  GameSession(
      this.chart, this.mode, this.save, this.records, this.c, this.random) {
    final id = save.get(0x224);
    planet = id >= 0 && id < planets.length ? planets[id] : null;
    _start();
  }
  final RhythmChart chart;
  final int mode;
  final SaveData save;
  final MusicRecords records;
  final GameContext c;
  final int Function() random;
  late final Planet? planet;
  late GameplayEngine engine;
  late GameplayView view;
  ResultScreen? result;
  PauseScreen? pause;
  HelpScreen? help;
  GameOverScreen? gameOver;
  String? pending;
  int failedTicks = 0, trophy = -1, vibrationTime = 0;
  bool audioStarted = false, prepared = false;
  void _start() {
    final parsed = parseMus(
        chart.id, c.read(chart.id), c.encoding, planet?.speed ?? 65536);
    engine = GameplayEngine(
        parsed.sequence,
        mode,
        random,
        planet?.multiplier ?? 65536,
        save.sync,
        save.delay,
        planet?.mirror ?? false,
        planet?.random ?? false);
    view = GameplayView(engine, c, () {
      if (!save.vibrationEnabled) return;
      final ms = vibrationTime > 0 ? 0 : 100;
      vibrationTime = ms != 0 ? 120 : 0;
      c.vibrate(ms);
    });
    pause = null;
    result = null;
    gameOver = null;
    failedTicks = 0;
    audioStarted = false;
    prepared = false;
    c.stop();
  }

  void _save() => c.save('savedata.dat', save.bytes);
  String? update(int now, int delta, Set<String> keys, Set<String> held) {
    vibrationTime -= delta;
    if (pending == 'retry') {
      _start();
    } else if (pending == 'pause') {
      pause = PauseScreen(c, save);
      c.stop();
      view.advanceStopped(0, true);
      engine.phase = 'paused';
      engine.heldMask = 0;
    } else if (pending == 'result') {
      result = ResultScreen(c, chart, engine.scoring, trophy);
    }
    pending = null;
    if (result != null) {
      if (result!.update(delta, keys)) {
        c.save('musicdata.dat', records.bytes);
        _save();
        return 'songSelect';
      }
      return null;
    }
    if (pause != null) {
      view.advanceStopped(delta);
      engine.update(now, delta, 0, 0);
      view.afterUpdate();
      if (help != null) {
        if (help!.update(delta, keys)) help = null;
        return null;
      }
      final next = pause!.update(delta, keys);
      if (next == 'playing') {
        pending = 'retry';
      } else if (next == 'report') {
        help = HelpScreen(c);
      } else if (next == 'songSelect' || next == 'restart') {
        return next;
      }
      return null;
    }
    if (engine.phase == 'failed') {
      if (gameOver?.ready == true && keys.isNotEmpty) return 'songSelect';
      failedTicks++;
      view.advanceStopped(delta, failedTicks == 5);
      if (failedTicks == 1) {
        c.stop();
        save.increment(0x2cc);
        save.set(0x2d4, save.get(0x2cc) - save.get(0x2d0));
        _save();
      }
      if (failedTicks == 5) {
        gameOver = GameOverScreen(view.archive);
        c.effect('EffectGameOver');
      }
    }
    int mask(Set<String> input) {
      var value = 0;
      for (var i = 0; i < 3 + mode * 3; i++) {
        if (input.contains('${i + 1}')) value |= 1 << i;
      }
      return value;
    }

    final pressed = mask(keys), wasPrepared = prepared;
    prepared = true;
    engine.update(
        now, delta, pressed, mask(held), () => view.beforeSpawn(delta));
    view.afterUpdate(wasPrepared ? pressed : 0);
    gameOver?.update(delta);
    if (!audioStarted &&
        (save.delay.abs() != 600 ||
            engine.startedAt != null &&
                now > engine.startedAt! + engine.sequence.audioStartMs)) {
      audioStarted = true;
      c.play(chart.audioFilename);
    }
    for (final e in engine.feedback) {
      if (e.kind == 'hit' && e.grade == 1) {
        save.increment(0x230, e.previousCombo);
        save.set(0x304, save.get(0x230));
      }
      if (e.kind == 'bonus') {
        save.increment(0x228, e.value);
        save.increment(0x22c, e.value);
        save.increment(e.value == 10 ? 0x328 : 0x324);
        save.set(0x320, save.get(0x22c));
        save.set(0x228, min(9999, save.get(0x228)));
      }
    }
    if (engine.phase == 'complete') {
      trophy = records.complete(
          chart.id,
          engine.scoring,
          save,
          planet?.mirror ?? false,
          planet?.random ?? false,
          planet?.speed ?? 65536);
      pending = 'result';
    } else if (engine.phase == 'playing' && keys.contains('back')) {
      pending = 'pause';
    }
    return null;
  }

  void draw(Rgb565Framebuffer t) {
    if (result != null) {
      result!.draw(t);
    } else {
      view.draw(t);
      gameOver?.draw(t);
      if (help != null) {
        help!.draw(t);
      } else {
        pause?.draw(t);
      }
    }
  }
}
