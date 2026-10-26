import 'package:shared_preferences/shared_preferences.dart';

enum SyncNetworkPolicy { wifiOnly, wifiAndMobile, disabled }

class SyncPolicy {
  static Future<SyncNetworkPolicy> get imageSyncPolicy async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('imageSyncPolicy') ?? 0;
    return SyncNetworkPolicy.values[index];
  }

  static Future<void> setImageSyncPolicy(SyncNetworkPolicy policy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('imageSyncPolicy', policy.index);
  }
}
