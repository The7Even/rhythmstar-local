import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'src/context.dart';
import 'src/runtime.dart';

const nativePlatform = MethodChannel('rhythmstar/native');

class RhythmStarGame {
  RhythmStarGame(this.onFrame, this.onError);
  final void Function(ui.Image) onFrame;
  final void Function(Object) onError;
  final _receive = ReceivePort();
  SendPort? _worker;
  Isolate? _isolate;
  bool _disposed = false;
  bool _active = true;
  String phase = '';

  Future<void> start() async {
    final paths =
        jsonDecode(await rootBundle.loadString('assets/resource_manifest.json'))
            as List;
    final resources = <String, Uint8List>{};
    await Future.wait(paths.cast<String>().map((path) async {
      final bytes = await rootBundle.load('assets/$path');
      resources[path] =
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    }));
    final saved =
        await nativePlatform.invokeMapMethod<String, dynamic>('initialize');
    final storage = <String, Uint8List>{
      for (final entry in (saved ?? <String, dynamic>{}).entries)
        entry.key: base64Decode(entry.value as String),
    };
    if (_disposed) return;
    _receive.listen((dynamic message) {
      if (_disposed) return;
      if (message is SendPort) {
        _worker = message;
        _worker!.send(['active', _active]);
      } else if (message is Map) {
        if (message['error'] != null) {
          onError(message['error']);
          return;
        }
        if (message['commands'] is List &&
            (message['commands'] as List).isNotEmpty) {
          nativePlatform
              .invokeMethod<void>('commands', message['commands'])
              .catchError(onError);
        }
        final nextPhase = message['phase'] as String?;
        if (nextPhase != null && phase != nextPhase) {
          phase = nextPhase;
          debugPrint('RhythmStar phase: $phase');
        }
        final pixels = message['pixels'] as TransferableTypedData?;
        if (pixels != null) {
          ui.decodeImageFromPixels(pixels.materialize().asUint8List(), 240, 320,
              ui.PixelFormat.rgba8888, (image) {
            if (_disposed) {
              image.dispose();
            } else {
              onFrame(image);
            }
            _worker?.send(['frameReady']);
          });
        }
      }
    });
    _isolate =
        await Isolate.spawn(_runGame, [_receive.sendPort, resources, storage]);
    if (_disposed) _isolate?.kill(priority: Isolate.immediate);
  }

  void key(String key, bool down) => _worker?.send(['key', key, down]);
  void releaseKeys() => _worker?.send(['release']);
  void press(String key) {
    this.key(key, true);
    this.key(key, false);
  }

  void setActive(bool active) {
    _active = active;
    _worker?.send(['active', active]);
    nativePlatform.invokeMethod<void>('active', {
      'active': active,
      'resumeMusic': phase != 'gameplay',
    }).catchError(onError);
  }

  void dispose() {
    _disposed = true;
    _worker?.send(['stop']);
    _receive.close();
    nativePlatform.invokeMethod<void>('dispose');
  }
}

void _runGame(List<dynamic> args) {
  final send = args[0] as SendPort;
  final receive = ReceivePort();
  late final DartGame game;
  Timer? timer;
  final clock = Stopwatch();
  final rgba = Int32List(240 * 320);
  final rgbaBytes = rgba.buffer.asUint8List();
  var active = false, framePending = false;
  String phase = '';
  const diagnostics = bool.fromEnvironment('RHYTHMSTAR_DIAGNOSTICS');
  var ticks = 0, totalMicros = 0, maxMicros = 0;

  void fail(Object error, StackTrace stack) {
    timer?.cancel();
    clock.stop();
    send.send({'error': '$error\n$stack'});
  }

  void tick() {
    if (!active) return;
    final measure = diagnostics ? (Stopwatch()..start()) : null;
    try {
      game.tick(clock.elapsedMilliseconds);
      phase = game.phase;
      final message = <String, dynamic>{
        'commands': List<List<Object>>.of(game.c.commands),
        'phase': phase
      };
      if (!framePending) {
        framePending = true;
        game.screen.writeRgba(rgba);
        // fromList copies staging bytes before the next game tick reuses them.
        message['pixels'] = TransferableTypedData.fromList([rgbaBytes]);
      }
      send.send(message);
      game.c.commands.clear();
      if (measure != null) {
        final micros = measure.elapsedMicroseconds;
        totalMicros += micros;
        if (micros > maxMicros) maxMicros = micros;
        if (++ticks == 100) {
          debugPrint(
              'RhythmStar Dart timing $phase: avg=${totalMicros ~/ 100000}ms max=${maxMicros ~/ 1000}ms');
          ticks = 0;
          totalMicros = 0;
          maxMicros = 0;
        }
      }
    } catch (error, stack) {
      fail(error, stack);
    }
  }

  try {
    game = DartGame(GameContext(
        args[1] as Map<String, Uint8List>, args[2] as Map<String, Uint8List>));
    receive.listen((dynamic message) {
      try {
        switch (message[0]) {
          case 'key':
            if (active) {
              game.key(message[1] as String, message[2] as bool);
            }
          case 'frameReady':
            framePending = false;
          case 'release':
            game.releaseKeys();
          case 'active':
            final next = message[1] as bool;
            if (active == next) break;
            game.releaseKeys();
            if (!next && phase == 'gameplay') {
              game.key('back', true);
              tick();
              game.releaseKeys();
              tick();
            }
            active = next;
            if (active) {
              clock.start();
              tick();
            } else {
              clock.stop();
            }
          case 'stop':
            game.stop();
            timer?.cancel();
            receive.close();
        }
      } catch (error, stack) {
        fail(error, stack);
      }
    });
    timer = Timer.periodic(const Duration(milliseconds: 50), (_) => tick());
    send.send(receive.sendPort);
  } catch (error, stack) {
    fail(error, stack);
    receive.close();
  }
}
