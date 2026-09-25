import '../native_math.dart';
import 'context.dart';
import 'dialogs.dart';
import 'menus.dart';
import 'planet.dart';
import 'selection.dart';
import 'session.dart';

class MenuStar {
  MenuStar(this.startX, this.startY);
  int startX, startY, elapsed = 0, x = 0, y = 0;
}

/// Entire game runtime. No JavaScript runtime, bridge, or display list.
class DartGame {
  DartGame(this.c, [int now = 0]) {
    start(now);
  }
  final GameContext c;
  final screen = Rgb565Framebuffer(240, 320),
      keys = <String>{},
      held = <String>{};
  late SaveData save;
  String phase = 'anbGames';
  String? pending;
  int frame = 0, lastTick = 0, menuSelection = 0, randomState = 0x4d2;
  bool running = true;
  VrpPlayer? logo, selectedPlayer;
  List<VrpPlayer> players = [];
  List<MenuStar> stars = [];
  SelectionScreens? selection;
  MenuScreens? menus;
  GameSession? session;
  HelpScreen? help;
  PlanetScreen? planet;
  DownloadScreen? download;
  static const menuDestinations = [
    'keySelect',
    'scores',
    'download',
    'options',
    'help',
    'credits',
    'restart'
  ];
  static const rightAnimations = [36, 20, 23, 25, 27, 29, 31],
      leftAnimations = [21, 22, 24, 26, 28, 30, 32];
  void start(int now) {
    save = SaveData(c.stored['savedata.dat']);
    c.volume(save.volume);
    logo = VrpPlayer(c.archive('anblogo'), 1, false);
    lastTick = now;
    phase = 'anbGames';
    frame = 0;
    menuSelection = 0;
    running = true;
  }

  void key(String key, bool down) {
    if (!running) return;
    if (down) {
      keys.add(key);
      held.add(key);
    } else {
      held.remove(key);
    }
  }

  void releaseKeys() {
    keys.clear();
    held.clear();
  }

  void stop() {
    running = false;
    c.stop();
  }

  int nextRandom() {
    randomState = (randomState * 0x343fd + 0x269ec3) & 0xffffffff;
    return randomState >> 16;
  }

  MenuStar _star([int index = 0]) {
    final edge = nextRandom() % 17, offset = index * 32;
    return MenuStar(
        (edge < 10 ? -30 + offset : (edge - 10) * 32 + offset) * 65536,
        (edge < 10 ? edge * 32 + offset : -30 + offset) * 65536);
  }

  void _updateStar(MenuStar star, int delta) {
    star.elapsed += delta * 65536 ~/ 1000;
    const angle = 80 * 205887 ~/ 180;
    star.x = star.startX +
        (star.elapsed * (nativeCosine(angle) * 50) / 65536).floor();
    star.y =
        star.startY + (star.elapsed * (nativeSine(angle) * 50) / 65536).floor();
    if (star.x > 270 * 65536 || star.y > 350 * 65536) {
      final r = _star();
      star.startX = r.startX;
      star.startY = r.startY;
      star.elapsed = 0;
    }
  }

