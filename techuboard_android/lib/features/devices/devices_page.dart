import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:common_relay/common_relay.dart' as cr;
import '../../app_localizations.dart';
import '../../notification_manager.dart';
import '../../sync_manager.dart';
import '../../sync/pairing_manager.dart';
import '../../sync/relay_client.dart';
import '../../sync/relay_groups.dart';
import '../../sync/relay_identity.dart';
import '../../ui/app_components.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> with WidgetsBindingObserver {
  bool _busy = false;
  String _busyMessage = '';
  bool _enrolled = false;
  String _groupName = '';
  String _peerDeviceName = '';
  String _selfDeviceId = '';
  List<Map<String, dynamic>> _members = [];
  Timer? _watchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncManager.instance.connectionRevision.addListener(_onStateChanged);
    SyncManager.instance.discoveryProgress.addListener(_onStateChanged);
    _loadStatus();
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SyncManager.instance.connectionRevision.removeListener(_onStateChanged);
    SyncManager.instance.discoveryProgress.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStatus();
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStatus() async {
    try {
      final g = await TechuRelayGroups.load();
      final selfId = g.config['device'] as String? ?? SyncManager.instance.peerId;
      final entry = g.config['group_entry'] as Map<String, dynamic>?;
      final isEnrolled = entry != null || (g.config['token'] as String? ?? '').length >= 32;

      List<Map<String, dynamic>> memberList = [];
      String gName = '';
      String remoteName = '';

      if (entry != null) {
        try {
          final state = cr.RelayGroups.unpack(entry);
          gName = (state['name'] as String?) ?? (state['group'] as String?) ?? '';
          final rawMembers = state['members'] as List<dynamic>? ?? [];
          memberList = rawMembers.map((m) => Map<String, dynamic>.from(m as Map)).toList();

          for (final m in memberList) {
            final devId = m['device'] as String?;
            final name = m['name'] as String? ?? 'Mac';
            if (devId != null && devId != selfId) {
              remoteName = name;
              // Auto-authorize paired peer for clipboard sync
              if (!SyncManager.instance.clipboardSyncPeerIds.contains(devId)) {
                unawaited(SyncManager.instance.setClipboardSyncTarget(devId, enabled: true));
              }
            }
          }
        } catch (_) {}
      }

      // Check active LAN/relay sessions
      if (remoteName.isEmpty) {
        for (final peer in SyncManager.instance.availablePeers) {
          if (peer.peerId != selfId) {
            remoteName = peer.displayName;
            if (!SyncManager.instance.clipboardSyncPeerIds.contains(peer.peerId)) {
              unawaited(SyncManager.instance.setClipboardSyncTarget(peer.peerId, enabled: true));
            }
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _selfDeviceId = selfId;
          _enrolled = isEnrolled;
          _groupName = gName;
          _peerDeviceName = remoteName.isNotEmpty ? remoteName : (isEnrolled ? 'Mac' : '');
          _members = memberList;
        });
      }
    } catch (_) {}
  }

  Future<void> _scanMacQR() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _FullscreenQRScanner(),
      ),
    );

    if (scanned != null && scanned.trim().isNotEmpty && mounted) {
      await _joinWithCode(scanned.trim());
    }
  }

  Future<void> _enterCodeDialog() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _CodeEntrySheet(),
    );

    if (code != null && code.trim().isNotEmpty && mounted) {
      await _joinWithCode(code.trim());
    }
  }

  Future<void> _joinWithCode(String text) async {
    setState(() {
      _busy = true;
      _busyMessage = 'Connecting to Mac...';
    });

    try {
      final manager = SyncManager.instance;
      if (!manager.isEnabled) {
        if (Platform.isAndroid) {
          unawaited(NotificationManager.instance.requestNotificationPermission());
        }
        manager.isEnabled = true;
        await manager.start();
      }

      final raw = text.trim();

      // CASE 1: Universal Techuboard JSON QR payload
      if (raw.startsWith('{') && raw.endsWith('}')) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json['app'] == 'techuboard' || json['v'] == 1 || json.containsKey('id')) {
            final remotePeerId = json['id'] as String? ?? '';
            final remoteName = json['name'] as String? ?? 'Mac';
            final port = json['port'] as int? ?? 5566;
            final ips = (json['ips'] as List?)?.cast<String>() ??
                (json['ip'] != null ? [json['ip'] as String] : <String>[]);
            final relayUrl = json['relay'] as String?;

            if (remotePeerId.isNotEmpty) {
              // 1. Authorize peer locally
              await manager.setSyncTarget(remotePeerId, enabled: true);
              await PairingManager.instance.trustPeer(
                peerId: remotePeerId,
                displayName: remoteName,
                publicKeyHex: json['pk'] as String? ?? '',
              );

              // 2. Dial local IPs
              for (final ip in ips) {
                if (ip.isNotEmpty && ip != '127.0.0.1') {
                  await manager.connectManualPeer(ip, port);
                }
              }

              // 3. Trigger immediate subnet discovery
              manager.triggerCrossBandDiscovery(scanFullSubnet: true);

              // 4. If relay invitation was attached, join relay in background
              if (relayUrl != null && relayUrl.isNotEmpty && relayUrl.startsWith('common-relay://')) {
                unawaited(() async {
                  try {
                    final inv = await TechuRelayGroups.resolveInvitation(relayUrl);
                    final draft = await TechuRelayGroups.draft(inv, manager.peerId);
                    await draft.join(inv, manager.displayName);
                    await TechuRelayGroups.persist(draft);
                  } catch (_) {}
                }());
              }

              await _loadStatus();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$remoteName এর সাথে সফলভাবে কানেক্ট হয়েছে! ক্লিপবোর্ড সিঙ্ক চালু আছে।',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF2E7D32),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
              return;
            }
          }
        } catch (_) {}
      }

      // CASE 2: 6-digit PIN code (e.g. "749 215" or "749215")
      final cleanPin = raw.replaceAll(RegExp(r'\s+'), '');
      if (cleanPin.length == 6 && int.tryParse(cleanPin) != null) {
        setState(() {
          _busyMessage = 'Finding Mac on local Wi-Fi with PIN $cleanPin...';
        });

        manager.triggerCrossBandDiscovery(scanFullSubnet: true);
        await Future<void>.delayed(const Duration(milliseconds: 1000));

        // Connect to any available peers found
        final available = manager.availablePeers;
        if (available.isNotEmpty) {
          for (final peer in available) {
            await manager.setSyncTarget(peer.peerId, enabled: true);
            await manager.connectManualPeer(peer.host, peer.port);
          }
        }

        await _loadStatus();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PIN $cleanPin গ্রহণ করা হয়েছে! লোকাল নেটওয়ার্কে অনুসন্ধান সম্পন্ন।',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // CASE 3: Direct IP address entry (e.g. 192.168.1.10:5566 or 192.168.1.10)
      final ipMatch = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::(\d{1,5}))?$').firstMatch(raw);
      if (ipMatch != null) {
        final ip = ipMatch.group(1)!;
        final port = int.tryParse(ipMatch.group(2) ?? '5566') ?? 5566;
        await manager.connectManualPeer(ip, port);
        manager.triggerCrossBandDiscovery(scanFullSubnet: true);
        await _loadStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$ip:$port এ সরাসরি কানেক্ট করা হয়েছে!'),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // CASE 4: Relay invitation URL (e.g. common-relay://...)
      if (raw.startsWith('common-relay://')) {
        final invitation = await TechuRelayGroups.resolveInvitation(raw);
        final isAuto = invitation['mode'] == 'auto';
        final draft = await TechuRelayGroups.draft(invitation, manager.peerId);
        draft.config['enrollment_invitation'] = invitation;
        draft.config.putIfAbsent('enrollment_name', () => manager.displayName);
        await TechuRelayGroups.savePending(draft);

        if (invitation.containsKey('bootstrap')) {
          await draft.bootstrap(invitation, draft.config['enrollment_name'] as String);
        } else {
          await draft.join(invitation, draft.config['enrollment_name'] as String);
        }
        await TechuRelayGroups.savePending(draft);

        if (isAuto) {
          final pendingDraft = await TechuRelayGroups.pending();
          if (pendingDraft != null && pendingDraft.config.containsKey('pending_join')) {
            await pendingDraft.finishJoin();
            await TechuRelayGroups.savePending(pendingDraft);
          }
        }

        await TechuRelayGroups.persist(draft);
        await manager.updateRelaySettings(
          enabled: true,
          url: draft.config['url'] as String? ?? 'wss://eglish.top/relay/v1/ws',
          deviceId: draft.config['device'] as String? ?? manager.peerId,
          token: '',
          forceRelayRestart: true,
        );
        await TechuRelayGroups.clearPending();
        manager.refreshDiscovery(automatic: false);
        await _loadStatus();
        return;
      }

      throw const FormatException('অকার্যকর কোড। Mac-এর QR কোড স্ক্যান করুন বা সঠিক ৬-ডিজিট পিন দিন।');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('সংযোগ সমস্যা: ${e.toString().replaceAll("Exception:", "").replaceAll("FormatException:", "").trim()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = '';
        });
      }
    }
  }

  Future<void> _showPhoneQRCode() async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PhoneQRDisplaySheet(),
    );
  }

  Future<void> _unpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect from Mac?'),
        content: const Text(
          'Your clipboard will no longer sync automatically with this device. You can reconnect anytime by scanning the QR code again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'Disconnecting...';
    });

    try {
      try {
        await TechuRelayGroups.exitGroup(disband: false);
      } catch (err) {
        debugPrint('[DevicesPage] Remote exitGroup notice failed, proceeding with local unpair: $err');
      }
      await TechuRelayGroups.clearEnrollment();
      await SyncManager.instance.updateRelaySettings(
        enabled: false,
        url: 'wss://eglish.top/relay/v1/ws',
        token: '',
        forceRelayRestart: true,
      );
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device disconnected.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnect failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = _enrolled || SyncManager.instance.hasLanSession || SyncManager.instance.hasRelaySession;

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              // Header title
              Text(
                'Devices & Sync',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Instant clipboard synchronization with your Mac.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              if (isConnected) ...[
                // Connected status card
                _buildConnectedCard(theme),
                const SizedBox(height: 24),
                // Pair another device button
                OutlinedButton.icon(
                  onPressed: _busy ? null : _scanMacQR,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Pair Another Mac / Device'),
                ),
              ] else ...[
                // Not paired card
                _buildNotPairedCard(theme),
              ],
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 18),
                        Text(
                          _busyMessage.isNotEmpty ? _busyMessage : 'Please wait...',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectedCard(ThemeData theme) {
    final devName = _peerDeviceName.isNotEmpty ? _peerDeviceName : 'Mac';

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.laptop_mac_rounded,
                    color: Color(0xFF2E7D32),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        devName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Connected · Live Synced',
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Clipboard is syncing automatically in real-time.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _unpair,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: theme.colorScheme.error,
                backgroundColor: theme.colorScheme.errorContainer.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Disconnect / Unpair'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotPairedCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.devices_rounded,
                    color: theme.colorScheme.primary,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Connect to your Mac',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Point your phone camera at the QR code on your Mac to sync clipboard instantly. No wires, zero setup.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Primary Button: Scan Mac QR Code
                FilledButton.icon(
                  onPressed: _busy ? null : _scanMacQR,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                  label: const Text(
                    'Scan Mac QR Code',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),

                // Secondary Button: Enter 6-Digit Code
                OutlinedButton.icon(
                  onPressed: _busy ? null : _enterCodeDialog,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.pin_rounded, size: 22),
                  label: const Text(
                    'Enter 6-Digit Code',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Tertiary option: Show phone's QR code
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _showPhoneQRCode,
            icon: const Icon(Icons.qr_code_rounded, size: 18),
            label: const Text('Show My Phone QR / Code'),
          ),
        ),
      ],
    );
  }
}

