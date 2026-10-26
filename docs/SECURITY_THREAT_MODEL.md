# Techuboard Security Architecture (C4 + STRIDE)

## 1. System Context (Level 1)
Techuboard ecosystem (macOS, Android, Windows, iOS) synchronizes clipboard data, files, and notifications locally via encrypted LAN transport, utilizing a central authenticated relay for discovery and tunnel initiation when LAN is unreachable.

## 2. Threat Model (STRIDE)
- **S**poofing: Mitigated by long-term X25519 identity keys + TOFU pinning + mutual authentication in handshake.
- **T**ampering: Mitigated by AES-GCM-256 / XChaCha20-Poly1305 per-session encryption + SHA-256 message integrity.
- **R**epudiation: Mitigated by message sequence numbers and per-peer ACK/NACK protocol.
- **I**nformation Disclosure: Mitigated by encryption at rest (SecureStorage/Keychain) and per-session ephemeral keys (Forward Secrecy).
- **D**enial of Service: Mitigated by LAN-only socket binding, connection rate limiting, session capacity limits.
- **E**levation of Privilege: Mitigated by platform-native OS sandboxing (Android/iOS/macOS).
