# Phase 1 Task 1 — Per-Peer Session Key Exchange Design

## Problem
Hardcoded `TechuboardSyncSecret2026` key shared across ALL devices (P0-1). No mutual authentication (P0-2).

## Solution
Noise Protocol Framework IKpsk2-inspired handshake using libsodium (`crypto_box` = X25519 + XSalsa20-Poly1305, `crypto_kdf` = HKDF-SHA256 variant).

## Components

### 1. PeerIdentity (per device)
- Long-term X25519 key pair generated at first launch
- Stored in platform secure storage (flutter_secure_storage / Keychain / Secure Enclave / DPAPI)
- Public key shared during handshake for mutual authentication

### 2. SessionHandshake (per connection)
1. Both peers generate ephemeral X25519 key pair
2. Exchange: ephemeral pubkey + signature of ephemeral with static key
3. Compute shared secret: DH(ephemeral_local, ephemeral_remote) || DH(ephemeral_local, static_remote) || DH(static_local, ephemeral_remote) || DH(static_local, static_remote)
4. HKDF-SHA256(shared_secret, info="techuboard-sync-v4") → 256-bit session key

### 3. SessionCrypto (per session)
- XChaCha20-Poly1305 (libsodium `crypto_secretbox`) with per-message nonce
- Rekey every 1 hour or 1 GB transferred (forward secrecy)
- Session keys never written to disk

## Files to modify/create
- `techuboard_android/lib/sync/peer_identity.dart` (new)
- `techuboard_android/lib/sync/session_handshake.dart` (new)
- `techuboard_android/lib/sync/session_crypto.dart` (new)
- `techuboard_android/lib/sync/crypto.dart` (update — remove hardcoded key)
- `techuboard_android/lib/sync/protocol.dart` (update — add handshake types)
- `techuboard_android/lib/sync/session.dart` (update — handshake before data)
- `techuboard_android/lib/sync_manager.dart` (update — manage identities)
- `techuboard_macos/Sources/Sync/SyncCrypto.swift` (update)
- `techuboard_macos/Sources/Sync/SyncManager.swift` (update)

## CEO 4-Point Scrutiny
| Filter | Verdict |
|--------|---------|
| 💰 Financial | ✅ PASS — no cost impact |
| ⏱️ CX | ✅ PASS — handshake adds ~50ms, imperceptible |
| 🧠 Staff Usability | ✅ PASS — transparent to user |
| 🛡️ Fail-Safe | ✅ PASS — fallback to legacy key if handshake fails (migration mode) |

## Execution Receipt
Pending implementation.
