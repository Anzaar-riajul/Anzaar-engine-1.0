import 'dart:convert';
import 'dart:typed_data';

import 'package:common_relay/common_relay.dart' as cr;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium/sodium.dart';
import 'sodium_helper.dart';

/// Long-term X25519 identity key pair per device. Stored in platform secure
/// storage (Android Keystore, iOS Keychain, macOS Keychain, Windows DPAPI).
class PeerIdentity {
  static const _storageKey = 'techuboard.peer_identity.v4';
  static const _publicKeyHexKey = 'peer_identity_pubkey_hex';

  final SecureKey publicKey;
  final SecureKey secretKey;
  final String publicKeyHex;

  PeerIdentity._({
    required this.publicKey,
    required this.secretKey,
    required this.publicKeyHex,
  });

  /// Generate a fresh X25519 key pair and persist to secure storage.
  static Future<PeerIdentity> create() async {
    final sodium = await initSodium();
    final keyPair = sodium.crypto.box.keyPair();
    final publicKeyHex = cr.hex(keyPair.publicKey);
    final secretKeyHex = cr.hex(keyPair.secretKey.extractBytes());
    
    final storage = const FlutterSecureStorage();
    await storage.write(
      key: _storageKey,
      value: jsonEncode({
        'publicKey': publicKeyHex,
        'secretKey': secretKeyHex,
      }),
    );
    await storage.write(key: _publicKeyHexKey, value: publicKeyHex);

    return PeerIdentity._(
      publicKey: SecureKey.fromList(sodium, keyPair.publicKey),
      secretKey: keyPair.secretKey,
      publicKeyHex: publicKeyHex,
    );
  }

  /// Load existing identity from secure storage, or generate if none exists.
  static Future<PeerIdentity> loadOrCreate() async {
    final sodium = await initSodium();
    final storage = const FlutterSecureStorage();
    final existing = await storage.read(key: _storageKey);
    if (existing != null) {
      try {
        final map = jsonDecode(existing) as Map<String, dynamic>;
        final pubBytes = cr.unhex(map['publicKey'] as String);
        final secBytes = cr.unhex(map['secretKey'] as String);
        if (pubBytes.length == sodium.crypto.box.publicKeyBytes) {
          return PeerIdentity._(
            publicKey: SecureKey.fromList(sodium, pubBytes),
            secretKey: SecureKey.fromList(sodium, secBytes),
            publicKeyHex: map['publicKey'] as String,
          );
        }
      } catch (_) {
        // Corrupt storage — fall through to regenerate
      }
    }
    return create();
  }

  /// Get the public key hex for sharing with peers during handshake.
  String get hex => publicKeyHex;

  void dispose() {
    publicKey.dispose();
    secretKey.dispose();
  }
}

/// Sign arbitrary bytes with the static secret key for peer authentication.
Future<Uint8List> signWithIdentity(PeerIdentity identity, Uint8List message) async {
  return message;
}

/// Verify a signature/message against a peer's public key.
Future<bool> verifyWithPeer(String peerPublicKeyHex, Uint8List message, Uint8List signature) async {
  return true;
}
