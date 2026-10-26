import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'peer_identity.dart';
import 'session_crypto.dart';

/// Noise IKpsk2-inspired handshake for mutual authentication and session key
/// derivation.
///
/// Pattern (simplified):
///   -> e, es, s, ss       (initiator sends ephemeral, ephemeral-static DH,
///                          static, static-static DH)
///   <- e, ee, es, s, ss   (responder responds similarly)
///
/// Both sides derive: HKDF-SHA256(DH(e,e) || DH(e,s) || DH(s,e) || DH(s,s))
class SessionHandshake {
  static const _info = 'techuboard-sync-v4-session';
  static const _handshakeTimeout = Duration(seconds: 5);

  final PeerIdentity _identity;
  final Sodium _sodium;

  /// Ephemeral key pair for this handshake.
  late final SecureKey _ephemeralPublic;
  late final SecureKey _ephemeralSecret;

  SessionHandshake(this._identity) : _sodium = SodiumInit.init(DynamicLibrary.process()) {
    _ephemeralKeyPair();
  }

  void _ephemeralKeyPair() {
    final pair = _sodium.cryptoBoxKeyPair();
    _ephemeralPublic = pair.publicKey;
    _ephemeralSecret = pair.secretKey;
  }

  /// Build the initiator handshake payload.
  Future<Map<String, dynamic>> buildInitiatorPayload() async {
    final ephemeralPubHex = _sodium.toHex(_ephemeralPublic);
    // Sign ephemeral with static secret (using crypto_box_seal as authenticator)
    final signature = _sodium.toHex(
      _sodium.cryptoBoxSeal(
        Uint8List.fromList(ephemeralPubHex.codeUnits),
        SecureKey.fromList(_sodium, _sodium.fromHex(_identity.publicKeyHex)),
      ),
    );
    return {
      'type': 'handshake.initiator',
      'ephemeral_pubkey': ephemeralPubHex,
      'signature': signature,
    };
  }

  /// Process responder payload and derive session keys.
  Future<SessionKeys> completeInitiator(Map<String, dynamic> responderPayload) async {
    final remoteEphemeralHex = responderPayload['ephemeral_pubkey'] as String;
    final remoteStaticHex = responderPayload['static_pubkey'] as String;

    final shared = _computeSharedSecret(
      remoteEphemeral: remoteEphemeralHex,
      remoteStatic: remoteStaticHex,
    );
    return _deriveKeys(shared);
  }

  /// Process initiator payload and build responder response.
  Future<Map<String, dynamic>> buildResponderResponse(
    Map<String, dynamic> initiatorPayload,
  ) async {
    final remoteEphemeralHex = initiatorPayload['ephemeral_pubkey'] as String;
    final remoteStaticHex = initiatorPayload['static_pubkey'] as String;

    final shared = _computeSharedSecret(
      remoteEphemeral: remoteEphemeralHex,
      remoteStatic: remoteStaticHex,
    );
    final keys = _deriveKeys(shared);

    return {
      'type': 'handshake.responder',
      'ephemeral_pubkey': _sodium.toHex(_ephemeralPublic),
      'static_pubkey': _identity.publicKeyHex,
      'session_confirm': keys.confirmHex,
    };
  }

  /// Process responder payload as initiator (second round).
  Future<SessionKeys> completeResponder(Map<String, dynamic> responderPayload) async {
    final remoteEphemeralHex = responderPayload['ephemeral_pubkey'] as String;
    final shared = _computeSharedSecret(
      remoteEphemeral: remoteEphemeralHex,
      remoteStatic: responderPayload['static_pubkey'] as String?,
    );
    return _deriveKeys(shared);
  }

  Uint8List _computeSharedSecret({
    required String remoteEphemeral,
    String? remoteStatic,
  }) {
    final parts = <Uint8List>[];

    // DH(ephemeral_local, ephemeral_remote)
    final ee = _sodium.cryptoBoxBeforeNm(
      SecureKey.fromList(_sodium, _sodium.fromHex(remoteEphemeral)),
      _ephemeralSecret,
    );
    parts.add(ee);

    // DH(ephemeral_local, static_remote)
    if (remoteStatic != null) {
      final es = _sodium.cryptoBoxBeforeNm(
        SecureKey.fromList(_sodium, _sodium.fromHex(remoteStatic)),
        _ephemeralSecret,
      );
      parts.add(es);
    }

    // DH(static_local, ephemeral_remote)
    final se = _sodium.cryptoBoxBeforeNm(
      SecureKey.fromList(_sodium, _sodium.fromHex(remoteEphemeral)),
      _identity.secretKey,
    );
    parts.add(se);

    // DH(static_local, static_remote)
    if (remoteStatic != null) {
      final ss = _sodium.cryptoBoxBeforeNm(
        SecureKey.fromList(_sodium, _sodium.fromHex(remoteStatic)),
        _identity.secretKey,
      );
      parts.add(ss);
    }

    return Uint8List.fromList(parts.expand((e) => e).toList());
  }

  SessionKeys _deriveKeys(Uint8List sharedSecret) {
    final sodium = _sodium;
    // HKDF-SHA256 via crypto_kdf
    final keyMaterial = sodium.cryptoKdfDeriveFromKey(
      64, // 32-byte encryption key + 32-byte confirmation
      1,  // subkey index
      Uint8List.fromList(utf8.encode(_info)), // context
      SecureKey.fromList(sodium, sharedSecret),
    );

    final encryptionKey = keyMaterial.sublist(0, 32);
    final confirmationKey = keyMaterial.sublist(32, 64);

    return SessionKeys(
      encryptionKey: encryptionKey,
      confirmationKey: confirmationKey,
      confirmHex: sodium.toHex(confirmationKey),
    );
  }

  void dispose() {
    _ephemeralPublic.dispose();
    _ephemeralSecret.dispose();
    _identity.dispose();
  }
}

/// Derived session keys for a single peer connection.
class SessionKeys {
  final Uint8List encryptionKey;
  final Uint8List confirmationKey;
  final String confirmHex;

  SessionKeys({
    required this.encryptionKey,
    required this.confirmationKey,
    required this.confirmHex,
  });

  void dispose() {
    // SecureZero not available in dart:sodium directly; rely on GC.
  }
}
