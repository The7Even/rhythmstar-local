import 'dart:math' as math;

int judgeTiming(int differenceMs) {
  final d = differenceMs.abs();
  return d <= 59
      ? 4
      : d <= 99
          ? 3
          : d <= 149
              ? 2
              : d <= 199
                  ? 1
                  : 0;
}

/// Original integer scoring rules, including hold ticks and gauge debt.
class GameScoring {
  GameScoring(this.mode, [this.planetMultiplier = 65536])
      : gauge = 80 - mode * 5;
  final int mode, planetMultiplier;
  int score = 0, gauge, gaugeDebt = 0, combo = 0, maxCombo = 0;
  int multiplier = 65536, missStreak = 0, missPenalty = 0;
  final counts = List<int>.filled(5, 0);
  static const rewards = [0, 4, 12, 17, 27];
  static const gauges = [
    [-3, 0, 0, 1, 3],
    [-4, -2, 0, 1, 3],
    [-6, -3, 0, 1, 3]
  ];

  void hit(int grade, [bool awardPoints = true]) {
    counts[grade]++;
    combo = grade > 1 ? combo + 1 : 0;
    maxCombo = math.max(maxCombo, combo);
    if (combo > 1) {
      multiplier = (combo <= 19
              ? 1
              : combo <= 39
                  ? 2
                  : combo <= 69
                      ? 3
                      : combo <= 99
                          ? 4
                          : 5) *
          65536;
    }
    if (awardPoints) award(grade);
  }

  void award(int grade) {
    if (grade == 4 && missPenalty != 0) missPenalty += 2;
    final scale = (planetMultiplier * multiplier / 65536).floor();
    score = math.min(9999999, score + (rewards[grade] * scale / 65536).floor());
    final change = gauges[mode][grade];
    final debt = gaugeDebt + change;
    if (debt < 0) {
      gaugeDebt = debt;
    } else {
      gaugeDebt = 0;
      gauge += change;
    }
    gauge = math.min(99, gauge);
  }

  void miss([int? holdIndex]) {
    combo = 0;
    multiplier = 65536;
    counts[0]++;
    if (holdIndex == null) gaugeDebt -= 15;
    if (holdIndex != null && holdIndex % 10 != 0) return;
    if (++missStreak > 4) {
      missStreak = 0;
      missPenalty -= 2;
    }
    gauge += gauges[mode][0] + missPenalty;
  }

  int rank() {
    final total = counts.reduce((a, b) => a + b);
    if (total == 0) return 6;
    final accuracy = (counts[4] * 95 +
            counts[3] * 90 +
            counts[2] * 80 +
            counts[1] -
            counts[0] * 20) ~/
        total;
    final rate = combo * 100 ~/ total;
    final value = accuracy +
        (rate <= 29
            ? -3
            : rate <= 70
                ? 1
                : rate <= 99
                    ? 3
                    : 5);
    return value <= 70
        ? 6
        : value <= 74
            ? 5
            : value <= 79
                ? 4
                : value <= 89
                    ? 3
                    : value <= 94
                        ? 2
                        : value <= 99
                            ? 1
                            : 0;
  }
}
