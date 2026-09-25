import 'context.dart';
import 'gameplay_engine.dart';

const programs = [
  (
    hud: [37, 55, 56, 31, 65, 65, 54, 87],
    key: 61,
    bar: 57,
    label: 75,
    hold: 71,
    emptyLabel: 74,
    x: 63,
    width: 39
  ),
  (
    hud: [100, 118, 119, 94, 65, 134, 117, 165],
    key: 127,
    bar: 120,
    label: 150,
    hold: 143,
    emptyLabel: 149,
    x: 49,
    width: 24
  ),
  (
    hud: [178, 196, 197, 172, 65, 218, 195, 258],
    key: 208,
    bar: 198,
    label: 240,
    hold: 230,
    emptyLabel: 239,
    x: 49,
    width: 16
  ),
];

class Cue {
  Cue(this.player);
  final VrpPlayer player;
  bool active = false;
}

class Effect extends Cue {
  Effect(super.player);
  bool ending = false, free = true, settle = false;
  int x = 0, y = 0, holdLane = -1;
  int? remaining;
}

class GameplayView {
  GameplayView(this.engine, GameContext c, this.vibrate) {
    archive = c.archive('MainGame');
    final p = programs[engine.mode];
    hud = c.players(archive, p.hud);
    final speed = engine.sequence.speedScale;
    hud[4].select(speed < 65536
        ? 84
        : speed > 131072
            ? 86
            : speed > 65536
                ? 85
                : 65);
    if (engine.mirror || engine.randomLanes) {
      hud[5].select(engine.mirror ? 82 : 83);
    }
    background =
        c.players(archive, [4, 3, 2].map((o) => p.hud[3] + o).toList());
    for (final b in background) {
      b.update(50);
    }
    keys = List.generate(3 + engine.mode * 3, (_) => VrpPlayer(archive, p.key));
    notePlayers = List.generate(256,
        (_) => (body: VrpPlayer(archive, 58), label: VrpPlayer(archive, 75)));
    cues = List.generate(
        keys.length,
        (lane) =>
            Cue(VrpPlayer(archive, [66, 135, 219][engine.mode] + lane, false)));
    effects = List.generate(128, (_) => Effect(VrpPlayer(archive, 90, false)));
    combo = VrpPlayer(archive, [46, 109, 187][engine.mode], false);
    tier = VrpPlayer(archive, [38, 101, 179][engine.mode]);
  }
  final GameplayEngine engine;
  final void Function() vibrate;
  late final VrpArchive archive;
  late final List<VrpPlayer> hud, keys, background;
  late final List<({VrpPlayer body, VrpPlayer label})> notePlayers;
  late final List<Cue> cues;
  late final List<Effect> effects;
  late final VrpPlayer combo, tier;
  bool tierVisible = false,
      tierIntro = false,
      comboVisible = false,
      comboEnding = false;
  int lastMultiplier = 1,
      vibrationDelay = 0,
      comboCount = 0,
      effectCursor = 0,
      backgroundDelay = 0,
      delta = 50;
  void beforeSpawn(int ms) {
    delta = ms;
    for (final p in background) {
      p.update(ms);
    }
    backgroundDelay -= ms;
    if (backgroundDelay < 0 && hud[0].update(ms)) backgroundDelay = 5000;
    hud[1].update(ms);
    hud[2].update(ms);
    if (hud[3].update(ms)) {
      hud[3].select(programs[engine.mode].hud[3] + (engine.random() & 1));
    }
    final gauge = (engine.scoring.gauge + engine.random() % 5 - 2).clamp(0, 99);
    hud[6].frame = 99 - gauge;
    if (hud[7].update(ms)) hud[7].select(programs[engine.mode].hud[7]);
    for (final p in keys) {
      if (p.update(ms)) p.select(programs[engine.mode].key);
    }
  }

  void advanceStopped(int ms, [bool clearCombo = false]) {
    delta = ms;
    for (final p in background) {
      p.update(ms);
    }
    for (final e in effects) {
      if (e.holdLane >= 0) e.ending = true;
    }
    if (clearCombo) {
      comboVisible = false;
      tierVisible = false;
    }
  }

  void _effect(int animation,
      [int x = 0, int y = 0, int holdLane = -1, int? remaining]) {
    var index = effectCursor;
    while (index < 128 && !effects[index].free) {
      index++;
    }
    if (index == 128) {
      index = 0;
      while (index < effectCursor && !effects[index].free) {
        index++;
      }
      if (index == effectCursor) return;
    }
    effectCursor = index;
    final e = effects[index];
    e.player.select(animation, false);
    e.active = true;
    e.ending = false;
    e.free = false;
    e.x = x;
    e.y = y;
    e.remaining = remaining;
    e.holdLane = holdLane;
    e.settle = holdLane >= 0;
  }

