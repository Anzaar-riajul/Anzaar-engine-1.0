import 'dart:ffi';
import 'dart:io';
import 'package:sodium/sodium.dart';

DynamicLibrary _loadSodium() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libsodium.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('sodium.dll');
  }
  return DynamicLibrary.process();
}

Future<Sodium>? _cachedSodium;

Future<Sodium> initSodium() {
  return _cachedSodium ??= SodiumInit.init(_loadSodium);
}
