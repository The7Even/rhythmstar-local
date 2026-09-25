import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const RhythmStarApp());
}

class RhythmStarApp extends StatelessWidget {
  const RhythmStarApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
      debugShowCheckedModeBanner: false, color: Colors.black, home: GamePage());
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  ui.Image? _image;
  String? _error;
  late final RhythmStarGame _game;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = RhythmStarGame((image) {
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() => _image = image);
      old?.dispose();
    }, (error) {
      if (mounted) setState(() => _error = '$error');
    });
    nativePlatform.setMethodCallHandler((call) async {
      if (call.method == 'key') {
        final args = call.arguments as Map;
        _game.key(args['key'] as String, args['down'] as bool);
      } else if (call.method == 'focus') {
        _game.setActive(call.arguments as bool);
      } else if (call.method == 'error') {
        if (mounted) setState(() => _error = '${call.arguments}');
      } else if (call.method == 'releaseKeys') {
        _game.releaseKeys();
      }
    });
    _game.start().catchError((Object error, StackTrace stack) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nativePlatform.setMethodCallHandler(null);
    _game.dispose();
    _image?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _game.setActive(state == AppLifecycleState.resumed);
  }

  String? _keyFor(KeyEvent event) {
    final key = event.physicalKey;
    if (key == PhysicalKeyboardKey.arrowUp) {
      return 'up';
    }
    if (key == PhysicalKeyboardKey.arrowDown) {
      return 'down';
    }
    if (key == PhysicalKeyboardKey.arrowLeft) {
      return 'left';
    }
    if (key == PhysicalKeyboardKey.arrowRight) {
      return 'right';
    }
    if (key == PhysicalKeyboardKey.enter || key == PhysicalKeyboardKey.space) {
      return 'ok';
    }
    if (key == PhysicalKeyboardKey.escape ||
        key == PhysicalKeyboardKey.backspace) {
      return 'back';
    }
    final label = event.logicalKey.keyLabel;
    if (RegExp(r'^[0-9]$').hasMatch(label)) {
      return label;
    }
    if (label == '*') return 'star';
    if (label == '#') return 'hash';
    return null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) {
            _game.press('back');
          }
        },
        child: KeyboardListener(
          focusNode: _focus,
          onKeyEvent: (event) {
            if (event is KeyDownEvent || event is KeyUpEvent) {
              final key = _keyFor(event);
              if (key != null) {
                _game.key(key, event is KeyDownEvent);
              }
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ColoredBox(
                    color: Colors.black,
                    child: _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)))
                        : _image == null
                            ? const Center(child: CircularProgressIndicator())
                            : CustomPaint(painter: _GamePainter(_image!)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _GamePainter extends CustomPainter {
  const _GamePainter(this.image);
  final ui.Image image;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_GamePainter oldDelegate) => oldDelegate.image != image;
}
