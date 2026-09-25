import 'dart:typed_data';

/// Static Unicode mapping data only; decoding executes in Dart.
class Cp949 {
  Cp949(Uint8List bytes) : table = ByteData.sublistView(bytes);
  final ByteData table;
  int code(int lead, int trail) =>
      table.getUint16((lead * 256 + trail) * 2, Endian.little);
  String decode(Uint8List bytes) {
    final result = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b < 128) {
        result.add(b);
        continue;
      }
      if (i + 1 == bytes.length) {
        result.add(0xfffd);
        break;
      }
      final c = code(b, bytes[i + 1]);
      if (c == 0xfffd && bytes[i + 1] < 128) {
        result.add(c);
      } else {
        result.add(c);
        i++;
      }
    }
    return String.fromCharCodes(result);
  }
}
