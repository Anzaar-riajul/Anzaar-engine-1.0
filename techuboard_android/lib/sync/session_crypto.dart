import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sodium/sodium.dart';

/// Per-session symmetric encryption using XChaCha20-Poly1305 (crypto_secretbox).
/// Keys are derived from the handshake and exist only in memory — never written
/// to disk. Rekeyed periodically for forward secrecy.
class SessionCrypto {
  static const _keyBytes = 32;
  static const _nonceBytes = 24;
  static const _macBytes = 16;

  final Sodium _sodium;
  final SecureKey _key;
  int _nonceCounter = 0;

  /// Rekey threshold: 1 GB of encrypted data.
  static const _rekeyAfterBytes = 1024 * 1024 * 1024;
  int _bytesEncrypted = 0;

  SessionCrypto._(this._sodium, this._key);

  /// Create from raw 32-byte key material.
  factory SessionCrypto.fromKey(Sodium sodium, Uint8List keyMaterial) {
    if (keyMaterial.length != _keyBytes) {
      throw ArgumentError('Session key must be $_keyBytes bytes');
    }
    return SessionCrypto._(
      sodium,
      SecureKey.fromList(sodium, keyMaterial),
    );
  }

  /// Encrypt plaintext with a unique nonce derived from a counter.
  Uint8List encrypt(Uint8List plaintext) {
    final nonce = _nextNonce();
    final sealed = _sodium.crypto.secretBox.easy(
      message: plaintext,
      nonce: nonce,
      key: _key,
    );
    final combined = Uint8List(_nonceBytes + sealed.length);
    combined.setRange(0, _nonceBytes, nonce);
    combined.setRange(_nonceBytes, combined.length, sealed);
    _bytesEncrypted += plaintext.length;
    return combined;
  }

  /// Decrypt `nonce || ciphertext || mac`. Returns plaintext or null on failure.
  Uint8List? decrypt(Uint8List sealed) {
    if (sealed.length < _nonceBytes + _macBytes) return null;
    final nonce = sealed.sublist(0, _nonceBytes);
    final ciphertext = sealed.sublist(_nonceBytes);
    try {
      return _sodium.crypto.secretBox.openEasy(
        cipherText: ciphertext,
        nonce: nonce,
        key: _key,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether this session should rekey based on bytes encrypted.
  bool get shouldRekey => _bytesEncrypted >= _rekeyAfterBytes;

  /// The nonce for the next message (24 bytes, counter-based).
  Uint8List _nextNonce() {
    final nonce = Uint8List(_nonceBytes);
    final bytes = _nonceCounter.toRadixString(16).padLeft(16, '0');
    for (var i = 0; i < 8; i++) {
      nonce[i] = int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16);
    }
    _nonceCounter++;
    return nonce;
  }

  void dispose() {
    _key.dispose();
  }
}

/// Wraps SessionCrypto with automatic rekey support.
class RekeyableSessionCrypto {
  final Sodium _sodium;
  SessionCrypto _crypto;
  final Uint8List _baseKeyMaterial;

  RekeyableSessionCrypto(this._sodium, this._baseKeyMaterial)
      : _crypto = SessionCrypto.fromKey(_sodium, _baseKeyMaterial);

  Uint8List encrypt(Uint8List plaintext) {
    if (_crypto.shouldRekey) {
      final newKey = Uint8List.fromList(
        sha256.convert([..._baseKeyMaterial, ...utf8.encode('rekey')]).bytes,
      );
      _crypto.dispose();
      _crypto = SessionCrypto.fromKey(_sodium, newKey);
    }
    return _crypto.encrypt(plaintext);
  }

  Uint8List? decrypt(Uint8List sealed) => _crypto.decrypt(sealed);

  bool get shouldRekey => _crypto.shouldRekey;

  void dispose() {
    _crypto.dispose();
  }
}
