import 'package:abrj_iraq/services/network_alert_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkAlertRules', () {
    test('keeps the default threshold within supported bounds', () {
      expect(NetworkAlertRules.defaultRsrpThresholdDbm, -110);
      expect(NetworkAlertRules.clampThreshold(-130), -120);
      expect(NetworkAlertRules.clampThreshold(-80), -90);
    });

    test('alerts when a reading crosses the configured threshold', () {
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: -100,
          currentRsrp: -110,
          thresholdDbm: -110,
        ),
        isTrue,
      );
    });

    test('uses hysteresis to avoid alerts from small signal fluctuations', () {
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: -105,
          currentRsrp: -110,
          thresholdDbm: -110,
        ),
        isFalse,
      );
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: -104,
          currentRsrp: -111,
          thresholdDbm: -110,
        ),
        isTrue,
      );
    });

    test('does not alert when either reading is unavailable', () {
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: null,
          currentRsrp: -115,
          thresholdDbm: -110,
        ),
        isFalse,
      );
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: -100,
          currentRsrp: null,
          thresholdDbm: -110,
        ),
        isFalse,
      );
    });

    test('clamps thresholds before evaluating an alert', () {
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: -100,
          currentRsrp: -120,
          thresholdDbm: -200,
        ),
        isTrue,
      );
      expect(
        NetworkAlertRules.shouldNotifyForRsrpDrop(
          previousRsrp: -100,
          currentRsrp: -90,
          thresholdDbm: 10,
        ),
        isFalse,
      );
    });
  });
}