  void tick(int now) {
    if (!running) return;
    if (pending == 'restart') {
      stop();
      pending = null;
      menus = null;
      selection = null;
      session = null;
      help = null;
      planet = null;
      download = null;
      players = [];
      selectedPlayer = null;
      stars = [];
      releaseKeys();
      randomState = 0x4d2;
      start(now);
      return;
    }
    final delta = max(0, now - lastTick);
    lastTick = now;
    save.playTime += delta;
    final next = pending;
    pending = null;
    if (next == 'title') {
      players =
          c.players(c.archive('MusicSelect_Title'), [2, 3, 4, 5, 6, 7, 8]);
      phase = 'title';
      c.play('MarchChop', true);
    } else if (next == 'mainMenu') {
      final a = c.archive('MusicSelect1');
      players = c.players(a, [17, 39, 16]);
      final anim = phase == 'title' ? 19 : rightAnimations[menuSelection];
      selectedPlayer = VrpPlayer(a, anim, false);
      if (phase != 'title') {
        selectedPlayer!.position = a.animation(anim)?.durationTicks ?? 0;
      }
      stars = List.generate(5, _star);
      phase = 'mainMenu';
      c.stop();
      c.play('SpyOut', true);
    } else if (next == 'keySelect' || next == 'songSelect') {
      selection ??= SelectionScreens(c, save);
      selection!.enter(next!);
      phase = next;
    } else if (next == 'download') {
      download = DownloadScreen(c);
      phase = next!;
    } else if (next == 'planet') {
      planet = PlanetScreen(c, save);
      phase = next!;
    } else if (next == 'gameplay') {
      session = GameSession(selection!.selected!, selection!.mode, save,
          selection!.records, c, nextRandom);
      phase = next!;
    } else if (next == 'help' || next == 'credits') {
      help ??= HelpScreen(c);
      help!.enter(next == 'credits');
      phase = next!;
    } else if (next != null) {
      menus ??= MenuScreens(c, save);
      menus!.enter(next);
      phase = next;
    }
    if (phase == 'anbGames' || phase == 'carrier3330') {
      final complete = logo!.update(delta);
      if (complete || keys.isNotEmpty) {
        if (phase == 'anbGames') {
          logo!.select(0, false);
          phase = 'carrier3330';
        } else {
          logo = null;
          pending = 'title';
          phase = 'titleTransition';
        }
      }
    } else if (phase == 'help' || phase == 'credits') {
      if (help!.update(delta, keys)) pending = 'mainMenu';
    } else if (phase == 'download') {
      pending = download!.update(delta, keys);
    } else if (phase == 'planet') {
      if (planet!.update(delta, keys)) pending = 'songSelect';
    } else if (phase == 'gameplay') {
      pending = session!.update(now, delta, keys, held);
    } else if (phase == 'keySelect' || phase == 'songSelect') {
      pending = selection!.update(delta, keys);
    } else if (menuPhases.contains(phase)) {
      pending = menus!.update(delta, keys);
    } else {
      for (final p in players) {
        p.update(delta);
      }
      if (phase == 'title' && keys.isNotEmpty) {
        pending = 'mainMenu';
      } else if (phase == 'mainMenu') {
        selectedPlayer?.update(delta);
        if (keys.contains('left') || keys.contains('right')) {
          final old = menuSelection, left = keys.contains('left');
          menuSelection = (old + (left ? -1 : 1)) % 7;
          selectedPlayer!.select(
              left ? leftAnimations[old] : rightAnimations[menuSelection],
              false);
          c.effect('EffectMenuChange');
        } else if (keys.contains('ok')) {
          pending = menuDestinations[menuSelection];
          if (['keySelect', 'scores', 'options'].contains(pending)) c.stop();
        }
        for (final s in stars) {
          _updateStar(s, delta);
        }
      }
    }
    keys.clear();
    screen.clear();
    if (phase == 'anbGames' || phase == 'carrier3330') {
      logo?.draw(screen, 120, 160);
    } else if (phase == 'titleTransition') {
    } else if (phase == 'title') {
      drawVrpFrame(screen, c.archive('MusicSelect_Title'), 0, 0);
      for (final p in players) {
        p.draw(screen);
      }
      if (pending != 'mainMenu') {
        c.font.english.draw(screen, 'Ver 1.0.3', 2, 28, 0xffff, 0);
      }
    } else if (phase == 'help' || phase == 'credits') {
      help!.draw(screen);
    } else if (phase == 'download') {
      download!.draw(screen);
    } else if (phase == 'planet') {
      planet!.draw(screen);
    } else if (phase == 'gameplay') {
      session!.draw(screen);
    } else if (phase == 'keySelect' || phase == 'songSelect') {
      selection!.draw(screen);
    } else if (menuPhases.contains(phase)) {
      menus!.draw(screen);
    } else {
      final a = c.archive('MusicSelect1');
      drawVrpFrame(screen, a, 15, menuSelection);
      for (final s in stars) {
        drawVrpFrame(
            screen, a, 38, 0, s.x / 65536, screen.height - s.y / 65536);
      }
      for (final p in players) {
        p.draw(screen);
      }
      selectedPlayer?.draw(screen);
    }
    frame++;
  }
}
