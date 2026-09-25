import 'sine_table.dart';

int nativeSine(int angle) {
  if (angle < 0) angle += 411774;
  if (angle > 411773) angle %= 411774;
  if (angle < 102943) return sineTable[angle * 256 ~/ 102943];
  if (angle < 205887) return sineTable[256 - (angle - 102943) * 256 ~/ 102943];
  if (angle < 308830) return -sineTable[(angle - 205887) * 256 ~/ 102943];
  return -sineTable[256 - (angle - 308830) * 256 ~/ 102943];
}

int nativeCosine(int angle) {
  angle = angle.abs();
  if (angle > 411773) angle %= 411774;
  if (angle < 102943) return sineTable[256 - angle * 256 ~/ 102943];
  if (angle < 205887) return -sineTable[(angle - 102943) * 256 ~/ 102943];
  if (angle < 308830) return -sineTable[256 - (angle - 205887) * 256 ~/ 102943];
  return sineTable[(angle - 308830) * 256 ~/ 102943];
}
