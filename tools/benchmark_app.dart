// Run on the phone with flutter build apk --release --target-platform android-arm
// --target tools/benchmark_app.dart --dart-define=RHYTHMSTAR_RENDER_PROFILE=true
// Uses independent in-memory saves and never calls the native storage/audio API.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:rhythmstar_flutter/src/context.dart';
import 'package:rhythmstar_flutter/src/runtime.dart';
import 'package:rhythmstar_flutter/src/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Renderer benchmark'))));
  final paths =
      jsonDecode(await rootBundle.loadString('assets/resource_manifest.json'))
          as List;
  final resources = <String, Uint8List>{};
  for (final path in paths) {
    final bytes = await rootBundle.load('assets/$path');
    resources[path as String] =
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }
  final c = GameContext(resources, {}),
      game = DartGame(GameContext(resources, {}));
  var now = 0;
  void tick() {
    game.tick(now += 50);
    game.c.commands.clear();
  }

  void key(String value) {
    game.key(value, true);
    game.key(value, false);
    tick();
    tick();
  }

  key('ok');
  key('ok');
  key('ok');
  final records = MusicRecords(c.catalog, c.read, null);
  for (var round = 0; round < 3; round++) {
    void measure(String name, void Function() draw, Rgb565Framebuffer target) {
      for (var i = 0; i < 20; i++) {
        draw();
        target.toRgba();
      }
      Rgb565Framebuffer.resetProfile();
      final samples = <int>[];
      var rgba = 0;
      for (var i = 0; i < 100; i++) {
        final watch = Stopwatch()..start();
        draw();
        samples.add(watch.elapsedMicroseconds);
        watch.reset();
        target.toRgba();
        rgba += watch.elapsedMicroseconds;
      }
      samples.sort();
      print(
          'RENDER_BENCH $round $name avg=${samples.reduce((a, b) => a + b) ~/ 100}us p95=${samples[94]}us max=${samples.last}us rgba=${rgba ~/ 100}us profile=${Rgb565Framebuffer.profile}');
    }

    measure('menu', tick, game.screen);
    for (var mode = 0; mode < 3; mode++) {
      final save = SaveData(null);
      var rng = 1234;
      int random() {
        rng = (rng * 0x343fd + 0x269ec3) & 0xffffffff;
        return rng >> 16;
      }

      final chart =
          c.catalog.firstWhere((chart) => chart.keyCount == 3 + mode * 3);
      final session = GameSession(chart, mode, save, records, c, random),
          target = Rgb565Framebuffer(240, 320);
      for (var time = 0; time < 5000; time += 50) {
        session.engine.scoring.gauge = 1000;
        session.update(time, 50, {}, {});
        c.commands.clear();
      }
      // Freeze game state: compare exactly the same rendering workload in both builds.
      measure('play${3 + mode * 3}', () {
        target.clear();
        session.draw(target);
      }, target);
      session.pending = 'pause';
      session.update(5050, 50, {}, {});
      c.commands.clear();
      measure('pause${3 + mode * 3}', () {
        target.clear();
        session.draw(target);
      }, target);
    }
  }
  print('RENDER_BENCH DONE');
}
