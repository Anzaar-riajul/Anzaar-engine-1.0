import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../clipboard_manager.dart';
import '../../app_localizations.dart';
import '../../ui/app_components.dart';
import '../../ui/app_theme.dart';
import '../../services/app_updater_service.dart';
import '../../services/floating_hub_control.dart';
import '../devices/devices_page.dart';
import '../devices/device_widgets.dart';

class MobileSettingsContent extends StatefulWidget {
  final VoidCallback onOpenLogs;
  final VoidCallback onOpenReceivedFiles;
  const MobileSettingsContent({
    super.key,
    required this.onOpenLogs,
    required this.onOpenReceivedFiles,
  });
  @override
  State<MobileSettingsContent> createState() => _MobileSettingsContentState();
}

class _MobileSettingsContentState extends State<MobileSettingsContent>
    with WidgetsBindingObserver {
  static const _widgetChannel = MethodChannel(
    'com.techuboard.app/widget',
  );
  static const _permissionsChannel = MethodChannel(
    'com.techuboard.app/permissions',
  );
  late final Future<String> _version = _readVersion();

  Future<String> _readVersion() async {
    try {
      final info = await const MethodChannel(
        'com.techuboard.app/storage',
      ).invokeMapMethod<String, String>('getAppVersion');
      final version = info?['version']?.trim() ?? '';
      final build = info?['build']?.trim() ?? '';
      if (version.isEmpty) return '—';
      return build.isEmpty ? 'v$version' : 'v$version ($build)';
    } catch (_) {
      return '—';
    }
  }

  bool _timerWidgetPinned = false;
  bool _isCheckingUpdate = false;
  bool _isInlineDownloading = false;
  double _inlineDownloadProgress = 0.0;
  String? _inlineDownloadError;

  Future<void> _handleInlineUpdate(UpdateInfo info) async {
    if (_isInlineDownloading || info.downloadUrl == null) return;
    setState(() {
      _isInlineDownloading = true;
      _inlineDownloadProgress = 0.0;
      _inlineDownloadError = null;
    });
    try {
      await AppUpdaterService.instance.downloadAndInstall(
        downloadUrl: info.downloadUrl!,
        onProgress: (p, received, total) {
          if (mounted) setState(() => _inlineDownloadProgress = p);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInlineDownloading = false;
          _inlineDownloadError = 'Update failed: $e';
        });
      }
    }
  }

  Future<void> _handleCheckUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    try {
      final info = await AppUpdaterService.instance.checkForUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        _showUpdateDialog(info, isForced: false);
      } else if (info.downloadUrl != null) {
        _showUpdateDialog(info, isForced: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are using the latest version of Techuboard.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check updates: $e')),
      );
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(UpdateInfo info, {bool isForced = false}) {
    double progress = 0.0;
    bool isDownloading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    isForced ? Icons.check_circle_outline_rounded : Icons.system_update_rounded,
                    color: isForced ? Colors.green : Colors.blueAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isForced ? 'Techuboard is Up to Date' : 'Update Available: ${info.latestVersion}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isForced
                        ? 'Current Version: ${info.currentVersion}\nLatest on GitHub: ${info.latestVersion}\n\nYou can reinstall the latest release APK if needed.'
                        : 'A newer version of Techuboard (${info.latestVersion}) is ready to install.',
                  ),
                  if (info.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Text(info.releaseNotes, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                  if (isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress > 0 ? progress : null),
                    const SizedBox(height: 6),
                    Text(
                      'Downloading: ${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
              actions: [
                if (!isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text(isForced ? 'Close' : 'Later'),
                  ),
                FilledButton.icon(
                  icon: isDownloading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    isDownloading
                        ? 'Downloading...'
                        : (isForced ? 'Reinstall Latest APK' : 'Update Now'),
                  ),
                  onPressed: isDownloading || info.downloadUrl == null
                      ? null
                      : () async {
                          setDialogState(() => isDownloading = true);
                          try {
                            await AppUpdaterService.instance.downloadAndInstall(
                              downloadUrl: info.downloadUrl!,
                              onProgress: (p, received, total) {
                                setDialogState(() => progress = p);
                              },
                            );
                            if (mounted) Navigator.pop(dialogCtx);
                          } catch (e) {
                            setDialogState(() => isDownloading = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Update download failed: $e')),
                              );
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }
  bool _pinning = false;
  bool _floatingHubEnabled = false;
  bool _hasOverlayPermission = false;
  bool _hasAccessibilityPermission = false;
  bool _autoImageSync = true;
  late final TextEditingController _excludedAppsController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _excludedAppsController = TextEditingController(
      text: ClipboardManager.instance.excludedApps.join('\n'),
    );
    if (Platform.isAndroid) {
      _refreshPinned();
      _refreshFloatingHubStatus();
      AppUpdaterService.instance.checkForUpdate();
    }
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _autoImageSync = prefs.getBool('autoImageSync') ?? true;
        });
      }
    });
  }

  Future<void> _toggleAutoImageSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoImageSync', value);
    if (mounted) setState(() => _autoImageSync = value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _excludedAppsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid && state == AppLifecycleState.resumed) {
      _refreshPinned();
      _refreshFloatingHubStatus();
    }
  }

  Future<void> _refreshFloatingHubStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final running =
          await _permissionsChannel.invokeMethod<bool>('isFloatingHubRunning') ??
              false;
      FloatingHubControl.instance.isRunning.value = running;
      final overlay =
          await _permissionsChannel.invokeMethod<bool>('canDrawOverlays') ??
              false;
      final access =
          await _permissionsChannel.invokeMethod<bool>(
                  'isAccessibilityGranted') ??
              false;
      if (mounted) {
        setState(() {
          _floatingHubEnabled = running;
          _hasOverlayPermission = overlay;
          _hasAccessibilityPermission = access;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFloatingHub(bool enable) async {
    if (!Platform.isAndroid) return;
    if (enable) {
      final canDraw =
          await _permissionsChannel.invokeMethod<bool>('canDrawOverlays') ??
              false;
      if (!canDraw) {
        await _permissionsChannel.invokeMethod<void>(
          'requestOverlayPermission',
        );
        if (mounted) {
          showTechuMessage(
            context,
            'Please grant "Display over other apps" permission',
          );
        }
        return;
      }
      await _permissionsChannel.invokeMethod<void>('startFloatingHub');
    } else {
      await _permissionsChannel.invokeMethod<void>('stopFloatingHub');
    }
    await _refreshFloatingHubStatus();
  }

  Future<void> _refreshPinned() async {
    try {
      final pinned =
          await _widgetChannel.invokeMethod<bool>('isTimerWidgetPinned') ??
          false;
      if (mounted) setState(() => _timerWidgetPinned = pinned);
    } catch (_) {
      /* Not every platform supports launcher widgets. */
    }
  }

  Future<void> _pin() async {
    if (_pinning) return;
    setState(() => _pinning = true);
    try {
      final ok =
          await _widgetChannel.invokeMethod<bool>('requestPinTimerWidget') ??
          false;
      if (!mounted) return;
      showTechuMessage(
        context,
        ok
            ? context.l10n.timerWidgetPinRequested
            : context.l10n.timerWidgetPinFailed,
      );
      if (ok) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) await _refreshPinned();
      }
    } catch (_) {
      if (mounted) showTechuMessage(context, context.l10n.timerWidgetPinFailed);
    } finally {
      if (mounted) setState(() => _pinning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TechuSection(
            title: l10n.personalize,
            child: Column(
              children: [
                ListTile(
                  leading: const TechuIcon(Icons.palette_outlined),
                  title: Text(l10n.appearance),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(l10n.systemTheme),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(l10n.lightTheme),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(l10n.darkTheme),
                        ),
                      ],
                      selected: {AppAppearance.instance.mode},
                      onSelectionChanged: (value) async {
                        await AppAppearance.instance.setMode(value.first);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
                const Divider(indent: 20, endIndent: 20),
                ListTile(
                  leading: const TechuIcon(Icons.language_rounded),
                  title: Text(l10n.languageLabel),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<AppLanguage>(
                      value: AppLanguageController.instance.language,
                      onChanged: (language) async {
                        if (language == null) return;
                        await AppLanguageController.instance.setLanguage(
                          language,
                        );
                        if (mounted) setState(() {});
                      },
                      items: AppLanguage.values
                          .map(
                            (language) => DropdownMenuItem(
                              value: language,
                              child: Text(language.displayName),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (Platform.isWindows)
            TechuSection(
              title: l10n.windowsExcludedApps,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _excludedAppsController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: l10n.windowsExcludedApps,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final names = _excludedAppsController.text
                            .split('\n')
                            .map((name) => name.trim())
                            .where((name) => name.isNotEmpty)
                            .toSet()
                            .toList();
                        await ClipboardManager.instance.updateExcludedApps(
                          names,
                        );
                        if (context.mounted) {
                          showTechuMessage(context, l10n.settingsSaved);
                        }
                      },
                      child: Text(l10n.saveExcludedApps),
                    ),
                  ],
                ),
              ),
            ),
          if (Platform.isAndroid)
            TechuSection(
              title: l10n.homeWidgetSection,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const TechuIcon(Icons.timer_outlined),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.timerWidgetTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.timerWidgetDesc,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.tonalIcon(
                      onPressed: _timerWidgetPinned || _pinning ? null : _pin,
                      icon: Icon(
                        _timerWidgetPinned
                            ? Icons.check_circle_outline
                            : Icons.add_rounded,
                      ),
                      label: Text(
                        _timerWidgetPinned
                            ? l10n.timerWidgetAdded
                            : l10n.addToHomeScreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (Platform.isAndroid)
            TechuSection(
              title: 'Floating Paste Hub',
              child: Column(
                children: [
                  SwitchListTile(
                    secondary:
                        const TechuIcon(Icons.dashboard_customize_rounded),
                    title: const Text('Floating Paste Pill'),
                    subtitle: Text(
                      _hasOverlayPermission
                          ? 'Floating capsule on top of any app (Overlay permission active)'
                          : 'Floating capsule on top of any app for 1-tap pasting',
                    ),
                    value: _floatingHubEnabled,
                    onChanged: (val) => _toggleFloatingHub(val),
                  ),
                  ListTile(
                    leading: const TechuIcon(Icons.accessibility_new_rounded),
                    title: const Text('1-Tap Direct Paste'),
                    subtitle: Text(
                      _hasAccessibilityPermission
                          ? 'Accessibility active (Auto direct-paste ready)'
                          : 'Tap to enable Accessibility for direct field paste',
                    ),
                    trailing: Icon(
                      _hasAccessibilityPermission
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_ios_rounded,
                      color: _hasAccessibilityPermission
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    onTap: () async {
                      await _permissionsChannel.invokeMethod<void>(
                        'openAccessibilitySettings',
                      );
                    },
                  ),
                ],
              ),
            ),
          TechuSection(
            title: 'Image & File Sync',
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const TechuIcon(Icons.image_outlined),
                  title: const Text('Auto Image & File Sync'),
                  subtitle: Text(
                    _autoImageSync
                        ? 'Automatically syncs copied images & files across all connected devices'
                        : 'Manual only (Use "Send to Device" to share images)',
                  ),
                  value: _autoImageSync,
                  onChanged: (val) => _toggleAutoImageSync(val),
                ),
              ],
            ),
          ),
          TechuSection(
            title: l10n.toolsAndSupport,
            child: Column(
              children: [
                ListTile(
                  leading: const TechuIcon(Icons.tune_rounded),
                  title: Text(l10n.connectionSettings),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const ConnectionEditor(),
                  ),
                ),
                const Divider(indent: 76, endIndent: 20),
                ListTile(
                  leading: const TechuIcon(Icons.folder_open_rounded),
                  title: Text(l10n.receivedFiles),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenReceivedFiles,
                ),
                const Divider(indent: 76, endIndent: 20),
                ListTile(
                  leading: const TechuIcon(Icons.article_outlined),
                  title: Text(l10n.viewLogs),
                  subtitle: Text(l10n.appRuntimeLogs),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenLogs,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text('Techuboard', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  l10n.aboutTechuboard,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FutureBuilder<String>(
                  future: _version,
                  builder: (context, snapshot) => Text(
                    '${l10n.appVersionLabel} ${snapshot.data ?? '—'}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ValueListenableBuilder<UpdateInfo?>(
                  valueListenable: AppUpdaterService.instance.updateNotifier,
                  builder: (context, updateInfo, _) {
                    final hasUpdate = updateInfo != null && updateInfo.hasUpdate;
                    if (hasUpdate) {
                      return Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF3B30),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'নতুন সংস্করণ উপলব্ধ: ${updateInfo.latestVersion}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3B30).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'UPDATE',
                                    style: TextStyle(
                                      color: Color(0xFFFF3B30),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (updateInfo.releaseNotes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                updateInfo.releaseNotes,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (_isInlineDownloading) ...[
                              const SizedBox(height: 12),
                              LinearProgressIndicator(value: _inlineDownloadProgress > 0 ? _inlineDownloadProgress : null),
                              const SizedBox(height: 6),
                              Text(
                                'ডাউনলোড হচ্ছে: ${(_inlineDownloadProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                            if (_inlineDownloadError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _inlineDownloadError!,
                                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _isInlineDownloading ? null : () => _handleInlineUpdate(updateInfo),
                              icon: _isInlineDownloading
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.download, size: 18),
                              label: Text(_isInlineDownloading ? 'ডাউনলোড হচ্ছে...' : 'এখনই সরাসরি আপডেট করুন'),
                            ),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: _isCheckingUpdate ? null : _handleCheckUpdate,
                        icon: _isCheckingUpdate
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync, size: 18),
                        label: Text(_isCheckingUpdate ? 'যাচাই করা হচ্ছে...' : 'আপডেট চেক করুন (Check for Updates)'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
