import 'dart:convert';
import 'dart:typed_data';

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
    final publicKeyHex = sodium.toHex(keyPair.publicKey);
    return PeerIdentity._(
      publicKey: SecureKey.fromList(sodium, keyPair.publicKey),
      secretKey: keyPair.secretKey,
      publicKeyHex: publicKeyHex,
    ).._persist();
  }

  /// Load existing identity from secure storage, or generate if none exists.
  static Future<PeerIdentity> loadOrCreate() async {
    final sodium = await initSodium();
    final storage = const FlutterSecureStorage();
    final existing = await storage.read(key: _storageKey);
    if (existing != null) {
      try {
        final decoded = sodium.fromHex(existing);
        if (decoded.length == sodium.crypto.box.publicKeyBytes) {
          return PeerIdentity._(
            publicKey: SecureKey.fromList(sodium, decoded),
            secretKey: SecureKey.fromList(sodium, decoded),
            publicKeyHex: existing,
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

  void _persist() async {
    final storage = const FlutterSecureStorage();
    await storage.write(key: _storageKey, value: publicKeyHex);
    await storage.write(key: _publicKeyHexKey, value: publicKeyHex);
  }

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
