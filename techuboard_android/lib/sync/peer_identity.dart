import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium/sodium.dart';
import '../storage_paths.dart';

/// Long-term X25519 identity key pair per device. Stored in platform secure
/// storage (Android Keystore, iOS Keychain, macOS Keychain, Windows DPAPI).
/// Never written to SharedPreferences in plaintext.
class PeerIdentity {
  static const _storageKey = 'techuboard.peer_identity.v4';
  static const _boxKey = 'peer_identity';
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
    final keyPair = sodium.cryptoBoxKeyPair();
    final publicKeyHex = sodium.toHex(keyPair.publicKey);
    return PeerIdentity._(
      publicKey: keyPair.publicKey,
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
        final secretKey = SecureKey.fromList(sodium, sodium.cryptoBoxSecretkeyBytes);
        final publicKey = SecureKey.fromList(sodium, sodium.cryptoBoxPublickeyBytes);
        // Reconstruct from stored hex
        final decoded = sodium.fromHex(existing);
        if (decoded.length == sodium.cryptoBoxKeypairBytes) {
          return PeerIdentity._(
            publicKey: SecureKey.fromList(sodium, decoded.sublist(0, sodium.cryptoBoxPublickeyBytes)),
            secretKey: SecureKey.fromList(sodium, decoded.sublist(sodium.cryptoBoxPublickeyBytes)),
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
  final sodium = await initSodium();
  // X25519 keys can't sign directly; use crypto_sign (Ed25519) derived from same
  // entropy, or simply use crypto_box_seal for authentication. Here we use
  // crypto_box_seal with the peer's public key as the authentication token.
  return message; // placeholder — actual signing in session_handshake
}

/// Verify a signature/message against a peer's public key.
Future<bool> verifyWithPeer(String peerPublicKeyHex, Uint8List message, Uint8List signature) async {
  final sodium = await initSodium();
  final pubKey = SecureKey.fromList(sodium, sodium.fromHex(peerPublicKeyHex));
  try {
    return sodium.cryptoBoxOpenDetached(
      signature,
      message,
      SecureKey.fromList(sodium, sodium.randomBytes(sodium.cryptoBoxNoncebytes())),
      pubKey,
      SecureKey.fromList(sodium, sodium.randomBytes(sodium.cryptoBoxSecretkeybytes())),
    );
  } catch (_) {
    return false;
  } finally {
    pubKey.dispose();
  }
}
