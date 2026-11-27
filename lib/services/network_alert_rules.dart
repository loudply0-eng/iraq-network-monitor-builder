/// Pure rules for deciding when a falling cellular RSRP reading is alert-worthy.
class NetworkAlertRules {
  NetworkAlertRules._();

  static const int minRsrpThresholdDbm = -120;
  static const int maxRsrpThresholdDbm = -90;
  static const int defaultRsrpThresholdDbm = -110;
  static const int hysteresisDb = 5;

  /// The UI selects thresholds in 5 dB increments.
  static const int rsrpThresholdSteps =
      (maxRsrpThresholdDbm - minRsrpThresholdDbm) ~/ 5;

  static int clampThreshold(int value) =>
      value.clamp(minRsrpThresholdDbm, maxRsrpThresholdDbm).toInt();

  /// Avoids alerts for small fluctuations around the selected threshold.
  ///
  /// A new alert is raised only when the previous reading was more than
  /// [hysteresisDb] stronger than the threshold and the current reading has
  /// reached the threshold or dropped below it.
  static bool shouldNotifyForRsrpDrop({
    required int? previousRsrp,
    required int? currentRsrp,
    required int thresholdDbm,
  }) {
    if (previousRsrp == null || currentRsrp == null) return false;
    final threshold = clampThreshold(thresholdDbm);
    return previousRsrp > threshold + hysteresisDb &&
        currentRsrp <= threshold;
  }
}
