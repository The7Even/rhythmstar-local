import 'dart:convert';
import 'dart:typed_data';
import 'chart.dart';
import 'encoding.dart';
import 'font.dart';
import 'vrp.dart';
export 'dart:math' show min, max, pow;
export 'dart:typed_data';
export '../framebuffer.dart';
export 'chart.dart';
export 'font.dart';
export 'vrp.dart';
export 'storage.dart';
export 'data.dart';

class GameContext {
  GameContext(this.resources, this.stored)
      : encoding = Cp949(resources['cp949.bin']!);
  final Map<String, Uint8List> resources, stored;
  final Cp949 encoding;
  final commands = <List<Object>>[];
  final _archives = <String, VrpArchive>{};
  late final font = GameFont(
      read('res/Font/hfont_wg.fnt'), read('res/Font/efont_12_8.fnt'), encoding);
  late final catalog = (jsonDecode(utf8.decode(read('songs.json'))) as List)
      .map((p) => parseMus(p as String, read(p), encoding))
      .toList();
  Uint8List read(String path) =>
      resources[path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '')]!;
  VrpArchive archive(String name) =>
      _archives.putIfAbsent(name, () => parseVrp(read('res/Vrp/$name.vrp')));
  List<VrpPlayer> players(VrpArchive a, List<int> ids) =>
      ids.map((id) => VrpPlayer(a, id)).toList();
  void save(String name, Uint8List bytes) {
    stored[name] = Uint8List.fromList(bytes);
    commands.add(['save', name, base64Encode(bytes)]);
  }

  void play(String file, [bool repeat = false]) => commands.add([
        'play',
        file.replaceFirst(RegExp(r'\.mmf$', caseSensitive: false), ''),
        repeat
      ]);
  void effect(String name) => commands.add(['effect', name]);
  void stop() => commands.add(['stop']);
  void volume(int value) => commands.add([
        'volume',
        const [0.0, .15, .3, .5, .75, 1.0][value.clamp(0, 5)]
      ]);
  void vibrate(int ms) => commands.add(['vibrate', ms]);
}
