import AppKit
import Foundation

class PreferencesManager {
    static let shared = PreferencesManager()
    
    private let defaults = UserDefaults.standard
    private let historyLimitKey = "historyLimit"
    private let historyLoadCountKey = "historyLoadCount"
    private let excludedAppsKey = "excludedApps"
    private let historyRetentionDaysKey = "historyRetentionDays"
    private let syncEnabledKey = "syncEnabled"
    private let syncPortKey = "syncPort"
    /// New key on purpose: the old `syncSecret` slot could hold a per-install
    /// random value that was never used for anything, and reading it as a
    /// pairing secret would derive a key no other device shares.
    private let authorizedDevicesKey = "authorizedDevices"
    private let authorizedPeerIdsKey = "authorizedPeerIds"
    private let clipboardSyncPeerIdsKey = "clipboardSyncPeerIds"
    private let notificationSyncPeerIdsKey = "notificationSyncPeerIds"
    private let syncPeerIdKey = "syncPeerId"
    private let authorizedPeerIdsMigratedKey = "authorizedPeerIdsMigrated"
    private let dualSyncAuthMigratedKey = "dualSyncAuthMigrated"
    private let deviceNameKey = "deviceName"
    private let appLanguageKey = "appLanguage"
    private let launchAtLoginKey = "launchAtLogin"
    private let historyEncryptionEnabledKey = "historyEncryptionEnabled"
    private let historyImageOCRIndexingKey = "historyImageOCRIndexing"
    private let searchGlobalShortcutEnabledKey = "searchGlobalShortcutEnabled"
    private let searchHistoryShortcutKey = "searchHistoryShortcut"
    private let screenshotOCRLanguageKey = "screenshotOCRLanguage"
    
    /// `Host.current().localizedName` can hit mDNS/DNS resolution and block for
    /// seconds. The device name is read on hot paths (every sync handshake and
    /// menu build), so resolve it at most once per launch.
    private static let fallbackDeviceName: String = {
        // gethostname()-backed, unlike Host.current() — strip the ".local" suffix
        // and turn the hyphens Bonjour inserts back into spaces.
        let shortName = ProcessInfo.processInfo.hostName
            .components(separatedBy: ".")
            .first?
            .replacingOccurrences(of: "-", with: " ") ?? ""
        return shortName.isEmpty ? "Mac" : shortName
    }()

    /// Local-only opt-in; never synchronized to other devices.
    var menuBarOverflowEnabled: Bool {
        get { defaults.bool(forKey: "menuBarOverflowEnabled") }
        set { defaults.set(newValue, forKey: "menuBarOverflowEnabled") }
    }

    var deviceName: String {
        get { defaults.string(forKey: deviceNameKey) ?? Self.fallbackDeviceName }
        set { defaults.set(newValue, forKey: deviceNameKey) }
    }

