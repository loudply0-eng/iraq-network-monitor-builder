import 'package:abrj_iraq/services/signal_history_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignalHistoryAnalytics.filterByWindow', () {
    final now = DateTime.utc(2026, 11, 27, 12);

    final records = <Map<String, dynamic>>[
      {'time': now.subtract(const Duration(minutes: 10)).toIso8601String()},
      {'time': now.subtract(const Duration(minutes: 30)).toIso8601String()},
      {'time': now.subtract(const Duration(hours: 2)).toIso8601String()},
      {'time': 'not-a-date'},
      {'time': now.add(const Duration(minutes: 1)).toIso8601String()},
    ];

    test('keeps only valid readings from the last 15 minutes', () {
      final result = SignalHistoryAnalytics.filterByWindow(
        records: records,
        window: SignalHistoryWindow.minutes15,
        now: now,
      );

      expect(result, hasLength(1));
      expect(result.single, same(records.first));
    });

    test('keeps readings from the last hour and excludes future records', () {
      final result = SignalHistoryAnalytics.filterByWindow(
        records: records,
        window: SignalHistoryWindow.hour1,
        now: now,
      );

      expect(result, hasLength(2));
    });

    test('all history preserves records without a valid timestamp', () {
      final result = SignalHistoryAnalytics.filterByWindow(
        records: records,
        window: SignalHistoryWindow.all,
        now: now,
      );

      expect(result, hasLength(records.length));
    });
  });

  group('SignalHistoryAnalytics.summarize', () {
    test('calculates descriptive RSRP, SINR and distinct-cell statistics', () {
      final result = SignalHistoryAnalytics.summarize([
        {'rsrp': -100, 'sinr': 10.0, 'cellId': '1001'},
        {'rsrp': -110, 'sinr': -5.0, 'cellId': '1001'},
        {'rsrp': -90, 'sinr': null, 'cellId': '2002'},
        {'rsrp': null, 'sinr': 999.0, 'cellId': ''},
        {'rsrp': -999, 'sinr': null, 'cellId': '—'},
      ]);

      expect(result.readingCount, 5);
      expect(result.rsrpSampleCount, 3);
      expect(result.sinrSampleCount, 2);
      expect(result.averageRsrp, -100);
      expect(result.weakestRsrp, -110);
      expect(result.strongestRsrp, -90);
      expect(result.averageSinr, 2.5);
      expect(result.distinctCellCount, 2);
    });

    test('reports unavailable metrics instead of inventing zero values', () {
      final result = SignalHistoryAnalytics.summarize([
        {'time': '2026-11-27T12:00:00Z', 'rsrp': null, 'sinr': null},
      ]);

      expect(result.readingCount, 1);
      expect(result.rsrpSampleCount, 0);
      expect(result.sinrSampleCount, 0);
      expect(result.averageRsrp, isNull);
      expect(result.weakestRsrp, isNull);
      expect(result.strongestRsrp, isNull);
      expect(result.averageSinr, isNull);
      expect(result.distinctCellCount, 0);
    });

    test('returns empty summary for an empty history', () {
      final result = SignalHistoryAnalytics.summarize([]);

      expect(result.readingCount, 0);
      expect(result.averageRsrp, isNull);
      expect(result.averageSinr, isNull);
      expect(result.distinctCellCount, 0);
    });
  });
}
