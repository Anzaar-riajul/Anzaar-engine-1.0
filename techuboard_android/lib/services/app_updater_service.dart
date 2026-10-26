import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String currentVersion;
  final int latestBuildNumber;
  final int currentBuildNumber;
  final String releaseNotes;
  final String? downloadUrl;
  final String? apkName;

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    required this.latestBuildNumber,
    required this.currentBuildNumber,
    required this.releaseNotes,
    this.downloadUrl,
    this.apkName,
  });
}

class AppUpdaterService {
  static final AppUpdaterService instance = AppUpdaterService._();
  AppUpdaterService._();

  static const String repoOwner = 'Anzaar-riajul';
  static const String repoName = 'Anzaar-engine-1.0';
  static const MethodChannel _channel = MethodChannel('com.techuboard.app/open_folder');

  final ValueNotifier<UpdateInfo?> updateNotifier = ValueNotifier<UpdateInfo?>(null);
  Timer? _periodicTimer;
  bool _isChecking = false;

  /// Starts recurring background checks (runs immediately, then every 30 mins)
  void startAutoCheck() {
    _periodicTimer?.cancel();
    checkForUpdate();
    _periodicTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      checkForUpdate();
    });
  }

  /// Get local app version and build number from native package manager
  Future<Map<String, dynamic>> _getLocalVersionInfo() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getAppVersionInfo');
      if (info != null) {
        return {
          'versionName': info['versionName']?.toString() ?? '1.0.81',
          'versionCode': int.tryParse(info['versionCode']?.toString() ?? '81') ?? 81,
        };
      }
    } catch (e) {
      debugPrint('[AppUpdater] getAppVersionInfo error: $e');
    }
    return {
      'versionName': '1.0.81',
      'versionCode': 81,
    };
  }

  /// Extract build number from GitHub tag like "android-v1.0-85" -> 85
  int _extractBuildNumber(String tag) {
    final match = RegExp(r'[-v](\d+)$').firstMatch(tag.trim());
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// Check GitHub releases for a newer APK version.
  Future<UpdateInfo> checkForUpdate() async {
    if (_isChecking) {
      return updateNotifier.value ?? const UpdateInfo(
        hasUpdate: false,
        latestVersion: '',
        currentVersion: '',
        latestBuildNumber: 0,
        currentBuildNumber: 0,
        releaseNotes: '',
      );
    }
    _isChecking = true;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final localInfo = await _getLocalVersionInfo();
      final currentVersionName = localInfo['versionName'] as String;
      final currentBuildNumber = localInfo['versionCode'] as int;

      final uri = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'Techuboard-Android-App');

      final response = await request.close();
      if (response.statusCode != 200) {
        debugPrint('[AppUpdater] GitHub API returned status ${response.statusCode}');
        final fallback = UpdateInfo(
          hasUpdate: false,
          latestVersion: currentVersionName,
          currentVersion: currentVersionName,
          latestBuildNumber: currentBuildNumber,
          currentBuildNumber: currentBuildNumber,
          releaseNotes: '',
        );
        return fallback;
      }

      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;

      final rawTag = data['tag_name'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? '';
      final assets = (data['assets'] as List<dynamic>? ?? []);

      String? apkUrl;
      String? apkName;

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkName = name;
          break;
        }
      }

      final remoteBuild = _extractBuildNumber(rawTag);
      final isNewer = (remoteBuild > 0 && currentBuildNumber > 0)
          ? remoteBuild > currentBuildNumber
          : _isVersionGreater(rawTag, currentVersionName);

      final displayLatest = rawTag.isNotEmpty ? rawTag : 'v$currentVersionName';

      final info = UpdateInfo(
        hasUpdate: isNewer && apkUrl != null,
        latestVersion: displayLatest,
        currentVersion: 'v$currentVersionName (Build $currentBuildNumber)',
        latestBuildNumber: remoteBuild,
        currentBuildNumber: currentBuildNumber,
        releaseNotes: releaseNotes,
        downloadUrl: apkUrl,
        apkName: apkName,
      );

      updateNotifier.value = info;
      return info;
    } catch (e) {
      debugPrint('[AppUpdater] Failed to check for updates: $e');
      final fallback = const UpdateInfo(
        hasUpdate: false,
        latestVersion: '',
        currentVersion: '',
        latestBuildNumber: 0,
        currentBuildNumber: 0,
        releaseNotes: '',
      );
      return fallback;
    } finally {
      client.close();
      _isChecking = false;
    }
  }

  /// Downloads the APK directly and invokes native package installer.
  Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(downloadUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Techuboard-Android-App');
      final response = await request.close();

      HttpClientResponse downloadResponse = response;
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectLocation = response.headers.value('location');
        if (redirectLocation != null) {
          final redirectUri = Uri.parse(redirectLocation);
          final redirectRequest = await client.getUrl(redirectUri);
          redirectRequest.headers.set('User-Agent', 'Techuboard-Android-App');
          downloadResponse = await redirectRequest.close();
        }
      }

      if (downloadResponse.statusCode != 200) {
        throw Exception('Download failed with status ${downloadResponse.statusCode}');
      }

      final contentLength = downloadResponse.contentLength;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/techuboard_update.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in downloadResponse) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          onProgress(receivedBytes / contentLength, receivedBytes, contentLength);
        }
      }

      await sink.flush();
      await sink.close();

      debugPrint('[AppUpdater] APK downloaded to ${apkFile.path}, launching installer...');

      // Launch native Android package installer directly
      await _channel.invokeMethod('installApk', {
        'filePath': apkFile.path,
      });
    } finally {
      client.close();
    }
  }

  bool _isVersionGreater(String remote, String current) {
    if (remote.isEmpty) return false;
    final remoteClean = remote.split('-').first.replaceAll(RegExp(r'[^0-9.]'), '');
    final currentClean = current.split('-').first.replaceAll(RegExp(r'[^0-9.]'), '');

    final rParts = remoteClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cParts = currentClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }
}
