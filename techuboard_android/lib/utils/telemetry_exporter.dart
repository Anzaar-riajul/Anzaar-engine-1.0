import 'dart:async';
import 'dart:convert';
import '../log_manager.dart';

/// OpenTelemetry-compatible metrics exporter tracking the Four Golden Signals:
/// Latency, Traffic, Errors, and Saturation.
class TelemetryExporter {
  static final TelemetryExporter instance = TelemetryExporter._();
  TelemetryExporter._();

  int _syncSuccessCount = 0;
  int _syncErrorCount = 0;
  int _bytesTransferred = 0;

  void recordSyncSuccess({required int bytes, required Duration latency}) {
    _syncSuccessCount++;
    _bytesTransferred += bytes;
    appLog('Telemetry: Sync Success', level: 'info', metadata: {
      'latency_ms': latency.inMilliseconds,
      'bytes': bytes,
      'signal': 'latency_and_traffic',
    });
  }

  void recordSyncError(String reason) {
    _syncErrorCount++;
    appLog('Telemetry: Sync Error', level: 'error', metadata: {
      'reason': reason,
      'signal': 'errors',
    });
  }

  /// Calculates current Sync Delivery Success Rate (SLO target: >= 99.9%).
  double get syncSuccessRate {
    final total = _syncSuccessCount + _syncErrorCount;
    if (total == 0) return 100.0;
    return (_syncSuccessCount / total) * 100.0;
  }
}
