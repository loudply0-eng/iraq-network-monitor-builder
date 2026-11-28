/// Testable summaries for TCP connection setup diagnostics.
class TcpEndpoint {
  const TcpEndpoint({
    required this.labelAr,
    required this.labelEn,
    required this.host,
    this.port = 443,
  });

  final String labelAr;
  final String labelEn;
  final String host;
  final int port;

  String label(bool english) => english ? labelEn : labelAr;
}

class TcpEndpointStats {
  const TcpEndpointStats({
    required this.attempts,
    required this.successes,
    required this.minimumMs,
    required this.maximumMs,
    required this.averageMs,
    required this.averageVariationMs,
  });

  final int attempts;
  final int successes;
  final int? minimumMs;
  final int? maximumMs;
  final double? averageMs;
  final double? averageVariationMs;

  int get failures => attempts - successes;
}

class TcpEndpointResult {
  const TcpEndpointResult({
    required this.endpoint,
    required this.stats,
  });

  final TcpEndpoint endpoint;
  final TcpEndpointStats stats;
}

class NetworkDiagnostics {
  NetworkDiagnostics._();

  static const List<TcpEndpoint> endpoints = <TcpEndpoint>[
    TcpEndpoint(
      labelAr: 'Cloudflare',
      labelEn: 'Cloudflare',
      host: '1.1.1.1',
    ),
    TcpEndpoint(
      labelAr: 'Google',
      labelEn: 'Google',
      host: '8.8.8.8',
    ),
    TcpEndpoint(
      labelAr: 'Quad9',
      labelEn: 'Quad9',
      host: '9.9.9.9',
    ),
  ];

  /// Null samples represent failed attempts; only successful samples enter
  /// latency statistics. Variation is the mean absolute delta between
  /// consecutive successful samples, not an ICMP/RFC jitter measurement.
  static TcpEndpointStats summarize(Iterable<int?> samples) {
    final all = samples.toList(growable: false);
    final successful = all.whereType<int>().where((value) => value >= 0).toList();
    if (successful.isEmpty) {
      return TcpEndpointStats(
        attempts: all.length,
        successes: 0,
        minimumMs: null,
        maximumMs: null,
        averageMs: null,
        averageVariationMs: null,
      );
    }

    final sum = successful.fold<int>(0, (total, value) => total + value);
    final variations = <int>[];
    for (var index = 1; index < successful.length; index++) {
      variations.add((successful[index] - successful[index - 1]).abs());
    }
    final variationSum = variations.fold<int>(0, (total, value) => total + value);

    return TcpEndpointStats(
      attempts: all.length,
      successes: successful.length,
      minimumMs: successful.reduce((a, b) => a < b ? a : b),
      maximumMs: successful.reduce((a, b) => a > b ? a : b),
      averageMs: sum / successful.length,
      averageVariationMs: variations.isEmpty ? null : variationSum / variations.length,
    );
  }
}
