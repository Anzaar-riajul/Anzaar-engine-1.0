import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FloatingHubControl {
  static final FloatingHubControl instance = FloatingHubControl._();
  FloatingHubControl._();

  static const _permissionsChannel =
      MethodChannel('com.techuboard.app/permissions');

  final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);

  Future<void> refreshStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final running =
          await _permissionsChannel.invokeMethod<bool>('isFloatingHubRunning') ??
              false;
      isRunning.value = running;
    } catch (_) {}
  }

  Future<void> toggle(BuildContext context) async {
    if (!Platform.isAndroid) return;
    try {
      final current = isRunning.value;
      if (!current) {
        final canDraw =
            await _permissionsChannel.invokeMethod<bool>('canDrawOverlays') ??
                false;
        if (!canDraw) {
          await _permissionsChannel.invokeMethod<void>(
            'requestOverlayPermission',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please grant "Display over other apps" permission to enable Floating Hub',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        await _permissionsChannel.invokeMethod<void>('startFloatingHub');
        isRunning.value = true;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Floating Paste Hub turned ON'),
                ],
              ),
              backgroundColor: Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        await _permissionsChannel.invokeMethod<void>('stopFloatingHub');
        isRunning.value = false;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Floating Paste Hub turned OFF'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to toggle Floating Hub: $e');
    }
    await refreshStatus();
  }
}
