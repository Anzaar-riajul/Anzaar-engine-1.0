import 'dart:math';

/// Injects random failures into the sync pipeline (for Chaos Testing only).
class ChaosInjector {
  static final ChaosInjector instance = ChaosInjector._();
  ChaosInjector._();

  bool _enabled = false;
  final _rng = Random();

  void enable() => _enabled = true;
  void disable() => _enabled = false;

  /// Randomly simulate socket disconnects during transmission.
  bool shouldDropSocket() {
    if (!_enabled) return false;
    return _rng.nextInt(10) == 0; // 10% chance
  }

  /// Randomly corrupt frame data.
  void corruptFrame(List<int> data) {
    if (!_enabled) return;
    if (_rng.nextInt(5) == 0 && data.length > 10) {
      data[data.length - 1] ^= 0xFF; // Flip bits
    }
  }
}
