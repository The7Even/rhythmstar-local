import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_list.dart';

void main() {
  test(
      'native renderer matches original web pixels across complete menu and play flows',
      () {
    final fixtures = jsonDecode(utf8.decode(gzip.decode(
            File('test/fixtures/render-parity.json.gz').readAsBytesSync())))
        as List;
    final renderer = DisplayListRenderer();
    for (final raw in fixtures) {
      final frame = raw as Map<String, dynamic>;
      renderer.draw(frame);
      final bytes = base64Decode(frame['rgb565'] as String);
      final expected = ByteData.sublistView(bytes);
      final actual = renderer.screen.pixels;
      var differences = 0;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != expected.getUint16(i * 2, Endian.little)) {
          differences++;
        }
      }
      expect(differences, 0,
          reason: '${frame['name']}: $differences differing pixels');
    }
  });
}
