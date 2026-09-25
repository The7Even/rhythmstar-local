import 'dart:convert';
import 'context.dart';

const menuPhases = {
  'scores',
  'options',
  'trophies',
  'report',
  'rankingStart',
  'rankingConfirm',
  'rankingError'
};

class MenuScreens {
  MenuScreens(this.c, this.save) : a = c.archive('MusicSelect2');
  final GameContext c;
  final SaveData save;
  final VrpArchive a;
  String phase = 'scores';
  int page = 0,
      row = 0,
      scoreSelection = 1,
      trophySelection = 0,
      background = 87;
  List<VrpPlayer> base = [], dynamicPlayers = [], report = [], dialog = [];
  bool yes = true;
  void enter(String next) {
    final previous = phase;
    phase = next;
    if (next == 'options') {
      page = row = 0;
      background = 34;
      base = c.players(a, [55]);
      dynamicPlayers = c.players(a, [67, 44, 46, 54, 50, 51, 59, 56, 58, 35]);
      _refreshOptions();
    } else if (next == 'scores') {
      background = 87;
      scoreSelection = previous == 'trophies' ? 0 : 1;
      base = c.players(a, [91, 88, 90]);
      dynamicPlayers = c.players(a, [89]);
      dialog = [];
    } else if (next == 'trophies') {
      if (previous != 'report') {
        trophySelection = 0;
        background = 93;
        base = c.players(a, [100, 98]);
        dynamicPlayers = c.players(a, [99, 97]);
      }
      report = [];
    } else if (next == 'report') {
      page = 0;
      report = c.players(c.archive('MusicSelect_Help'), [9, 2, 4, 6, 8]);
    } else if (next == 'rankingStart') {
      save.bytes.setAll(0x110, utf8.encode('ANB(KTF)\x00'));
      save.bytes.setAll(0x10, utf8.encode('K\x00'));
    } else {
      yes = true;
      dialog = c.players(c.archive('MusicSelect_Window'),
          [1, next == 'rankingConfirm' ? 11 : 10, 9, 9, 9]);
      c.effect('EffectWindowOpen');
    }
  }

  String? update(int delta, Set<String> keys) {
    bool has(String k) => keys.contains(k);
    if (phase == 'rankingStart') return 'rankingConfirm';
    if (phase == 'rankingConfirm' || phase == 'rankingError') {
      dialog[2].update(delta);
      if (phase == 'rankingError') {
        if (has('ok') || has('back')) return 'scores';
      } else if (has('left')) {
        yes = true;
      } else if (has('right')) {
        yes = false;
      } else if (has('back') || (has('ok') && !yes)) {
        return 'scores';
      } else if (has('ok')) {
        return 'rankingError';
      }
      dialog[1].frame = yes ? 0 : 1;
      return null;
    }
    if (phase == 'report') {
      report[4].update(delta);
      if (report[2].update(delta)) report[2].select(4);
      if (report[3].update(delta)) report[3].select(6);
      if (has('star')) {
        page = max(0, page - 1);
        report[2].select(5);
      } else if (has('hash')) {
        page = min(3, page + 1);
        report[3].select(7);
      } else if (has('back')) {
        return 'trophies';
      }
      return null;
    }
    for (final p in base) {
      p.update(delta);
    }
    if (phase == 'scores') {
      dynamicPlayers[0].frame = scoreSelection;
      if (has('up') || has('down')) {
        final next = has('up') ? 1 : 0;
        if (next != scoreSelection) {
          scoreSelection = next;
          c.effect('EffectKeyChange');
        }
      } else if (has('ok')) {
        return scoreSelection != 0 ? 'rankingStart' : 'trophies';
      } else if (has('back')) {
        return 'mainMenu';
      }
    } else if (phase == 'trophies') {
      dynamicPlayers[1].frame = trophySelection;
      if (has('left')) {
        trophySelection = max(0, trophySelection - 1);
      } else if (has('right')) {
        trophySelection = min(11, trophySelection + 1);
      } else if (has('up')) {
        if (trophySelection >= 3) trophySelection -= 3;
      } else if (has('down')) {
        if (trophySelection < 9) trophySelection += 3;
      } else if (has('back')) {
        return 'scores';
      } else if (has('star')) {
        return 'report';
      }
    } else {
      final p = dynamicPlayers;
      if (p[1].update(delta)) p[1].select(44);
      if (p[2].update(delta)) p[2].select(46);
      for (final i in row != 0 ? [7, 9] : [5, 6, 9]) {
        p[i].update(delta);
      }
      if (has('up') || has('down')) {
        if (page == 0) {
          row = has('up') ? 0 : 1;
          p[3].select(54 - row);
          p[4].select(50 - row);
        }
      } else if (has('left') || has('right')) {
        final direction = has('left') ? -1 : 1;
        if (page == 0 && row == 0) {
          save.volume = (save.volume + direction).clamp(0, 5);
          c.volume(save.volume);
          c.effect('EffectWindowOpen');
        } else if (page == 0) {
          final old = save.vibrationEnabled;
          save.vibrationEnabled = direction < 0;
          if (!old && save.vibrationEnabled) c.vibrate(100);
        } else if (page == 1) {
          save.delay = (save.delay + direction * 200).clamp(-600, 600);
        } else {
          save.sync = (save.sync + direction).clamp(-3, 3);
        }
        _refreshOptions();
      } else if (has('star') || has('hash')) {
        page = (page + (has('star') ? -1 : 1)).clamp(0, 2);
        p[has('star') ? 1 : 2].select(has('star') ? 45 : 47);
        _refreshOptions();
      } else if (has('back') || has('ok')) {
        c.save('savedata.dat', save.bytes);
        return 'mainMenu';
      }
    }
    return null;
  }

