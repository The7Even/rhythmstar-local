import 'context.dart';

class SelectionScreens {
  SelectionScreens(this.c, this.save) {
    a = c.archive('MusicSelect1');
    catalog = List.generate(
        3,
        (i) =>
            c.catalog.where((chart) => chart.keyCount == 3 + i * 3).toList());
    records = MusicRecords(
        catalog.expand((v) => v).toList(), c.read, c.stored['musicdata.dat']);
  }
  final GameContext c;
  final SaveData save;
  late final VrpArchive a;
  late final List<List<RhythmChart>> catalog;
  late final MusicRecords records;
  String phase = 'keySelect';
  int mode = 0, song = 0, scroll = 0, delta = 50;
  bool hint = false, stable = true, planetStable = true;
  List<VrpPlayer> base = [], dynamicPlayers = [], dialog = [];
  List<String> titles = [];
  VrpArchive? picture;
  final pictures = <String, VrpArchive>{};
  RhythmChart? get selected =>
      song >= 0 && song < catalog[mode].length ? catalog[mode][song] : null;
  void enter(String next) {
    final previous = phase;
    phase = next;
    if (next == 'keySelect') {
      mode = 0;
      hint = false;
      base = c.players(a, [13, 12, 4]);
      dynamicPlayers = c.players(a, [11, 5, 8]);
      c.stop();
    } else {
      if (previous == 'keySelect') song = 0;
      stable = planetStable = true;
      final planet = save.get(0x224),
          animation = save.get(0x224) < 0 ? 102 : 58 + save.get(0x224) * 4;
      base = c.players(a, [104]);
      dynamicPlayers = c.players(a, [animation, animation, 43, 49, 50, 52, 44]);
      if (List.generate(11, (i) => save.get(0x260 + i * 4))
          .any((v) => v != 0)) {
        dynamicPlayers.add(VrpPlayer(a, 53));
      }
      _refreshPlanet(planet);
      _refreshSong();
      _refreshTitles();
      _preview();
      hint = save.get(0x2c0) == 0;
      if (hint) {
        dialog = c.players(c.archive('MusicSelect_Window'), [1, 10, 9, 9, 9]);
        c.effect('EffectWindowOpen');
      }
    }
  }

  String? update(int ms, Set<String> keys) {
    delta = ms;
    bool has(String k) => keys.contains(k);
    final p = dynamicPlayers;
    if (phase == 'keySelect') {
      for (final b in base) {
        b.update(ms);
      }
      p[1].update(ms);
      p[2].update(ms);
      if (has('up') || has('down')) {
        mode = (mode + (has('up') ? 2 : 1)) % 3;
        p[0].frame = mode;
        p[1].select(5 + mode);
        p[2].select(8 + mode);
        c.effect('EffectKeyChange');
      } else if (has('ok')) {
        return 'songSelect';
      } else if (has('back')) {
        return 'mainMenu';
      }
      return null;
    }
    if (hint) {
      if (has('ok')) {
        hint = false;
        save.set(0x2c0, 1);
        _preview();
        _save();
      }
      return null;
    }
    for (final b in base) {
      b.update(ms);
    }
    if (p[2].update(ms)) p[2].select(43);
    if (!planetStable) {
      p[0].update(ms);
      if (p[1].update(ms)) {
        planetStable = true;
        _preview();
      }
    }
    if (!stable) {
      if (p[5].update(ms)) {
        p[5].select(52);
        stable = true;
        _refreshTitles();
        _preview();
      }
    } else {
      p[2].update(ms);
    }
    p[6].update(ms);
    if (p.length > 7) p[7].update(ms);
    if (!stable) return null;
    if (has('left') || has('right')) {
      _planet(has('left') ? -1 : 1);
    } else if (has('up') || has('down')) {
      final up = has('up');
      song += up ? -1 : 1;
      final count = catalog[mode].length;
      if (song < -1) song = count - 1;
      if (song > count) song = 0;
      _refreshSong();
      stable = false;
      p[2].select(42, false);
      p[5].select(up ? 51 : 54, false);
      c.effect('EffectMusicChange');
    } else if (has('back')) {
      return 'keySelect';
    } else if (has('ok')) {
      return selected != null ? 'gameplay' : 'download';
    } else if (has('hash')) {
      return 'planet';
    }
    return null;
  }

  void _refreshTitles() {
    scroll = 0;
    final songs = catalog[mode], length = catalog[mode].length + 1;
    titles = [-2, -1, 0, 1, 2].map((o) {
      final i = (song + o) % length;
      return i == songs.length ? '\rB최신곡\rU 다운받기' : songs[i].title;
    }).toList();
  }