    var appLanguage: AppLanguage {
        get {
            guard let rawValue = defaults.string(forKey: appLanguageKey),
                  let language = AppLanguage(rawValue: rawValue) else {
                return AppLanguage.systemDefault
            }
            return language
        }
        set {
            guard appLanguage != newValue else { return }
            defaults.set(newValue.rawValue, forKey: appLanguageKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }
    
    var historyLimit: Int {
        get { defaults.integer(forKey: historyLimitKey) == 0 ? 1000 : defaults.integer(forKey: historyLimitKey) }
        set { defaults.set(newValue, forKey: historyLimitKey) }
    }

    /// 每次从磁盘加载到内存的历史条数（默认 100）
    var historyLoadCount: Int {
        get {
            let value = defaults.integer(forKey: historyLoadCountKey)
            return value == 0 ? 100 : value
        }
        set { defaults.set(newValue, forKey: historyLoadCountKey) }
    }
    
    /// Days to keep unpinned history; 0 keeps it forever.
    var historyRetentionDays: Int {
        get { defaults.integer(forKey: historyRetentionDaysKey) }
        set { defaults.set(max(0, newValue), forKey: historyRetentionDaysKey) }
    }

    var excludedApps: [String] {
        get { defaults.stringArray(forKey: excludedAppsKey) ?? ["com.agilebits.onepassword7", "com.apple.keychainaccess"] }
        set { defaults.set(newValue, forKey: excludedAppsKey) }
    }

    var isSyncEnabled: Bool {
        get { defaults.bool(forKey: syncEnabledKey) }
        set { defaults.set(newValue, forKey: syncEnabledKey) }
    }

    var syncPort: Int {
        get { 
            let port = defaults.integer(forKey: syncPortKey)
            return port == 0 ? 5566 : port
        }
        set { defaults.set(newValue, forKey: syncPortKey) }
    }

    var syncPeerId: String {
        get {
            if let id = defaults.string(forKey: syncPeerIdKey), !id.isEmpty, Self.isValidUuid(id) {
                return id
            }
            // Regenerate if empty OR not a canonical UUID. Protocol-v1 stored
            // peerId as "Android-<8hex>" / "iOS-<8hex>"; those legacy values
            // revive verbatim and corrupt session identity (adoptSession dedup,
            // role arbitration, auth lists).
            if let stale = defaults.string(forKey: syncPeerIdKey), !stale.isEmpty {
                pruneLegacyAuthorizedPeerIds(oldPeerId: stale)
                appLog("syncPeerId invalid format, regenerating: \(stale)", level: .warning)
            }
            let id = UUID().uuidString
            defaults.set(id, forKey: syncPeerIdKey)
            pruneLegacyAuthorizedPeerIds()
            return id
        }
    }

    /// Canonical UUID v4 format: 8-4-4-4-12 hex digits with hyphens.
    static let uuidPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    }()

    static func isValidUuid(_ id: String) -> Bool {
        let range = NSRange(id.startIndex..., in: id)
        return uuidPattern.firstMatch(in: id, options: [], range: range) != nil
    }

    /// Remove legacy non-UUID entries (e.g. "Android-066f3806", raw display names)
    /// from all three auth lists. These point at identities that no longer exist
    /// after peerId regeneration or protocol-v1→v2 upgrade, and would silently
    /// block fanout to the real peer (which now has a proper UUID).
    func pruneLegacyAuthorizedPeerIds(oldPeerId: String? = nil) {
        func prune(_ key: String) {
            let list = defaults.stringArray(forKey: key) ?? []
            let kept = list.filter { Self.isValidUuid($0) && $0 != oldPeerId }
            if kept.count != list.count {
                defaults.set(kept, forKey: key)
            }
        }
        prune(clipboardSyncPeerIdsKey)
        prune(notificationSyncPeerIdsKey)
        prune(authorizedPeerIdsKey)
        // Legacy v1 list stored display names, never valid peerIds — clear once.
        if defaults.object(forKey: authorizedDevicesKey) != nil {
            defaults.removeObject(forKey: authorizedDevicesKey)
        }
    }

    /// Union of clipboard + notification outbound targets (stale UI / discovery hints).
    var authorizedPeerIds: [String] {
        get {
            migrateDualSyncAuthIfNeeded()
            return Array(Set(clipboardSyncPeerIds).union(notificationSyncPeerIds)).sorted()
        }
        set {
            // Legacy single-list writes apply to both capabilities.
            clipboardSyncPeerIds = newValue
            notificationSyncPeerIds = newValue
            defaults.set(newValue, forKey: authorizedPeerIdsKey)
        }
    }

    /// Peers this device may push clipboard/history to (outbound only).
    var clipboardSyncPeerIds: [String] {
        get {
            migrateDualSyncAuthIfNeeded()
            return defaults.stringArray(forKey: clipboardSyncPeerIdsKey) ?? []
        }
        set {
            defaults.set(newValue, forKey: clipboardSyncPeerIdsKey)
            syncAuthorizedPeerIdsUnion()
        }
    }

    /// Peers this device may push notifications to (outbound only).
    var notificationSyncPeerIds: [String] {
        get {
            migrateDualSyncAuthIfNeeded()
            return defaults.stringArray(forKey: notificationSyncPeerIdsKey) ?? []
        }
        set {
            defaults.set(newValue, forKey: notificationSyncPeerIdsKey)
            syncAuthorizedPeerIdsUnion()
        }
    }

    var authorizedDevices: [String] {
        get { defaults.stringArray(forKey: authorizedDevicesKey) ?? [] }
        set { defaults.set(newValue, forKey: authorizedDevicesKey) }
    }

    /// One-shot: copy legacy `authorizedPeerIds` into both capability lists (both on).
    private func migrateDualSyncAuthIfNeeded() {
        guard !defaults.bool(forKey: dualSyncAuthMigratedKey) else { return }
        let legacy = defaults.stringArray(forKey: authorizedPeerIdsKey) ?? []
        if defaults.object(forKey: clipboardSyncPeerIdsKey) == nil {
            defaults.set(legacy, forKey: clipboardSyncPeerIdsKey)
        }
        if defaults.object(forKey: notificationSyncPeerIdsKey) == nil {
            defaults.set(legacy, forKey: notificationSyncPeerIdsKey)
        }
        defaults.set(true, forKey: dualSyncAuthMigratedKey)
        syncAuthorizedPeerIdsUnion()
    }

    private func syncAuthorizedPeerIdsUnion() {
        let union = Array(
            Set(defaults.stringArray(forKey: clipboardSyncPeerIdsKey) ?? [])
                .union(defaults.stringArray(forKey: notificationSyncPeerIdsKey) ?? [])
        ).sorted()
        defaults.set(union, forKey: authorizedPeerIdsKey)
    }

    func setClipboardSync(peerId: String, enabled: Bool) {
        var ids = Set(clipboardSyncPeerIds)
        if enabled { ids.insert(peerId) } else { ids.remove(peerId) }
        clipboardSyncPeerIds = ids.sorted()
    }

    func setNotificationSync(peerId: String, enabled: Bool) {
        var ids = Set(notificationSyncPeerIds)
        if enabled { ids.insert(peerId) } else { ids.remove(peerId) }
        notificationSyncPeerIds = ids.sorted()
    }

    /// Remove a peer from both capability lists (stale offline row delete).
    func removeAuthorizedPeer(_ peerId: String) {
        var clip = Set(clipboardSyncPeerIds)
        var notif = Set(notificationSyncPeerIds)
        clip.remove(peerId)
        notif.remove(peerId)
        clipboardSyncPeerIds = clip.sorted()
        notificationSyncPeerIds = notif.sorted()
    }

    /// Manually configured peers (format "host:port") for cross-band /
    /// cross-subnet discovery when mDNS multicast is isolated by the router.
    private let manualSyncPeersKey = "manualSyncPeers"
    var manualSyncPeers: [String] {
        get { defaults.stringArray(forKey: manualSyncPeersKey) ?? [] }
        set { defaults.set(newValue, forKey: manualSyncPeersKey) }
    }

    func addManualPeer(_ peer: String) {
        var peers = manualSyncPeers
        if !peers.contains(peer) {
            peers.append(peer)
            manualSyncPeers = peers
        }
    }

    func removeManualPeer(_ peer: String) {
        var peers = manualSyncPeers
        peers.removeAll { $0 == peer }
        manualSyncPeers = peers
    }

    /// Maps legacy display-name authorizations to stable peer IDs when peers are discovered.
    func migrateAuthorizedPeerIds(from peers: [DiscoveredPeer]) {
        guard !defaults.bool(forKey: authorizedPeerIdsMigratedKey) else { return }

        var peerIds = Set(authorizedPeerIds)
        for legacyName in authorizedDevices {
            if let match = peers.first(where: { $0.displayName == legacyName }) {
                peerIds.insert(match.peerId)
            } else {
                // Pre-peerId builds used the mDNS service name as SyncMessage.deviceId.
                peerIds.insert(legacyName)
            }
        }
        authorizedPeerIds = peerIds.sorted()
        defaults.set(true, forKey: authorizedPeerIdsMigratedKey)
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: launchAtLoginKey) }
        set { defaults.set(newValue, forKey: launchAtLoginKey) }
    }

    var isHistoryEncryptionEnabled: Bool {
        get { defaults.bool(forKey: historyEncryptionEnabledKey) }
        set { defaults.set(newValue, forKey: historyEncryptionEnabledKey) }
    }

    /// Whether image history entries are OCR-indexed for search. Defaults ON;
    /// the first recognition loads Vision's models (~100MB resident for the
    /// process lifetime), which is the single largest component of the
    /// post-screenshot memory floor.
    var isHistoryImageOCRIndexingEnabled: Bool {
        get {
            if defaults.object(forKey: historyImageOCRIndexingKey) == nil { return true }
            return defaults.bool(forKey: historyImageOCRIndexingKey)
        }
        set { defaults.set(newValue, forKey: historyImageOCRIndexingKey) }
    }

    var isSearchGlobalShortcutEnabled: Bool {
        get {
            if defaults.object(forKey: searchGlobalShortcutEnabledKey) == nil { return true }
            return defaults.bool(forKey: searchGlobalShortcutEnabledKey)
        }
        set { defaults.set(newValue, forKey: searchGlobalShortcutEnabledKey) }
    }

    var isWordShortcutEnabled: Bool {
        get { defaults.object(forKey: "wordShortcutEnabled") == nil || defaults.bool(forKey: "wordShortcutEnabled") }
        set { defaults.set(newValue, forKey: "wordShortcutEnabled") }
    }

    var wordLookupShortcut: ShortcutCombo? {
        get {
            // An explicit clear must survive restart instead of restoring the default.
            guard defaults.object(forKey: "wordLookupShortcut") != nil else {
                return ShortcutCombo(keyCode: 0x02, modifierFlags: NSEvent.ModifierFlags([.control, .option]).rawValue)
            }
            guard let data = defaults.data(forKey: "wordLookupShortcut") else { return nil }
            return try? JSONDecoder().decode(ShortcutCombo.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: "wordLookupShortcut")
        }
    }

    var searchHistoryShortcut: ShortcutCombo? {
        get {
            if let data = defaults.data(forKey: searchHistoryShortcutKey),
               let combo = try? JSONDecoder().decode(ShortcutCombo.self, from: data) {
                return combo
            }
            return ShortcutCombo(keyCode: 0x03, modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: searchHistoryShortcutKey)
            } else {
                defaults.removeObject(forKey: searchHistoryShortcutKey)
            }
        }
    }

    var screenshotOCRLanguage: ScreenshotOCRLanguage {
        get {
            guard let raw = defaults.string(forKey: screenshotOCRLanguageKey),
                  let language = ScreenshotOCRLanguage(rawValue: raw) else {
                return .default
            }
            return language
        }
        set { defaults.set(newValue.rawValue, forKey: screenshotOCRLanguageKey) }
    }
    
    private init() {}
}
