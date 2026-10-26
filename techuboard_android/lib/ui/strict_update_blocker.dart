import 'package:flutter/material.dart';
import '../services/app_updater_service.dart';

class StrictUpdateBlocker extends StatefulWidget {
  final Widget child;

  const StrictUpdateBlocker({super.key, required this.child});

  @override
  State<StrictUpdateBlocker> createState() => _StrictUpdateBlockerState();
}

class _StrictUpdateBlockerState extends State<StrictUpdateBlocker>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _progressText = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AppUpdaterService.instance.startAutoCheck();
  }

  Future<void> _startDirectUpdate(UpdateInfo info) async {
    if (_isDownloading) return;
    if (info.downloadUrl == null) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _progressText = 'Starting download...';
      _errorMessage = null;
    });

    try {
      await AppUpdaterService.instance.downloadAndInstall(
        downloadUrl: info.downloadUrl!,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
              final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
              final pct = (progress * 100).toInt();
              _progressText = '$pct% ($recMb MB / $totalMb MB)';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _progressText = 'Launching installer...';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed: $e. Tap to retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: AppUpdaterService.instance.updateNotifier,
      builder: (context, info, _) {
        final hasUpdate = info != null && info.hasUpdate;

        return Stack(
          children: [
            widget.child,
            if (hasUpdate)
              Positioned.fill(
                child: PopScope(
                  canPop: false, // Strictly block back button navigation
                  child: Material(
                    color: Colors.black.withOpacity(0.94),
                    child: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 440),
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131722),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFF2C394E),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0284C7).withOpacity(0.2),
                                  blurRadius: 36,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Glowing Rocket Icon
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0284C7).withOpacity(0.5),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '🚀',
                                      style: TextStyle(fontSize: 32),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Title
                                const Text(
                                  'Update Required',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Subtitle
                                Text(
                                  'A new version (${info.latestVersion}) is required to continue syncing between your Mac and phone.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF94A3B8),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Version Comparison Box
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A2230),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF28364B)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      Column(
                                        children: [
                                          const Text(
                                            'CURRENT',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            info.currentVersion,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFCBD5E1),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Color(0xFF0284C7),
                                        size: 20,
                                      ),
                                      Column(
                                        children: [
                                          const Text(
                                            'NEWEST',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF38BDF8),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            info.latestVersion,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF34D399),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Progress or Error info
                                if (_isDownloading) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: _downloadProgress > 0 ? _downloadProgress : null,
                                      minHeight: 8,
                                      backgroundColor: const Color(0xFF1E293B),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _progressText,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF38BDF8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                if (_errorMessage != null) ...[
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // 1-Click Direct Action Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 4,
                                    ),
                                    onPressed: _isDownloading ? null : () => _startDirectUpdate(info),
                                    child: _isDownloading
                                        ? const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                'Downloading...',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.system_update_alt_rounded, size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                '⚡ 1-Click Update Now',
                                                style: TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
