import 'package:abrj_iraq/services/network_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkDiagnostics.summarize', () {
    test('summarizes successful TCP attempts and ignores failures', () {
      final result = NetworkDiagnostics.summarize(<int?>[20, 30, null, 25]);

      expect(result.attempts, 4);
      expect(result.successes, 3);
      expect(result.failures, 1);
      expect(result.minimumMs, 20);
      expect(result.maximumMs, 30);
      expect(result.averageMs, 25);
      expect(result.averageVariationMs, 7.5);
    });

    test('returns unavailable metrics when every attempt fails', () {
      final result = NetworkDiagnostics.summarize(<int?>[null, null, null]);

      expect(result.attempts, 3);
      expect(result.successes, 0);
      expect(result.failures, 3);
      expect(result.minimumMs, isNull);
      expect(result.maximumMs, isNull);
      expect(result.averageMs, isNull);
      expect(result.averageVariationMs, isNull);
    });

    test('does not invent variation from a single successful attempt', () {
      final result = NetworkDiagnostics.summarize(<int?>[null, 42, null]);

      expect(result.successes, 1);
      expect(result.averageMs, 42);
      expect(result.averageVariationMs, isNull);
    });
  });

  test('provides three independent public TCP diagnostic endpoints', () {
    expect(NetworkDiagnostics.endpoints.map((item) => item.host).toSet(), {
      '1.1.1.1',
      '8.8.8.8',
      '9.9.9.9',
    });
  });
}
