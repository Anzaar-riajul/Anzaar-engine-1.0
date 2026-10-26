import 'package:sodium_libs/sodium_libs.dart';

Future<Sodium>? _cachedSodium;

Future<Sodium> initSodium() {
  return _cachedSodium ??= SodiumInit.init();
}
