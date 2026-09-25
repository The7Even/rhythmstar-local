import 'context.dart';
import 'scoring.dart';

class HelpScreen {
  HelpScreen(this.c) {
    a = c.archive('MusicSelect_Help');
    players = c.players(a, [9, 0, 4, 6, 8]);
  }
  final GameContext c;
  late final VrpArchive a;
  late final List<VrpPlayer> players;
  int page = 0;
  bool credits = false;
  void enter([bool value = false]) {
    credits = value;
    page = 0;
    players[1].select(value ? 1 : 0);
  }

  bool update(int delta, Set<String> keys) {
    if (credits) return keys.contains('back') || keys.contains('ok');
    players[4].update(delta);
    if (players[2].update(delta)) players[2].select(4);
    if (players[3].update(delta)) players[3].select(6);
    if (keys.contains('star')) {
      page = max(0, page - 1);
      players[2].select(5);
    } else if (keys.contains('hash')) {
      page = min(12, page + 1);
      players[3].select(7);
    } else if (keys.contains('back')) {
      return true;
    }
    return false;
  }

  void draw(Rgb565Framebuffer t) {
    for (final p in players) {
      p.draw(t);
    }
    for (final (v, x) in [(page + 1, 102), (credits ? 1 : 13, 141)]) {
      drawVrpFrame(t, a, 3, v % 10, x, 300);
      drawVrpFrame(t, a, 3, v ~/ 10, x - 12, 300);
    }
    if (!credits && page == 12) {
      for (var y = 112; y < 234; y++) {
        t.pixels.fillRange(y * t.width + 50, y * t.width + 200, 0x2584);
      }
    }
    c.font
        .draw(t, credits ? creditsText : helpText[page], 50, 100, 150, 170, 0);
  }
}

class NoticeScreen {
  NoticeScreen(this.c, [this.trophy, this.message]) {
    players = c.players(c.archive('MusicSelect_Window'), [1, 10, 9, 9, 9]);
    c.effect('EffectWindowOpen');
  }
  final GameContext c;
  final int? trophy;
  final String? message;
  late final List<VrpPlayer> players;
  void update(int delta) => players[2].update(delta);
  void draw(Rgb565Framebuffer t) {
    for (final p in players) {
      p.draw(t);
    }
    if (trophy == null) {
      c.font.draw(
          t,
          message ??
              '\rD행성\rU을 치유했습니다.\n\n음악선택시 \rE좌우방향키\rU를 이용해서 \rD행성\rU을 바꿀 수 있습니다.',
          40,
          114,
          164,
          86);
    } else {
      c.font.draw(t, '\rD트로피\rU를 얻었습니다!', 58, 122, 130, 28);
      drawVrpFrame(t, c.archive('MusicSelect1'), 152, trophy!, 73, 180);
      drawVrpFrame(t, c.archive('MusicSelect1'), 153, trophy!, 103, 180);
    }
  }
}

class PauseScreen {
  PauseScreen(this.c, this.save) {
    players = c.players(
        c.archive('MainGame'), [0, 15, 1, 2, 4, 18, 19, 21, 24, 6, 17, 25, 7]);
    _volume();
    _vibration();
  }
  final GameContext c;
  final SaveData save;
  late final List<VrpPlayer> players;
  List<VrpPlayer> dialog = [];
  int row = 0;
  void _volume() {
    players[11].frame = save.volume;
    players[10].select(save.volume != 0 ? 17 : 16);
  }

  void _vibration() {
    players[9].frame = save.vibrationEnabled ? 0 : 1;
    players[8].select(save.vibrationEnabled ? 24 : 23);
  }

  void _save() => c.save('savedata.dat', save.bytes);
  String? update(int delta, Set<String> keys) {
    bool has(String k) => keys.contains(k);
    if (dialog.isNotEmpty) return has('ok') ? 'playing' : null;
    players[1].frame = row;
    players[5].frame = save.sync + 3;
    players[2].frame = (save.delay + 600) ~/ 200;
    for (final i in [12, 8, 10]) {
      players[i].update(delta);
    }
    final digit = ['1', '2', '3', '4', '5', '6', '7', '8'].indexWhere(has);
    if (digit >= 0) {
      row = digit;
      players[12].select(7 + row);
    }
    if (digit == 0 || has('ok') && row == 0) {
      _save();
      return 'playing';
    }
    if (digit == 1 || has('ok') && row == 1) {
      _save();
      return 'songSelect';
    }
    if (digit == 6 || has('ok') && row == 6) return 'report';
    if (digit == 7 || has('ok') && row == 7) {
      _save();
      return 'restart';
    }
    final direction = has('left')
        ? -1
        : has('right')
            ? 1
            : 0;
    if (digit == 2 || direction != 0 && row == 2) {
      save.volume = digit == 2
          ? (save.volume + 1) % 6
          : (save.volume + direction).clamp(0, 5);
      c.volume(save.volume);
      _volume();
      if (save.volume != 0) c.effect('EffectWindowOpen');
    } else if (digit == 3 || direction != 0 && row == 3) {
      final old = save.vibrationEnabled;
      save.vibrationEnabled = digit == 3 ? !old : direction < 0;
      if (!old && save.vibrationEnabled) c.vibrate(100);
      _vibration();
    } else if (digit == 4 || direction != 0 && row == 4) {
      final next = save.delay + (digit == 4 ? 200 : direction * 200);
      save.delay =
          digit == 4 ? (next > 600 ? -600 : next) : next.clamp(-600, 600);
    } else if (digit == 5 || direction != 0 && row == 5) {
      final next = save.sync + (digit == 5 ? 1 : direction);
      save.sync = digit == 5 ? (next > 3 ? -3 : next) : next.clamp(-3, 3);
    } else if (has('up') || has('down')) {
      row = (row + (has('up') ? 7 : 1)) % 8;
      players[12].select(7 + row);
    } else if (has('back')) {
      _save();
      dialog = c.players(c.archive('MusicSelect_Window'), [1, 10, 9, 9, 9]);
    }
    return null;
  }

