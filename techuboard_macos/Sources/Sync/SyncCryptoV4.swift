import Foundation
import CryptoKit

/// World-class v4 Secure Session Crypto for macOS (CryptoKit Curve25519 + HKDF-SHA256).
/// Replaces the hardcoded v3 static key with per-peer authenticated session keys.
final class SyncCryptoV4 {
    static let shared = SyncCryptoV4()

    private let keychainService = "com.techuboard.app.identity"
    private let identityKeyTag = "com.techuboard.app.x25519.private"

    private(set) var staticPrivateKey: Curve25519.KeyAgreement.PrivateKey
    private var sessionKeys: [String: SymmetricKey] = [:]
    private let queue = DispatchQueue(label: "com.techuboard.crypto.v4.queue", attributes: .concurrent)

    private init() {
        if let existing = SyncCryptoV4.loadPrivateKeyFromKeychain() {
            self.staticPrivateKey = existing
        } else {
            let newKey = Curve25519.KeyAgreement.PrivateKey()
            _ = SyncCryptoV4.savePrivateKeyToKeychain(newKey)
            self.staticPrivateKey = newKey
        }
    }

    var staticPublicKeyHex: String {
        return staticPrivateKey.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Derive per-peer session key using X25519 key agreement + HKDF-SHA256.
    func establishSession(peerId: String, remotePublicKeyHex: String) -> Bool {
        guard let remoteData = Data(hex: remotePublicKeyHex),
              let remotePublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteData) else {
            return false
        }

        do {
            let sharedSecret = try staticPrivateKey.sharedSecretFromKeyAgreement(with: remotePublicKey)
            let salt = "techuboard-sync-v4-salt".data(using: .utf8)!
            let info = "techuboard-sync-v4-session".data(using: .utf8)!

            let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: info,
                outputByteCount: 32
            )

            queue.async(flags: .barrier) {
                self.sessionKeys[peerId] = derivedKey
            }
            return true
        } catch {
            return false
        }
    }

    /// Encrypt plaintext for a specific peer using v4 session key (AES-GCM-256 via CryptoKit).
    func encrypt(peerId: String, text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let key = sessionKey(for: peerId) else { return nil }
        do {
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)
            var combined = Data(nonce)
            combined.append(sealed.ciphertext)
            combined.append(sealed.tag)
            return combined.base64EncodedString()
        } catch {
            return nil
        }
    }

    /// Decrypt base64 payload from a specific peer.
    func decrypt(peerId: String, base64: String) -> String? {
        guard let data = Data(base64Encoded: base64), data.count > 28,
              let key = sessionKey(for: peerId) else { return nil }
        do {
            let nonce = try AES.GCM.Nonce(data: data.prefix(12))
            let tag = data.suffix(16)
            let ciphertext = data.dropFirst(12).dropLast(16)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let plain = try AES.GCM.open(box, using: key)
            return String(data: plain, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func sessionKey(for peerId: String) -> SymmetricKey? {
        var key: SymmetricKey?
        queue.sync {
            key = sessionKeys[peerId]
        }
        return key
    }

    private static func savePrivateKeyToKeychain(_ key: Curve25519.KeyAgreement.PrivateKey) -> Bool {
        let data = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.techuboard.app",
            kSecAttrAccount as String: "x25519_identity",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func loadPrivateKeyFromKeychain() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.techuboard.app",
            kSecAttrAccount as String: "x25519_identity",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
}

extension Data {
    init?(hex: String) {
        var len = hex.count
        var data = Data(capacity: len / 2)
        var ptr = hex.utf8.makeIterator()
        while let c1 = ptr.next(), let c2 = ptr.next() {
            guard let v1 = UnicodeScalar(c1)?.value, let v2 = UnicodeScalar(c2)?.value,
                  let d1 = DecimalDigit(v1), let d2 = DecimalDigit(v2) else { return nil }
            data.append(UInt8(d1 * 16 + d2))
        }
        self = data
    }
}

private func DecimalDigit(_ val: UInt32) -> Int? {
    switch val {
    case 48...57: return Int(val - 48)
    case 65...70: return Int(val - 55)
    case 97...102: return Int(val - 87)
    default: return nil
    }
}