/// Fullscreen high-speed camera scanner with viewfinder frame
class _FullscreenQRScanner extends StatefulWidget {
  const _FullscreenQRScanner();

  @override
  State<_FullscreenQRScanner> createState() => _FullscreenQRScannerState();
}

class _FullscreenQRScannerState extends State<_FullscreenQRScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _detected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        if (raw.startsWith('common-relay://') || raw.startsWith('techuboard://') || raw.contains('#')) {
          _detected = true;
          HapticFeedback.mediumImpact();
          Navigator.pop(context, raw.trim());
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code on Mac'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Viewfinder overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'Point camera at the QR code on your Mac screen',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean bottom sheet to enter 6-digit code or paste pairing text
class _CodeEntrySheet extends StatefulWidget {
  const _CodeEntrySheet();

  @override
  State<_CodeEntrySheet> createState() => _CodeEntrySheetState();
}

class _CodeEntrySheetState extends State<_CodeEntrySheet> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Enter Pairing Code or IP',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Mac স্ক্রিনে দেখানো ৬-ডিজিটের পিন কোড বা Wi-Fi IP দিন:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _textController,
            autofocus: true,
            style: const TextStyle(fontSize: 18, letterSpacing: 1.5, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'e.g. 749 215 or 192.168.1.x',
              hintStyle: TextStyle(
                letterSpacing: 1,
                fontSize: 15,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste_rounded),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _textController.text = data!.text!.trim();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              final val = _textController.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(context, val);
              }
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Connect', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

/// Sheet that displays phone's own QR code and 6-digit PIN
class _PhoneQRDisplaySheet extends StatefulWidget {
  const _PhoneQRDisplaySheet();