  void draw(Rgb565Framebuffer t) {
    for (final p in dialog.isEmpty ? players : dialog) {
      p.draw(t);
    }
    if (dialog.isNotEmpty) {
      c.font.draw(
          t,
          '\rY폰\rU에서는 \rD사운드\rU를 \rD일시정지\rU할 수 없어, \rE다시 시작\rU해야합니다.',
          40,
          114,
          164,
          86);
    }
  }
}

class GameOverScreen {
  GameOverScreen(VrpArchive a)
      : players = [VrpPlayer(a, 27, false), VrpPlayer(a, 29, false)];
  final List<VrpPlayer> players;
  bool finished = false, ready = false;
  void update(int delta) {
    if (finished) ready = true;
    players[0].update(delta);
    if (players[1].update(delta) && !finished) {
      players[1].select(28);
      finished = true;
    }
  }

  void draw(Rgb565Framebuffer t) {
    for (final p in players) {
      p.draw(t);
    }
  }
}

class ResultScreen {
  ResultScreen(this.c, this.chart, this.scoring, [this.trophy = -1]) {
    a = c.archive('MusicSelect1');
    picture = parseVrp(musPicture(c.read(chart.id)));
    base = c.players(a, [115, 116, 130]);
    rank = VrpPlayer(a, 118 + scoring.rank());
  }
  final GameContext c;
  final RhythmChart chart;
  final GameScoring scoring;
  final int trophy;
  late final VrpArchive a, picture;
  late final List<VrpPlayer> base;
  late final VrpPlayer rank;
  int stage = 0, elapsed = 0;
  bool rankPending = true;
  NoticeScreen? notice;
  bool update(int delta, Set<String> keys) {
    for (final p in base) {
      p.update(delta);
    }
    elapsed += delta;
    if (elapsed > 200) {
      elapsed = 0;
      stage = min(9, stage + 1);
      if (stage == 1) c.effect('EffectResult');
    }
    if (stage < 9) return false;
    if (rankPending) {
      if (rank.update(delta)) {
        rankPending = false;
        rank.select(117);
        rank.frame = scoring.rank();
      }
      return false;
    }
    notice?.update(delta);
    if (keys.isNotEmpty) {
      if (trophy < 0 || notice != null) return true;
      notice = NoticeScreen(c, trophy);
    }
    return false;
  }

  void draw(Rgb565Framebuffer t) {
    drawVrpFrame(t, a, 114, 0);
    for (final p in base) {
      p.draw(t);
    }
    final frame = a.frame(114, 0), m = a.frame(114, 0)?.marker(13);
    if (m != null) drawVrpFrame(t, picture, 0, 0, m.x, t.height - m.y);
    final v = [
      scoring.counts[4],
      scoring.counts[3],
      scoring.counts[2],
      scoring.counts[1],
      scoring.counts[0],
      scoring.counts.reduce((a, b) => a + b),
      scoring.score,
      scoring.maxCombo
    ];
    const animations = [128, 126, 125, 125, 125, 125, 129, 127];
    for (var s = 1; s <= stage; s++) {
      if (s == 9) {
        rank.draw(t);
        continue;
      }
      drawVrpFrame(t, a, 105 + s, 0);
      final p = frame?.marker(s + 4);
      if (p == null) continue;
      var number = v[s - 1], digit = 0;
      do {
        drawVrpFrame(t, a, animations[s - 1], number % 10, p.x - digit * 11,
            t.height - p.y);
        number = number ~/ 10;
        digit++;
      } while (number > 0 && digit < (s >= 7 ? 7 : 5));
    }
    notice?.draw(t);
  }
}

class DownloadScreen {
  DownloadScreen(this.c) {
    a = c.archive('MusicSelect2');
    base = c.players(a, [27, 24, 26]);
    selection = VrpPlayer(a, 25);
    c.stop();
  }
  final GameContext c;
  late final VrpArchive a;
  late List<VrpPlayer> base;
  late final VrpPlayer selection;
  int selected = 1;
  bool empty = false;
  NoticeScreen? notice;
  String? update(int delta, Set<String> keys) {
    bool has(String k) => keys.contains(k);
    if (notice != null) {
      notice!.update(delta);
      if (has('ok') || has('back')) {
        notice = null;
        if (empty) {
          empty = false;
          base = c.players(a, [27, 24, 26]);
        }
      }
      return null;
    }
    for (final p in base) {
      p.update(delta);
    }
    selection.frame = selected;
    final previous = selected;
    if (has('up')) {
      selected = 1;
    } else if (has('down')) {
      selected = 0;
    } else if (has('back')) {
      return 'mainMenu';
    } else if (has('ok')) {
      if (selected == 0) {
        empty = true;
        base = c.players(a, [9, 8, 2, 4, 6]);
      }
      notice = NoticeScreen(
          c, null, selected != 0 ? '오류가 발생했습니다.' : '다운로드 받은 파일이 없습니다.');
    }
    if (previous != selected) c.effect('EffectMenuChange');
    return null;
  }

  void draw(Rgb565Framebuffer t) {
    drawVrpFrame(t, a, empty ? 0 : 23, 0);
    for (final p in base) {
      p.draw(t);
    }
    if (!empty) selection.draw(t);
    notice?.draw(t);
  }
}
