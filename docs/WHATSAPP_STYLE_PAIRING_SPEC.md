# WhatsApp-Style Link Device Pairing Protocol (Techuboard Zero-Trust P2P)

## 🎯 Executive Overview
This specification details the 1-click **WhatsApp Link Device** pairing workflow for Techuboard across macOS, Android, Windows, and iOS.

---

## 📱 User Workflow (UX)

```
+------------------------------------+         +------------------------------------+
|         Device A (Primary)         |         |         Device B (Companion)       |
|                                    |         |                                    |
| [ QR CODE DISPLAYED ]              |  Scan   | [ CAMERA SCANNER OPEN ]            |
| "Scan with Techuboard App"        | <====== | Point camera at screen             |
|                                    |   or    |                                    |
|  Or enter 6-digit code: [749-823]  |  Type   | Enter code: [ 749823 ]             |
+------------------------------------+         +------------------------------------+
                                         ||
                                         \/  <1 Second P2P Handshake
+-----------------------------------------------------------------------------------+
| ✅ INSTANT SUCCESS: "Device B Connected! Clipboard Sync & Transfer Active"        |
+-----------------------------------------------------------------------------------+
```

---

## 🔐 Cryptographic Payload Structure

### 1. QR Code Payload Format (`techuboard://pair`)
```json
{
  "v": 1,
  "id": "8f3b2a11-0c4d-4e22-91a5-812e4f009211",
  "name": "MacBook Pro",
  "ip": "192.168.1.105",
  "port": 5566,
  "pk": "a4f8e9120b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e",
  "psk": "e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2"
}
```

### 2. 6-Digit Short Pairing Code
- Short code maps to a temporary local LAN UDP broadcast beacon (`255.255.255.255:5567`).
- Expiration: 180 seconds.
- Single-use: invalidates immediately upon successful handshake.

---

## 🔄 Cryptographic Handshake & Identity Pinning

1. **Scan / Code Entry**: Companion device extracts Target IP, Port, Static Public Key (`pk`), and One-Time Secret (`psk`).
2. **LAN Connection**: Establishes TCP connection to `IP:Port`.
3. **Noise IKpsk2 Handshake**:
   - Both devices derive session keys using X25519 DH + HKDF-SHA256 authenticated by the scanned `psk`.
4. **Trust On First Use (TOFU) Pinning**:
   - Both devices save each other's Static Public Key (`pk`) in Secure Storage (Android EncryptedSharedPreferences / iOS Keychain / macOS Keychain / Windows DPAPI).
5. **Permanent Authorization**:
   - Future connections automatically authenticate using the pinned public keys without requiring re-scanning.

---

## 🛡️ CEO 4-Point Scrutiny Matrix

| Scrutiny Filter | Result | Verification |
|-----------------|--------|--------------|
| 💰 **Financial & Margin Risk** | **$0 Cost** | 100% P2P local LAN / direct socket. Zero cloud server overhead. |
| ⏱️ **Customer Experience** | **<1s Pairing** | Instant camera QR detection with haptic feedback. |
| 🧠 **Staff Usability** | **WhatsApp-Identical** | Zero IP addresses, zero technical terms for users. |
| 🛡️ **Fail-Safe** | **Offline Ready** | Works over local Wi-Fi, mobile hotspot, or direct Ethernet. 6-digit code fallback if camera disabled. |