  void _refreshSong() {
    final chart = selected;
    picture = chart == null
        ? null
        : pictures.putIfAbsent(
            chart.id, () => parseVrp(musPicture(c.read(chart.id))));
  }

  void _preview() {
    if (selected == null) {
      c.stop();
    } else {
      c.play(selected!.audioFilename);
    }
  }

  void _save() => c.save('savedata.dat', save.bytes);
  void _refreshPlanet(int planet) {
    const options = [
      (0, 1),
      (0, 2),
      (0, 3),
      (2, 0),
      (1, 0),
      (2, 1),
      (2, 2),
      (2, 3),
      (1, 1),
      (1, 2),
      (1, 3)
    ];
    final (mirror, speed) = planet < 0 ? (0, 0) : options[planet];
    dynamicPlayers[3].frame = mirror;
    dynamicPlayers[4].frame = speed;
  }

  void _planet(int direction) {
    final old = save.get(0x224);
    var next = old + direction;
    while (next >= 0 && next <= 10 && save.get(0x260 + next * 4) == 0) {
      next += direction;
    }
    if (next > 10 || (old < 0 && next < 0)) return;
    next = max(-1, next);
    save.set(0x224, next);
    _save();
    dynamicPlayers[0]
        .select(direction < 0 ? 57 + old * 4 : 56 + next * 4, false);
    dynamicPlayers[1].select(
        direction < 0
            ? (next < 0 ? 103 : 59 + next * 4)
            : (old < 0 ? 102 : 58 + old * 4),
        false);
    _refreshPlanet(next);
    planetStable = false;
    dynamicPlayers[2].select(42, false);
    c.effect('EffectStarChange');
  }

  void draw(Rgb565Framebuffer t) {
    drawVrpFrame(t, a, 41, 0);
    for (final p in [...base, ...dynamicPlayers]) {
      p.draw(t);
    }
    if (phase == 'keySelect') return;
    VrpMarker? common(int id) => a.frame(41, 0)?.marker(id);
    if (stable && selected != null) {
      drawVrpFrame(
          t, a, 55, selected!.level - (a.animation(55)?.firstFrame ?? 0));
      final pic = common(3);
      if (pic != null && picture != null) {
        drawVrpFrame(t, picture!, 0, 0, pic.x, t.height - pic.y);
      }
      final score = common(1);
      if (score != null) {
        for (var i = 0; i < 7; i++) {
          drawVrpFrame(
              t,
              a,
              48,
              (records.score(selected!.id) / pow(10, i)).truncate() % 10,
              score.x - i * 14,
              t.height - score.y);
        }
      }
    }
    final currency = common(2);
    if (currency != null) {
      for (var i = 0; i < 4; i++) {
        drawVrpFrame(t, a, 47, (save.get(0x228) / pow(10, i)).truncate() % 10,
            currency.x - i * 12, t.height - currency.y);
      }
    }
    final list = dynamicPlayers[5];
    for (final (id, row) in [(30, 2), (31, 1), (32, 3), (33, 0), (34, 4)]) {
      final m = list.current?.marker(id), title = titles[row];
      if (m == null || title.isEmpty) continue;
      final width = title
              .replaceAll(RegExp(r'\r.'), '')
              .codeUnits
              .fold(0, (int sum, int c) => sum + (c < 128 ? 6 : 12)),
          y = (t.height - m.y - 16).floor(),
          x = m.x.floor();
      if (row == 2 && width > 100) {
        scroll -= (delta * 15 * 65536 / 1000).floor();
        if (scroll < -width * 65536) scroll = ((m.x + 100) * 65536).toInt();
        c.font.draw(t, title, (m.x + scroll / 65536).floor(), y, width * 2, 16,
            0, (x: x, y: y, width: 100, height: 16));
      } else {
        c.font.draw(t, title, x, y, 100, 16, 0);
      }
    }
    if (hint) {
      for (final p in dialog) {
        p.draw(t);
      }
      c.font.draw(
          t,
          '\rD[행성치유란?]\rU\n게임중에 얻은 \rY음표\rU로 \rD행성\rU을 치유하면, 그 \rD행성\rU을 골라 플레이할 수 있습니다.\n\rD행성\rU을 선택하면 \rE다양한 옵션\rU이 적용됩니다.\n',
          40,
          114,
          164,
          86);
    }
  }
}