  @override
  State<_PhoneQRDisplaySheet> createState() => _PhoneQRDisplaySheetState();
}

class _PhoneQRDisplaySheetState extends State<_PhoneQRDisplaySheet> {
  String? _qrCodeText;
  String _shortPin = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generatePhoneQR();
  }

  Future<void> _generatePhoneQR() async {
    try {
      String? link;
      int pin = 749215;
      try {
        final g = await TechuRelayGroups.load();
        if (!g.config.containsKey('group_entry')) {
          final phoneName = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'Android Phone';
          final draft = await TechuRelayGroups.creationDraft('Techu Phone', phoneName, SyncManager.instance.peerId);
          await draft.create();
          await TechuRelayGroups.persist(draft);
        }

        final active = await TechuRelayGroups.load();
        final invitation = await active.invite(mode: 'auto', compact: true);
        await TechuRelayGroups.persist(active);
        link = TechuRelayGroups.encodeInvitation(invitation);
        final id = invitation['id'] as String? ?? '000000';
        pin = (int.tryParse(id.substring(0, 6.clamp(0, id.length)), radix: 16) ?? 749215) % 900000 + 100000;
      } catch (_) {}

      final ips = await SyncManager.instance.enumerateLocalIPv4s();
      final primaryIP = ips.isNotEmpty ? ips.first : '127.0.0.1';
      final cleanPin = '$pin';

      final payload = {
        'app': 'techuboard',
        'v': 1,
        'id': SyncManager.instance.peerId,
        'name': SyncManager.instance.displayName,
        'ips': ips,
        'ip': primaryIP,
        'port': SyncManager.instance.port,
        'pin': cleanPin,
        'relay': link ?? '',
      };

      if (mounted) {
        setState(() {
          _qrCodeText = jsonEncode(payload);
          _shortPin = '${cleanPin.substring(0, 3)} ${cleanPin.substring(3)}';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Phone Pairing Code',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Scan this QR code from your Mac or enter the code.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_qrCodeText != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrCodeText!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            if (_shortPin.isNotEmpty) ...[
              Text(
                'PIN: $_shortPin',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _qrCodeText!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pairing link copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Pairing Link'),
            ),
          ] else ...[
            const Text('Could not generate pairing code. Please try again.'),
          ],
        ],
      ),
    );
  }
}