  void afterUpdate([int pressed = 0]) {
    final p = programs[engine.mode];
    if (comboEnding) {
      comboVisible = false;
      comboEnding = false;
    }
    if (pressed != 0) hud[7].select(p.hud[7] + 1);
    for (var lane = 0; lane < cues.length; lane++) {
      if (((pressed | engine.heldMask) & (1 << lane)) != 0) {
        keys[lane].select(p.key + 1 + lane);
        cues[lane].player.select([66, 135, 219][engine.mode] + lane, false);
        cues[lane].active = true;
      }
    }
    for (var i = 0; i < engine.notes.length; i++) {
      final n = engine.notes[i], e = engine.notes[i].event;
      if (e == null) continue;
      final players = notePlayers[i];
      if (n.state == 1 && n.counter == 1) {
        final lane = e.channel % 10;
        players.body.select(e.channel >= 20
            ? p.bar
            : e.channel >= 10
                ? p.hold + lane
                : p.bar + 1 + lane);
        players.label.select(
            e.channel >= 20 || (e.channel >= 10 && e.holdIndex != 0)
                ? p.emptyLabel
                : p.label + lane);
      }
      if (n.state == 1 && n.counter == 1 && n.bonus != 0) {
        final base = [80, 158, 251][engine.mode];
        players.body.select(base + (n.bonus == 1 ? 1 : 0));
        players.label.select(base - (n.bonus == 1 ? 1 : 2));
      }
      players.body.update(delta);
    }
    for (final e in engine.feedback) {
      if (e.kind == 'miss') {
        tierVisible = false;
        lastMultiplier = 1;
        continue;
      }
      if (e.kind == 'bonus') {
        _effect([53, 116, 194][engine.mode], 0, 0, -1, 400);
        continue;
      }
      if (e.kind != 'hit') continue;
      if (e.channel < 10) {
        _effect([90, 168, 261][engine.mode], p.x + p.width * e.channel, 70);
      } else if (!effects
          .any((f) => f.active && f.holdLane == e.channel - 10)) {
        _effect([92, 170, 263][engine.mode], p.x + p.width * (e.channel - 10),
            70, e.channel - 10);
      }
      if (e.channel < 10 || e.holdIndex == 0) {
        _effect([48, 111, 189][engine.mode] + e.grade);
        vibrationDelay = 700;
        vibrate();
      }
      vibrationDelay -= delta;
      if (vibrationDelay < 0 && e.channel >= 10 && e.holdIndex > 0) {
        _effect([52, 115, 193][engine.mode]);
        vibrationDelay = 700;
        vibrate();
      }
      if (e.combo > 1) {
        combo.select([46, 109, 187][engine.mode], false);
        comboCount = e.combo;
        comboVisible = true;
        final m = e.combo <= 19
            ? 1
            : e.combo <= 39
                ? 2
                : e.combo <= 69
                    ? 3
                    : e.combo <= 99
                        ? 4
                        : 5;
        if (m != lastMultiplier) {
          lastMultiplier = m;
          tierVisible = m > 1;
          tierIntro = true;
          tier.select([38, 101, 179][engine.mode] + m * 2 - 3);
        }
      }
    }
    for (final e in effects) {
      if (e.active &&
          e.holdLane >= 0 &&
          (engine.heldMask & (1 << e.holdLane)) == 0) e.ending = true;
      if (e.ending) {
        e.active = false;
        e.free = true;
        e.ending = false;
      } else if (e.active && e.remaining != null) {
        e.remaining = e.remaining! - delta;
        if (e.remaining! < 0) e.ending = true;
      } else if (e.active && e.player.update(delta)) {
        if (e.holdLane < 0) {
          e.ending = true;
        } else if (e.settle) {
          e.player.select(e.player.animation - 1);
          e.settle = false;
        }
      }
    }
    if (comboVisible && combo.update(delta)) comboEnding = true;
    if (tierVisible && tier.update(delta) && tierIntro) {
      tier.select(tier.animation - 1);
      tierIntro = false;
    }
  }

  void draw(Rgb565Framebuffer t) {
    final p = programs[engine.mode];
    for (final cue in cues) {
      if (!cue.active) continue;
      final complete = cue.player.update(delta);
      cue.player.draw(t);
      if (complete) cue.active = false;
    }
    for (final b in background) {
      b.draw(t);
    }
    for (var i = engine.notes.length - 1; i >= 0; i--) {
      final n = engine.notes[i], e = engine.notes[i].event;
      if (n.free || e == null || e.channel == 20) continue;
      final x = p.x + (e.channel >= 20 ? 0 : e.channel % 10) * p.width,
          origin = t.height - n.y / 65536;
      notePlayers[i].label.draw(t, x, origin);
      final scale = e.holdSpeed / 65536;
      notePlayers[i].body.draw(
          t,
          x,
          origin + (scale > 0 ? 8 * scale - 8 / 65536 : 0),
          scale != 0 ? scale : 1);
    }
    for (final i in [1, 2, 3, 6, 7]) {
      hud[i].draw(t);
    }
    for (final k in keys) {
      k.draw(t);
    }
    for (final m in hud[1].current?.markers ?? <VrpMarker>[]) {
      if (m.id == 20) {
        var score = engine.scoring.score;
        for (var i = 0; i < 7; i++) {
          drawVrpFrame(
              t, archive, 265, score % 10, m.x - i * 14, t.height - m.y);
          score = score ~/ 10;
        }
      } else if (m.id == 21 || m.id == 22) {
        hud[m.id == 21 ? 4 : 5].draw(t, m.x, t.height - m.y);
      }
    }
    if (tierVisible) tier.draw(t);
    if (comboVisible) {
      combo.draw(t);
      final m = archive.frame(combo.animation, 0)?.marker(10);
      if (m != null) {
        var digits = '$comboCount';
        if (digits.length > 4) digits = digits.substring(digits.length - 4);
        for (var i = 0; i < digits.length; i++) {
          drawVrpFrame(t, archive, combo.animation + 1, int.parse(digits[i]),
              m.x + (i - digits.length / 2) * 28, t.height - m.y);
        }
      }
    }
    for (final e in effects.reversed) {
      if (e.active) e.player.draw(t, e.x, t.height - e.y);
    }
  }
}
