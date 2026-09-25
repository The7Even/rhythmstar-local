import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmstar_flutter/src/context.dart';
import 'package:rhythmstar_flutter/src/runtime.dart';

void main() {
  test('Dart game matches original state, audio, saves, and rendered pixels',
      () {
    final paths =
        jsonDecode(File('assets/resource_manifest.json').readAsStringSync())
            as List;
    final resources = <String, Uint8List>{
      for (final path in paths)
        path as String: File('assets/$path').readAsBytesSync()
    };
    final game = DartGame(GameContext(resources, {}));
    final actions = jsonDecode(utf8.decode(gzip.decode(
        File('test/fixtures/dart-runtime.json.gz').readAsBytesSync()))) as List;
    for (final action in actions) {
      if (action['op'] == 'key') {
        game.key(action['key'], true);
        game.key(action['key'], false);
      } else if (action['op'] == 'tick') {
        game.tick(action['now']);
        expect(game.phase, action['phase'],
            reason: 'phase at ${action['now']}');
        expect(game.c.commands, action['commands'],
            reason: 'commands at ${action['now']} (${game.phase})');
        game.c.commands.clear();
      } else {
        final expected = ByteData.sublistView(base64Decode(action['rgb565']));
        var differences = 0, first = -1;
        for (var i = 0; i < game.screen.pixels.length; i++) {
          if (game.screen.pixels[i] !=
              expected.getUint16(i * 2, Endian.little)) {
            differences++;
            if (first < 0) first = i;
          }
        }
        expect(differences, 0,
            reason:
                '${action['name']}: $differences pixels differ; first ($first) at ${first % 240},${first ~/ 240}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
