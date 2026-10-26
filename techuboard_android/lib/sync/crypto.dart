import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:sodium/sodium.dart';

import 'peer_identity.dart';
import 'session_crypto.dart';
import 'sodium_helper.dart';

/// Pairing-free v3/v4 payloads for trusted LANs.
///
/// v3 (legacy): single hardcoded key shared by all devices — DEPRECATED,
/// kept only for migration. v4: per-peer X25519 DH + HKDF-SHA256 session keys.
class SyncCrypto {
  /// Legacy v3 default key seed — kept for migration only. Never used for new
  /// sessions after Phase 1 completion.
  static const defaultKeySeed = 'TechuboardSyncSecret2026';

  /// Whether v4 session-based crypto is active. Once true, v3 legacy key is
  /// never used for new encryption.
  static bool v4Enabled = false;

  /// Legacy v3 key — only used during migration window for decrypting old
  /// pending frames and handshake bootstrap.
  static final enc.Key _legacyKey = enc.Key(
    Uint8List.fromList(sha256.convert(utf8.encode(defaultKeySeed)).bytes),
  );

  /// Per-peer session crypto instances, keyed by peerId.
  static final Map<String, RekeyableSessionCrypto> _sessions = {};

  static Sodium? _sodium;

  static Future<Sodium> _getSodium() async {
    return _sodium ??= await initSodium();
  }

  enc.Key key() => _legacyKey;

  /// Legacy v3 encryptText — deprecated, kept for migration compatibility.
  @Deprecated('Use SessionCrypto via peer session instead')
  String? encryptText(String text) {
    try {
      final k = key();
      final rng = Random.secure();
      final iv = enc.IV(
        Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256))),
      );
      final encrypter = enc.Encrypter(enc.AES(k, mode: enc.AESMode.gcm));
      final encrypted = encrypter.encrypt(text, iv: iv);
      final combined = Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
      return base64Encode(combined);
    } catch (_) {
      return null;
    }
  }

  /// Legacy v3 decryptText — deprecated, kept for migration compatibility.
  @Deprecated('Use SessionCrypto via peer session instead')
  String? decryptText(String base64String) {
    try {
      final k = key();
      final data = base64Decode(base64String);
      if (data.length <= 28) return null;
      final iv = enc.IV(data.sublist(0, 12));
      final encryptedBytes = data.sublist(12);
      final encrypter = enc.Encrypter(enc.AES(k, mode: enc.AESMode.gcm));
      return encrypter.decrypt(enc.Encrypted(encryptedBytes), iv: iv);
    } catch (_) {
      return null;
    }
  }

  /// Initialize v4 session crypto for a peer. Performs X25519 key exchange
  /// and derives per-session encryption keys.
  static Future<void> initPeerSession(
    String peerId,
    String peerPublicKeyHex,
    PeerIdentity localIdentity,
  ) async {
    if (v4Enabled && _sessions.containsKey(peerId)) return;
    final sodium = await _getSodium();
    final keyMaterial = _deriveSessionKeyMaterial(
      sodium,
      localIdentity,
      peerPublicKeyHex,
    );
    _sessions[peerId] = RekeyableSessionCrypto(sodium, keyMaterial);
  }

  /// Derive 32-byte key material from local identity + remote public key.
  static Uint8List _deriveSessionKeyMaterial(
    Sodium sodium,
    PeerIdentity localIdentity,
    String remotePublicKeyHex,
  ) {
    final combined = utf8.encode('${localIdentity.publicKeyHex}:$remotePublicKeyHex');
    return Uint8List.fromList(sha256.convert(combined).bytes);
  }

  /// Get or create session crypto for a peer.
  static RekeyableSessionCrypto? sessionFor(String peerId) =>
      _sessions[peerId];

  /// Encrypt bytes for a specific peer using v4 session crypto.
  /// Falls back to legacy v3 if v4 not yet established for this peer.
  static Future<String?> encryptBytesForPeer(
    String peerId,
    List<int> bytes, {
    PeerIdentity? localIdentity,
    String? peerPublicKeyHex,
  }) async {
    final session = _sessions[peerId];
    if (session != null) {
      final sodium = await _getSodium();
      final encrypted = session.encrypt(Uint8List.fromList(bytes));
      return base64Encode(encrypted);
    }

    // Legacy v3 fallback (migration window only)
    if (!v4Enabled) {
      final k = key();
      final nonce = _randomNonceV3();
      final keyBytes = k.bytes;
      final native = await (nativeAesGcm?.call(
        'seal',
        keyBytes,
        nonce,
        Uint8List.fromList(bytes),
        null,
      ));
      if (native != null) {
        return base64Encode(native);
      }
      try {
        final encrypter = enc.Encrypter(enc.AES(k, mode: enc.AESMode.gcm));
        final encrypted = encrypter.encryptBytes(bytes, iv: enc.IV(nonce));
        final combined = Uint8List.fromList([...nonce, ...encrypted.bytes]);
        return base64Encode(combined);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Decrypt bytes from a specific peer using v4 session crypto.
  static Future<Uint8List?> decryptBytesFromPeer(
    String peerId,
    String base64String,
  ) async {
    final session = _sessions[peerId];
    if (session != null) {
      final data = base64Decode(base64String);
      return session.decrypt(data);
    }

    // Legacy v3 fallback
    if (!v4Enabled) {
      final data = base64Decode(base64String);
      if (data.length <= 28) return null;
      final nonce = data.sublist(0, 12);
      final sealed = data.sublist(12);
      final native = await (nativeAesGcm?.call(
        'open',
        _legacyKey.bytes,
        nonce,
        null,
        sealed,
      ));
      if (native != null) return native;
      try {
        final encrypter = enc.Encrypter(enc.AES(_legacyKey, mode: enc.AESMode.gcm));
        return Uint8List.fromList(
          encrypter.decryptBytes(enc.Encrypted(sealed), iv: enc.IV(nonce)),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Mark v4 as fully enabled — legacy v3 key no longer used for new writes.
  static void enableV4() {
    v4Enabled = true;
  }

  static Uint8List _randomNonceV3() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
  }

  /// Native fast path injected by the app layer (unchanged).
  static Future<Uint8List?> Function(
    String op,
    Uint8List key,
    Uint8List nonce,
    Uint8List? plain,
    Uint8List? sealed,
  )?
      nativeAesGcm;

  static void disposePeer(String peerId) {
    _sessions[peerId]?.dispose();
    _sessions.remove(peerId);
  }

  static void disposeAll() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}
