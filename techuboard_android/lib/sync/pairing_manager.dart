import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'peer_identity.dart';

/// Manages WhatsApp-style device pairing (QR code generation, scanning,
/// PSK exchange, and TOFU public key pinning).
class PairingManager {
  static final PairingManager instance = PairingManager._();
  PairingManager._();

  static const _storage = FlutterSecureStorage();
  static const _trustedPeersKey = 'techuboard.trusted_peers.v4';

  /// Generate pairing payload for displaying as a QR code on the primary device.
  Future<Map<String, dynamic>> generatePairingPayload({
    required String peerId,
    required String displayName,
    required String host,
    required int port,
    required PeerIdentity identity,
  }) async {
    final rng = Random.secure();
    final pskBytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final pskHex = pskBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

    // Store temporary PSK for incoming pairing verification
    const prefsStorage = const FlutterSecureStorage();
    await prefsStorage.write(key: 'temp_pairing_psk', value: pskHex);

    return {
      'v': 1,
      'id': peerId,
      'name': displayName,
      'ip': host,
      'port': port,
      'pk': identity.publicKeyHex,
      'psk': pskHex,
    };
  }

  /// Parse and validate scanned QR pairing payload on companion device.
  Map<String, dynamic>? parsePairingQr(String qrData) {
    try {
      final map = jsonDecode(qrData) as Map<String, dynamic>;
      if (map['v'] != 1 ||
          map['id'] is! String ||
          map['ip'] is! String ||
          map['port'] is! int ||
          map['pk'] is! String ||
          map['psk'] is! String) {
        return null;
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  /// Permanently trust and pin a paired peer's public key (TOFU).
  Future<void> trustPeer({
    required String peerId,
    required String displayName,
    required String publicKeyHex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trustedPeersKey);
    final map = raw != null ? Map<String, dynamic>.from(jsonDecode(raw)) : <String, dynamic>{};

    map[peerId] = {
      'name': displayName,
      'pk': publicKeyHex,
      'paired_at': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_trustedPeersKey, jsonEncode(map));

    // Also add to authorized clipboard/notification sync lists
    final clipboardAuth = prefs.getStringList('clipboardSyncPeerIds') ?? [];
    if (!clipboardAuth.contains(peerId)) {
      clipboardAuth.add(peerId);
      await prefs.setStringList('clipboardSyncPeerIds', clipboardAuth);
    }
    final notifAuth = prefs.getStringList('notificationSyncPeerIds') ?? [];
    if (!notifAuth.contains(peerId)) {
      notifAuth.add(peerId);
      await prefs.setStringList('notificationSyncPeerIds', notifAuth);
    }
  }

  /// Check if a peer is trusted via pinned public key.
  Future<bool> isPeerTrusted(String peerId, String publicKeyHex) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trustedPeersKey);
    if (raw == null) return false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[peerId] as Map<String, dynamic>?;
      if (entry == null) return false;
      return entry['pk'] == publicKeyHex;
    } catch (_) {
      return false;
    }
  }
}
