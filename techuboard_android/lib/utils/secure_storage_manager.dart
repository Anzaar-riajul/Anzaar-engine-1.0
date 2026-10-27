import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SecureStorageManager provides a unified interface for encrypted at-rest storage.
/// It wraps FlutterSecureStorage and provides migration logic from SharedPreferences.
class SecureStorageManager {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  /// Migrates a sensitive key from plaintext SharedPreferences to encrypted SecureStorage.
  static Future<void> migrate(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(key)) {
      final value = prefs.getString(key);
      if (value != null) {
        await write(key, value);
        if (key != 'peerId') {
          await prefs.remove(key);
        }
      }
    }
  }
}
