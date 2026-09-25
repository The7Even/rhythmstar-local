import 'context.dart';
import 'dialogs.dart';

class PlanetScreen {
  PlanetScreen(this.c, this.save) {
    a = c.archive('MusicSelect1');
    help = c.archive('MusicSelect_Help');
    base = c.players(a, [149, 133, 148]);
    arrows = c.players(a, [143, 145]);
    highlight = VrpPlayer(a, 147);
  }
  final GameContext c;
  final SaveData save;
  late final VrpArchive a, help;
  late final List<VrpPlayer> base, arrows;
  late final VrpPlayer highlight;
  int selected = 0;
  NoticeScreen? notice;
  bool update(int delta, Set<String> keys) {
    bool has(String k) => keys.contains(k);
    if (notice != null) {
      notice!.update(delta);
      if (has('ok')) notice = null;
      return false;
    }
    for (final p in base) {
      p.update(delta);
    }
    for (var i = 0; i < arrows.length; i++) {
      if (arrows[i].update(delta)) arrows[i].select(143 + i * 2);
    }
    if (has('down')) {
      selected = min(10, selected + 1);
    } else if (has('up')) {
      selected = max(0, selected - 1);
    } else if (has('star')) {
      selected = max(0, selected - 4);
      arrows[0].select(144);
    } else if (has('hash')) {
      selected = min(10, selected + 4);
      arrows[1].select(146);
    } else if (has('ok')) {
      final currency = save.get(0x228),
          unlocked = save.get(0x260 + selected * 4);
      if (currency > 0 && unlocked == 0) {
        save.set(0x228, currency - 1);
        final o = 0x234 + selected * 4;
        save.increment(o);
        if (save.get(o) == planets[selected].cost) {
          save.set(0x260 + selected * 4, 1);
          notice = NoticeScreen(c);
        }
      }
    } else if (has('back')) {
      c.save('savedata.dat', save.bytes);
      return true;
    }
    highlight.frame = selected % 4;
    return false;
  }

  void draw(Rgb565Framebuffer t) {
    for (final p in [...base, ...arrows, highlight]) {
      p.draw(t);
    }
    VrpMarker marker(int id) => a.frame(149, 0)!.marker(id)!;
    final page = selected ~/ 4;
    for (var index = page * 4; index < min(11, page * 4 + 4); index++) {
      final row = index % 4, p = marker(103 + index % 4);
      drawVrpFrame(t, a, 134, index, p.x, t.height - p.y);
      if (save.get(0x260 + index * 4) == 0) drawVrpFrame(t, a, 137 + row, 0);
      final notes = marker(107 + row), progress = save.get(0x234 + index * 4);
      for (var n = 0; n < planets[index].cost; n++) {
        drawVrpFrame(t, a, 141, n < progress ? 0 : 1, notes.x + n * 10,
            t.height - notes.y);
      }
    }
    final unlocked = save.get(0x260 + selected * 4) != 0, p = planets[selected];
    drawVrpFrame(t, a, unlocked ? 135 : 136, unlocked ? selected : 0);
    final multiplier = [
          '1.1',
          '1.2',
          '1.5',
          '1.4',
          '1.6',
          '1.6',
          '1.75',
          '2.1',
          '1.9',
          '2.0',
          '2.5'
        ][selected],
        speed = p.speed < 65536
            ? '0.5배속'
            : p.speed > 131072
                ? '3배속'
                : p.speed > 65536
                    ? '2배속'
                    : '배속없음';
    final pos = marker(111);
    c.font.draw(
        t,
        '행성: \rF${p.name}\rU\n점수: \rF$multiplier배\rU\n옵션: \rF$speed\rU\n     \rF${p.mirror ? '미러모드' : p.random ? '랜덤모드' : ''}\rU',
        pos.x.toInt(),
        (t.height - pos.y).toInt(),
        120,
        52);
    for (final (id, v) in [(100, page + 1), (101, 3)]) {
      final m = marker(id);
      for (var i = 0; i < 2; i++) {
        drawVrpFrame(t, help, 3, (v / pow(10, i)).truncate() % 10, m.x - i * 12,
            t.height - m.y);
      }
    }
    final m = marker(102);
    for (var i = 0; i < 4; i++) {
      drawVrpFrame(t, a, 142, (save.get(0x228) / pow(10, i)).truncate() % 10,
          m.x - i * 11, t.height - m.y);
    }
    notice?.draw(t);
  }
}
