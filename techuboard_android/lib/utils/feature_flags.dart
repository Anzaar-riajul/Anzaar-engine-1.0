import 'package:shared_preferences/shared_preferences.dart';

/// Feature Flags for Canary Rollout & Safe Automated Rollback.
class FeatureFlags {
  static const String _keyV4Sync = 'ff_v4_sync_enabled';
  static const String _keyImageSync = 'ff_image_sync_enabled';
  static const String _keyFloatingHub = 'ff_floating_hub_enabled';

  static Future<bool> isV4SyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyV4Sync) ?? true;
  }

  static Future<bool> isImageSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyImageSync) ?? true;
  }

  static Future<bool> isFloatingHubEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFloatingHub) ?? true;
  }

  /// Emergency rollback: disable V4 sync immediately in case of unexpected protocol regression.
  static Future<void> triggerEmergencyRollback() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyV4Sync, false);
  }
}