  void _refreshOptions() {
    final p = dynamicPlayers;
    if (page == 0) {
      p[0].select(67);
      p[3].select(54 - row);
      p[4].select(50 - row);
      p[5].select(save.volume != 0 ? 52 : 51);
      p[6].select(save.volume != 0 ? 58 + save.volume : 43);
      p[7].select(save.vibrationEnabled ? 57 : 56);
      p[8].select(58);
      p[8].frame = save.vibrationEnabled ? 0 : 1;
      p[9].select(43);
    } else {
      p[0].select(page == 1 ? 66 : 65);
      p[3].select(54);
      p[4].select(48);
      for (final i in [5, 6, 7, 8]) {
        p[i].select(43);
      }
      p[9].select(38 + (page == 1 ? save.delay ~/ 200 : save.sync));
    }
  }

  void draw(Rgb565Framebuffer t) {
    drawVrpFrame(t, a, background, 0);
    for (final p in [...base, ...dynamicPlayers]) {
      p.draw(t);
    }
    if (phase == 'trophies') {
      for (var index = 0; index < 12; index++) {
        final count = save.get(0x28c + index * 4),
            x = 63 + index % 3 * 57,
            origin = 118 + index ~/ 3 * 45;
        drawVrpFrame(t, a, 94, count != 0 ? index : 12, x, origin);
        if (count != 0) {
          var position = x + 16;
          for (final digit in '$count'.split('').reversed) {
            drawVrpFrame(t, a, 96, int.parse(digit), position, origin);
            position -= 6;
          }
          drawVrpFrame(t, a, 96, 10, position, origin);
        }
      }
      drawVrpFrame(t, a, 95, trophySelection, 50, 291);
      if (save.get(0x28c + trophySelection * 4) != 0) {
        c.font.draw(
            t,
            const [
              '5시간이상 플레이',
              '콤보 누적 5000개',
              '음표 누적 500개',
              '5곡이상 A등급',
              '5곡이상 S등급',
              '기본곡 All S등급',
              '5곡이상 미러모드 A등급',
              '5곡이상 랜덤모드 A등급',
              '5곡이상 0.5배속 A등급',
              '5곡이상 3배속 A등급',
              '모든 행성 치유',
              '다운로드5곡 이상'
            ][trophySelection],
            36,
            295,
            170,
            16,
            0);
      }
    } else if (phase == 'options' && page > 0) {
      c.font.draw(
          t,
          page == 1
              ? '사운드가 노트보다 빠르거나 느릴 경우, 아래의 값을 조절해 주십시오.'
              : '사운드가 약간씩 느려지는 경우, 아래의 값을 조절해 주십시오.',
          36,
          132,
          170,
          40,
          0);
    } else if (phase == 'report') {
      for (final p in report) {
        p.draw(t);
      }
      final help = c.archive('MusicSelect_Help');
      for (final (n, x) in [(page + 1, 102), (4, 141)]) {
        drawVrpFrame(t, help, 3, n, x, 300);
        drawVrpFrame(t, help, 3, 0, x - 12, 300);
      }
      c.font.draw(t, _reportText(), 50, 100, 150, 170, 0);
    } else if (dialog.isNotEmpty) {
      for (final p in dialog) {
        p.draw(t);
      }
      c.font.draw(
          t,
          phase == 'rankingConfirm'
              ? '네트워크에 접속시, \rY데이터통화료\rU가 부과됩니다. 접속하시겠습니까?'
              : '오류가 발생했습니다.',
          40,
          114,
          164,
          86);
    }
  }

  String _reportText() {
    String lines(String title, String first, List<String> rest) =>
        '[$title]\n\rV$first\n\n\rg${rest.join('\n')}';
    if (page == 0) {
      return lines('기본정보', '총플레이시간: \rg${save.playTime ~/ 60000}분', [
        '총플레이 수: ${save.get(0x2cc)}회',
        '총클리어 수: ${save.get(0x2d0)}회',
        '게임오버 수: ${save.get(0x2d4)}회',
        '',
        '다운로드 곡수: ${save.get(0x2d8)}곡',
        '캐시구매 곡수: ${save.get(0x2e0)}곡',
        '음표구매 곡수: ${save.get(0x2dc)}곡'
      ]);
    }
    if (page == 1) {
      return lines(
          'Grade 정보',
          '총 스코어: \rg${save.get(0x2e4)}점',
          List.generate(
              7, (i) => '${'SABCDEF'[i]}등급 획득: ${save.get(0x2e8 + i * 4)}회'));
    }
    if (page == 2) {
      return lines('Combo 정보', '총 누적콤보: \rg${save.get(0x304)}', [
        '총플레이 수: ${save.get(0x2cc)}회',
        ...List.generate(
            6,
            (i) => '${[
                  '100%',
                  '90%',
                  '80%',
                  '70%',
                  '60%',
                  '60%미만'
                ][i]} 콤보: ${save.get(0x308 + i * 4)}회')
      ]);
    }
    return lines('음표정보', '총 얻은음표: \rg${save.get(0x320)}개', [
      '음표 획득수: ${save.get(0x324)}회',
      '왕음표 획득수: ${save.get(0x328)}회',
      '',
      '총 사용음표: ${save.get(0x32c)}개',
      '총 보유음표: ${save.get(0x330)}개'
    ]);
  }
}
