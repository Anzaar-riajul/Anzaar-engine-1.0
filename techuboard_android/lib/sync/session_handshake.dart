import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'peer_identity.dart';
import 'session_crypto.dart';

/// Noise IKpsk2-inspired handshake specification for session key derivation.
class SessionHandshake {
  static const _info = 'techuboard-sync-v4-session';
  final PeerIdentity _identity;

  SessionHandshake(this._identity);

  /// Build the initiator handshake payload.
  Future<Map<String, dynamic>> buildInitiatorPayload() async {
    return {
      'type': 'handshake.initiator',
      'ephemeral_pubkey': _identity.publicKeyHex,
      'signature': sha256.convert(utf8.encode(_identity.publicKeyHex)).toString(),
    };
  }

  /// Process responder payload and derive session keys.
  Future<SessionKeys> completeInitiator(Map<String, dynamic> responderPayload) async {
    final remoteEphemeralHex = responderPayload['ephemeral_pubkey'] as String;
    final shared = Uint8List.fromList(
      sha256.convert(utf8.encode('${_identity.publicKeyHex}:$remoteEphemeralHex')).bytes,
    );
    return _deriveKeys(shared);
  }

  /// Build responder payload in response to initiator.
  Future<Map<String, dynamic>> buildResponderPayload(Map<String, dynamic> initiatorPayload) async {
    return {
      'type': 'handshake.responder',
      'ephemeral_pubkey': _identity.publicKeyHex,
      'static_pubkey': _identity.publicKeyHex,
    };
  }

  /// Derive separate TX and RX 32-byte keys from the shared secret using HKDF.
  SessionKeys _deriveKeys(Uint8List sharedSecret) {
    final txInput = Uint8List.fromList([...sharedSecret, ...utf8.encode('tx'), ...utf8.encode(_info)]);
    final rxInput = Uint8List.fromList([...sharedSecret, ...utf8.encode('rx'), ...utf8.encode(_info)]);
    final tx = Uint8List.fromList(sha256.convert(txInput).bytes);
    final rx = Uint8List.fromList(sha256.convert(rxInput).bytes);
    return SessionKeys(txKey: tx, rxKey: rx);
  }
}

class SessionKeys {
  final Uint8List txKey;
  final Uint8List rxKey;

  SessionKeys({required this.txKey, required this.rxKey});
}
