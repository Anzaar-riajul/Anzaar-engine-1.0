import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String? apkName;

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    this.downloadUrl,
    this.apkName,
  });
}

class AppUpdaterService {
  static final AppUpdaterService instance = AppUpdaterService._();
  AppUpdaterService._();

  static const String currentVersion = '1.0.32';
  static const String repoOwner = 'Anzaar-riajul';
  static const String repoName = 'Anzaar-engine-1.0';
  static const MethodChannel _channel = MethodChannel('com.techuboard.app/open_folder');

  /// Check GitHub releases for a newer APK version.
  Future<UpdateInfo> checkForUpdate() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'Techuboard-Android-App');

      final response = await request.close();
      if (response.statusCode != 200) {
        debugPrint('[AppUpdater] GitHub API returned status ${response.statusCode}');
        return const UpdateInfo(
          hasUpdate: false,
          latestVersion: currentVersion,
          currentVersion: currentVersion,
          releaseNotes: '',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;

      final tagName = (data['tag_name'] as String? ?? '').replaceAll('v', '').replaceAll('android-', '').trim();
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

      final isNewer = _isVersionGreater(tagName, currentVersion);

      return UpdateInfo(
        hasUpdate: isNewer && apkUrl != null,
        latestVersion: tagName.isNotEmpty ? tagName : currentVersion,
        currentVersion: currentVersion,
        releaseNotes: releaseNotes,
        downloadUrl: apkUrl,
        apkName: apkName,
      );
    } catch (e) {
      debugPrint('[AppUpdater] Failed to check for updates: $e');
      return const UpdateInfo(
        hasUpdate: false,
        latestVersion: currentVersion,
        currentVersion: currentVersion,
        releaseNotes: '',
      );
    } finally {
      client.close();
    }
  }

  /// Downloads the APK and triggers Android system package installer.
  Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(downloadUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Techuboard-Android-App');
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 302) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      // If redirected, follow the redirect
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
          onProgress(receivedBytes / contentLength);
        }
      }

      await sink.flush();
      await sink.close();

      debugPrint('[AppUpdater] APK downloaded to ${apkFile.path}, launching installer...');

      // Launch native Android package installer
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
