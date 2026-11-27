/// Time windows and descriptive statistics for the locally saved signal history.
enum SignalHistoryWindow {
  minutes15,
  hour1,
  all,
}

/// Descriptive statistics calculated only from readings that contain each metric.
class SignalHistorySummary {
  const SignalHistorySummary({
    required this.readingCount,
    required this.rsrpSampleCount,
    required this.sinrSampleCount,
    required this.averageRsrp,
    required this.weakestRsrp,
    required this.strongestRsrp,
    required this.averageSinr,
    required this.distinctCellCount,
  });

  final int readingCount;
  final int rsrpSampleCount;
  final int sinrSampleCount;
  final double? averageRsrp;
  final int? weakestRsrp;
  final int? strongestRsrp;
  final double? averageSinr;
  final int distinctCellCount;
}

/// Filters recorded measurements and calculates transparent, non-predictive summaries.
class SignalHistoryAnalytics {
  SignalHistoryAnalytics._();

  static Duration? durationFor(SignalHistoryWindow window) => switch (window) {
        SignalHistoryWindow.minutes15 => const Duration(minutes: 15),
        SignalHistoryWindow.hour1 => const Duration(hours: 1),
        SignalHistoryWindow.all => null,
      };

  static List<Map<String, dynamic>> filterByWindow({
    required Iterable<Map<String, dynamic>> records,
    required SignalHistoryWindow window,
    DateTime? now,
  }) {
    final duration = durationFor(window);
    if (duration == null) return List<Map<String, dynamic>>.of(records);

    final currentTime = now ?? DateTime.now();
    final cutoff = currentTime.subtract(duration);
    return records.where((record) {
      final timestamp = DateTime.tryParse(record['time']?.toString() ?? '');
      return timestamp != null &&
          !timestamp.isBefore(cutoff) &&
          !timestamp.isAfter(currentTime);
    }).toList();
  }

  static SignalHistorySummary summarize(
    Iterable<Map<String, dynamic>> records,
  ) {
    final items = records.toList(growable: false);
    final rsrpValues = <int>[];
    final sinrValues = <double>[];
    final cellIds = <String>{};

    for (final item in items) {
      final rsrp = _number(item['rsrp']);
      if (rsrp != null && rsrp >= -200 && rsrp <= 0) {
        rsrpValues.add(rsrp.round());
      }

      final sinr = _number(item['sinr']);
      if (sinr != null && sinr >= -100 && sinr <= 100) {
        sinrValues.add(sinr);
      }

      final cellId = item['cellId']?.toString().trim() ?? '';
      if (cellId.isNotEmpty && cellId != '—') cellIds.add(cellId);
    }

    final rsrpSum = rsrpValues.fold<int>(0, (sum, value) => sum + value);
    final sinrSum = sinrValues.fold<double>(0, (sum, value) => sum + value);

    return SignalHistorySummary(
      readingCount: items.length,
      rsrpSampleCount: rsrpValues.length,
      sinrSampleCount: sinrValues.length,
      averageRsrp: rsrpValues.isEmpty ? null : rsrpSum / rsrpValues.length,
      weakestRsrp: rsrpValues.isEmpty
          ? null
          : rsrpValues.reduce((a, b) => a < b ? a : b),
      strongestRsrp: rsrpValues.isEmpty
          ? null
          : rsrpValues.reduce((a, b) => a > b ? a : b),
      averageSinr: sinrValues.isEmpty ? null : sinrSum / sinrValues.length,
      distinctCellCount: cellIds.length,
    );
  }

  static double? _number(dynamic value) {
    final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}
