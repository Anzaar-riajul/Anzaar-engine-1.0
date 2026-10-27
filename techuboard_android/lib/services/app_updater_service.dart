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
  final bool isDownloaded;
  final String? localApkPath;

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    required this.latestBuildNumber,
    required this.currentBuildNumber,
    required this.releaseNotes,
    this.downloadUrl,
    this.apkName,
    this.isDownloaded = false,
    this.localApkPath,
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

  /// Extract build number from GitHub tag like "android-v1.0-12396" -> 12396
  int _extractBuildNumber(String tag) {
    final match = RegExp(r'[-v](\d+)$').firstMatch(tag.trim());
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// Get target update file location for a specific build
  Future<File> getUpdateApkFile(int remoteBuild) async {
    final tempDir = await getTemporaryDirectory();
    final updatesDir = Directory('${tempDir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return File('${updatesDir.path}/Techuboard_build_$remoteBuild.apk');
  }

  /// Returns existing downloaded APK file if it exists and has valid size (>15MB)
  Future<File?> getExistingDownloadedApk(int remoteBuild) async {
    if (remoteBuild <= 0) return null;
    try {
      final file = await getUpdateApkFile(remoteBuild);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 15 * 1024 * 1024) {
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Directly launch the system package installer for an already downloaded APK
  Future<void> installLocalApk(String filePath) async {
    await _channel.invokeMethod('installApk', {
      'filePath': filePath,
    });
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

      String rawTag = '';
      String releaseNotes = '';
      String? apkUrl;
      String? apkName = 'Techuboard-Android-v1.0.apk';

      // 1. Direct Web Redirect check (Zero Rate Limit - bypasses GitHub 60 req/hr API restriction)
      try {
        final headUri = Uri.parse('https://github.com/$repoOwner/$repoName/releases/latest');
        final headReq = await client.getUrl(headUri);
        headReq.followRedirects = false;
        headReq.headers.set('User-Agent', 'Mozilla/5.0 (Android; Mobile)');
        final headResp = await headReq.close();
        final location = headResp.headers.value('location');
        if (location != null && location.contains('/releases/tag/')) {
          rawTag = location.split('/releases/tag/').last.trim();
          apkUrl = 'https://github.com/$repoOwner/$repoName/releases/download/$rawTag/Techuboard-Android-v1.0.apk';
        }
      } catch (e) {
        debugPrint('[AppUpdater] Web redirect check error: $e');
      }

      // 2. If tag was not resolved from redirect, query GitHub API
      if (rawTag.isEmpty) {
        try {
          final uri = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
          final request = await client.getUrl(uri);
          request.headers.set('Accept', 'application/vnd.github.v3+json');
          request.headers.set('User-Agent', 'Techuboard-Android-App');
          final response = await request.close();
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final data = json.decode(body) as Map<String, dynamic>;
            rawTag = data['tag_name'] as String? ?? '';
            releaseNotes = data['body'] as String? ?? '';
            final assets = (data['assets'] as List<dynamic>? ?? []);
            for (final asset in assets) {
              final name = asset['name'] as String? ?? '';
              if (name.toLowerCase().endsWith('.apk')) {
                apkUrl = asset['browser_download_url'] as String?;
                apkName = name;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('[AppUpdater] API check error: $e');
        }
      }

      if (rawTag.isEmpty) {
        final info = UpdateInfo(
          hasUpdate: false,
          latestVersion: 'v$currentVersionName',
          currentVersion: 'v$currentVersionName (Build $currentBuildNumber)',
          latestBuildNumber: currentBuildNumber,
          currentBuildNumber: currentBuildNumber,
          releaseNotes: '',
          downloadUrl: null,
          apkName: apkName,
        );
        updateNotifier.value = info;
        return info;
      }

      final remoteBuild = _extractBuildNumber(rawTag);
      int normalizedCurrent = currentBuildNumber;
      if (normalizedCurrent > 10000 && remoteBuild < 1000) {
        normalizedCurrent = normalizedCurrent % 1000;
      }
      int normalizedRemote = remoteBuild;
      if (normalizedRemote > 10000 && normalizedCurrent < 1000) {
        normalizedRemote = normalizedRemote % 1000;
      }

      // Strict dynamic check:
      // If remote build number is available, remote build MUST be strictly greater than current build!
      bool isNewer = false;
      if (normalizedRemote > 0 && normalizedCurrent > 0) {
        isNewer = normalizedRemote > normalizedCurrent;
      } else {
        isNewer = _isVersionGreater(rawTag, currentVersionName);
      }

      final displayLatest = rawTag.isNotEmpty ? rawTag : 'v$currentVersionName';

      // Check if this newer build has ALREADY been downloaded to local storage
      bool isDownloaded = false;
      String? localApkPath;
      if (isNewer && remoteBuild > 0) {
        final existingFile = await getExistingDownloadedApk(remoteBuild);
        if (existingFile != null) {
          isDownloaded = true;
          localApkPath = existingFile.path;
        }
      }

      final info = UpdateInfo(
        hasUpdate: isNewer && apkUrl != null,
        latestVersion: displayLatest,
        currentVersion: 'v$currentVersionName (Build $currentBuildNumber)',
        latestBuildNumber: remoteBuild,
        currentBuildNumber: currentBuildNumber,
        releaseNotes: releaseNotes,
        downloadUrl: apkUrl,
        apkName: apkName,
        isDownloaded: isDownloaded,
        localApkPath: localApkPath,
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
    int? remoteBuild,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final targetBuild = remoteBuild ?? _extractBuildNumber(downloadUrl);
    if (targetBuild > 0) {
      final existing = await getExistingDownloadedApk(targetBuild);
      if (existing != null) {
        await installLocalApk(existing.path);
        return;
      }
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse(downloadUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Techuboard-Android-App');
      final response = await request.close();

      Uri currentUri = uri;
      HttpClientResponse downloadResponse = response;
      int redirects = 0;
      while ((downloadResponse.statusCode == 301 ||
              downloadResponse.statusCode == 302 ||
              downloadResponse.statusCode == 307 ||
              downloadResponse.statusCode == 308) &&
          redirects < 5) {
        final redirectLocation = downloadResponse.headers.value('location');
        if (redirectLocation == null || redirectLocation.isEmpty) break;
        currentUri = Uri.parse(redirectLocation);
        final redirectRequest = await client.getUrl(currentUri);
        redirectRequest.headers.set('User-Agent', 'Techuboard-Android-App');
        downloadResponse = await redirectRequest.close();
        redirects++;
      }

      if (downloadResponse.statusCode != 200) {
        throw Exception('Download failed with status ${downloadResponse.statusCode}');
      }

      final contentLength = downloadResponse.contentLength;
      final targetFile = await getUpdateApkFile(targetBuild);
      final partFile = File('${targetFile.path}.part');

      if (await partFile.exists()) {
        await partFile.delete();
      }

      final sink = partFile.openWrite();
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

      // Atomic rename once 100% complete so it persists on disk!
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);

      debugPrint('[AppUpdater] APK downloaded to ${targetFile.path}, launching installer...');

      // Launch native Android package installer directly
      await installLocalApk(targetFile.path);
    } finally {
      client.close();
    }
  }

  bool _isVersionGreater(String remote, String current) {
    if (remote.isEmpty) return false;
    // Strip trailing build number like -12396 or -85 so it doesn't inflate the patch version
    final cleanRemote = remote.replaceAll(RegExp(r'-\d+$'), '');
    final cleanCurrent = current.replaceAll(RegExp(r'\+\d+$'), '');

    final rMatch = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(cleanRemote);
    final cMatch = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(cleanCurrent);
    if (rMatch == null || cMatch == null) return false;

    final rMajor = int.tryParse(rMatch.group(1) ?? '0') ?? 0;
    final rMinor = int.tryParse(rMatch.group(2) ?? '0') ?? 0;
    final rPatch = int.tryParse(rMatch.group(3) ?? '0') ?? 0;

    final cMajor = int.tryParse(cMatch.group(1) ?? '0') ?? 0;
    final cMinor = int.tryParse(cMatch.group(2) ?? '0') ?? 0;
    final cPatch = int.tryParse(cMatch.group(3) ?? '0') ?? 0;

    if (rMajor != cMajor) return rMajor > cMajor;
    if (rMinor != cMinor) return rMinor > cMinor;
    return rPatch > cPatch;
  }
}
