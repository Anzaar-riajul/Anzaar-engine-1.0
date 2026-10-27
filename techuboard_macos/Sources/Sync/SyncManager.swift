import Foundation
import AppKit
import Network
import CryptoKit

/// Public synchronization facade. Transport, discovery, crypto, and reliability
/// implementation details live in the sibling Sync*.swift extensions.
final class SyncManager: NSObject {
    static let shared = SyncManager()

    var onDevicesChanged: (([String]) -> Void)?
    var onPeersChanged: (([DiscoveredPeer]) -> Void)?

    let syncQueue = DispatchQueue(label: "com.techuboard.sync.v2")
    let scanQueue = DispatchQueue(label: "com.techuboard.scan.v2", attributes: .concurrent)
    let dialDedupLock = NSLock()
    /// Allocated on first recv — a 64KB buffer used to live here even when
    /// sync was disabled entirely.
    var receiveScratch = Data()

    static let maxFrameLength = 4 * 1024 * 1024
    static let maxHandshakeFrameLength = 64 * 1024
    static let defaultPort: UInt16 = 5566
    static let discoveryDebounce: TimeInterval = 0.6
    static let handshakeTimeout: TimeInterval = 2.0
    static let connectTimeout: TimeInterval = 3.0
    static let scanConnectTimeout: TimeInterval = 0.35
    static let pingInterval: TimeInterval = 30
    static let pendingQueueMax = 500
    static let pendingQueueTTL: TimeInterval = 24 * 60 * 60
    static let pendingAckRetryAge: TimeInterval = 120
    static let endpointCacheKey = "techuboard.peerEndpoints.v2"
    static let endpointCacheTTL: TimeInterval = 86400
    static let maxReconnectBackoff: TimeInterval = 30
    static let minReconnectInterval: TimeInterval = 2
    static let scanConcurrency = 48
    static let subnetScanCooldown: TimeInterval = 60
    /// Align with Android history.fetch *request* throttle (15 min).
    static let historyFetchThrottle: TimeInterval = 15 * 60

    var displayName: String { PreferencesManager.shared.deviceName }
    var peerId: String { PreferencesManager.shared.syncPeerId }
    var syncPort: UInt16 {
        UInt16(clamping: PreferencesManager.shared.syncPort == 0 ? Int(Self.defaultPort) : PreferencesManager.shared.syncPort)
    }

    let diagnostics = SyncDiagnostics()
    var relayConfigurationGeneration = 0
    static let defaultEncryptionKey = SymmetricKey(data: SHA256.hash(data: Data("TechuboardSyncSecret2026".utf8)))


    var discoveredPeers: [String: DiscoveredPeer] = [:]
    let peersLock = NSLock()
    var pendingDiscoveryWork: DispatchWorkItem?
    var isRefreshingDiscovery = false
    let scanStateLock = NSLock()
    var isScanning = false
    var lastScanFinishedAt: Date?
    var serviceGeneration = 0
    var lastDialAt: [String: Date] = [:]
    let dialDedupTTL: TimeInterval = 4

    // Auto-rediscovers a peer whose cached endpoint died (e.g. its DHCP lease
    // moved): after this many consecutive authorized dial failures, fall back
    // to one full /24 scan — throttled so a dead address can't scan on every
    // discovery cycle. Guarded by selfHealLock: dials run on the concurrent
    // scanQueue while adoption runs on syncQueue.
    static let autoRediscoverFailThreshold = 2
    static let autoRediscoverCooldown: TimeInterval = 10 * 60
    let selfHealLock = NSLock()
    var authorizedDialFailStreak = 0
    var lastAutoRediscoverAt: Date?

    /// A full /24 scan writes a dedup entry per dial (~254). They are only
    /// meaningful for `dialDedupTTL` seconds, so drop the stale ones once the
    /// scan finishes instead of keeping the map growing forever.
    func pruneStaleDialTimestamps() {
        let now = Date()
        dialDedupLock.lock()
        lastDialAt = lastDialAt.filter { now.timeIntervalSince($0.value) < 30 }
        dialDedupLock.unlock()
    }

    struct Session {
        let peerId: String
        let host: String
        let port: UInt16
        var fd: Int32
        var readSource: DispatchSourceRead?
        var writer: SyncSocketWriter?
        var historyReplayRows: [Int64] = []
        var buffer = Data()
        var lastPong = Date()
        let isClient: Bool
    }
    var sessions: [String: Session] = [:]
    var reconnectBackoffs: [String: TimeInterval] = [:]
    var pendingReconnects: [String: DispatchWorkItem] = [:]
    var lastReconnectAttempt: [String: Date] = [:]

    var relayClient: SyncRelayClient?
    var relayConnecting = Set<String>()
    var listenFD: Int32 = -1
    var listenSource: DispatchSourceRead?
    var listenerClosing = false
    var listenerStartRequested = false
    var listenerRequestedPort: UInt16?
    var acceptingClients: [Int32: (host: String, buffer: Data, source: DispatchSourceRead)] = [:]
    var inFlightHashes: [String: Set<String>] = [:]
    var lastHistoryFetchResponse: [String: Date] = [:]
    var pingTimer: DispatchSourceTimer?
    var pathMonitor: NWPathMonitor?
    var lastPathStatus: NWPath.Status = .requiresConnection
    var networkProbe: DispatchWorkItem?
    var lastPathSignature: String?

    // MARK: File transfer state (SyncFileTransfer.swift)
    // incomingFiles / fileAckWaiters are only touched on syncQueue.
    struct IncomingFileState {
        let peerId: String
        let senderName: String
        let fileId: String
        let fileName: String
        let fileSize: Int
        let chunkSize: Int
        let chunkCount: Int
        let sha256: String
        let partURL: URL
        let folderName: String?
        /// Persistent append handle opened at file.meta; closed by
        /// completeChunkedFile / discardIncomingFile.
        var handle: FileHandle?
        var received: Set<Int> = []
        var idleWork: DispatchWorkItem?
    }
    var incomingFiles: [String: IncomingFileState] = [:]
    var fileAckWaiters: [String: (Bool) -> Void] = [:]
    let fileTransferQueue = DispatchQueue(label: "com.techuboard.sync.filetransfer")
    // A send waits for the remote ACK. Receiving must remain independent so
    // two Macs sending at the same time can still finish each other's files.
    let fileReceiveQueue = DispatchQueue(label: "com.techuboard.sync.filereceive")
    #if TECHUBOARD_CORE_TESTS
    var fileReceiveDirectoryForTesting: URL?
    #endif

    // MARK: - Lifecycle

    func start() {
        appLog("SyncManager v3 starting...")
        guard PreferencesManager.shared.isSyncEnabled || NotificationManager.shared.notificationSyncEnabled else { return }
        syncQueue.async { [weak self] in
            guard let self else { return }
            let defaults = UserDefaults.standard
            if defaults.integer(forKey: "syncTransportVersion") != SyncEnvelope.version {
                // Stored v2 ciphertext cannot be replayed with the default v3 key.
                // Local history and device sharing choices remain intact.
                PendingSyncRepository.shared.clearAll()
                defaults.removeObject(forKey: "syncPairingSecret")
                defaults.removeObject(forKey: "syncSecret")
                defaults.set(SyncEnvelope.version, forKey: "syncTransportVersion")
            }
            // Old private-key encoded frames cannot be replayed with pairing-free LAN.
            if defaults.integer(forKey: "lanDefaultKeyVersion") != 1 {
                PendingSyncRepository.shared.clearAll()
                defaults.set(1, forKey: "lanDefaultKeyVersion")
            }
            PendingSyncRepository.shared.cleanOld(ttl: Self.pendingQueueTTL)
            self.startListening()
            self.startRelay()
            self.startPingTimer()
            self.startPathMonitoring()
            if PreferencesManager.shared.isSyncEnabled {
                // Authorized cache dial only — full /24 scan is user refresh.
                self.loadEndpointCache()
                self.scheduleDiscovery(immediate: true, scanFullSubnet: false)
            }
        }
    }

    func stop() {
        appLog("SyncManager v3 stopping...")
        scanStateLock.lock(); serviceGeneration &+= 1; scanStateLock.unlock()
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.relayClient?.stop(); self.relayClient = nil
            self.relayConnecting.removeAll()
            self.stopPathMonitoring()
            self.pingTimer?.cancel(); self.pingTimer = nil
            self.pendingDiscoveryWork?.cancel(); self.pendingDiscoveryWork = nil
            self.pendingReconnects.values.forEach { $0.cancel() }
            self.pendingReconnects.removeAll(); self.reconnectBackoffs.removeAll()
            for id in Array(self.sessions.keys) { self.closeSession(peerId: id, scheduleReconnect: false) }
            for (fd, client) in self.acceptingClients { client.source.cancel(); Darwin.close(fd) }
            self.acceptingClients.removeAll()
            self.stopListening()
            self.peersLock.lock(); self.discoveredPeers.removeAll(); self.peersLock.unlock()
            self.notifyPeersChanged()
        }
    }

    func restartService() {
        stop()
        syncQueue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
    }

    /// - Parameters:
    ///   - pruneCache: drop unauthorized ghosts from disk (user refresh button).
    ///   - scanFullSubnet: dial entire /24 (only user refresh).
    func refreshDiscovery(pruneCache: Bool = true, scanFullSubnet: Bool = true) {
        guard PreferencesManager.shared.isSyncEnabled, !isRefreshingDiscovery else { return }
        isRefreshingDiscovery = true
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.probeNetworkSessions()
            self.relayClient?.refreshPeers()
            let liveSessions = self.sessions
            var cached: [String: CachedEndpoint] = [:]
            for entry in self.loadEndpointCacheEntries() {
                cached[entry.peerId] = entry
            }
            self.peersLock.lock()
            var kept: [String: DiscoveredPeer] = [:]
            for (id, session) in liveSessions {
                if let existing = self.discoveredPeers[id] { kept[id] = existing }
                else {
                    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(session.host), port: NWEndpoint.Port(rawValue: session.port) ?? 5566)
                    kept[id] = DiscoveredPeer(peerId: id, displayName: cached[id]?.name ?? id, endpoint: endpoint, host: session.host, port: session.port)
                }
            }
            self.discoveredPeers = kept
            let keptList = Array(kept.values)
            self.peersLock.unlock()
            if pruneCache {
                self.rewriteEndpointCacheAfterRefresh(livePeers: keptList)
            }
            self.notifyPeersChanged()
            self.scheduleDiscovery(immediate: true, scanFullSubnet: scanFullSubnet)
            self.syncQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.isRefreshingDiscovery = false }
        }
    }

    func triggerCrossBandDiscovery() {
        guard PreferencesManager.shared.isSyncEnabled else { return }
        scheduleDiscovery(immediate: false, scanFullSubnet: false)
    }

    /// Counts a failed proactive dial to an authorized peer (its cached
    /// address is dead — typically the peer moved to a new DHCP lease) and,
    /// once the streak trips the threshold and the cooldown has elapsed,
    /// falls back to a full /24 scan so the peer is re-found without a manual
    /// refresh.
    func noteAuthorizedDialFailure(peerId: String?) {
        guard let peerId, !peerId.isEmpty,
              Set(PreferencesManager.shared.authorizedPeerIds).contains(peerId) else { return }
        var shouldScan = false
        selfHealLock.lock()
        authorizedDialFailStreak += 1
        let streak = authorizedDialFailStreak
        if streak >= Self.autoRediscoverFailThreshold {
            let last = lastAutoRediscoverAt
            if last == nil || Date().timeIntervalSince(last!) >= Self.autoRediscoverCooldown {
                lastAutoRediscoverAt = Date()
                shouldScan = true
            }
        }
        selfHealLock.unlock()
        guard shouldScan else { return }
        appLog("Auto rediscover: \(streak) consecutive authorized dial failures — scanning /24 for missing peers")
        scheduleDiscovery(immediate: true, scanFullSubnet: true)
    }

    func noteSessionEstablished() {
        selfHealLock.lock()
        authorizedDialFailStreak = 0
        selfHealLock.unlock()
    }

    // MARK: - Public queries

    struct SavedDeviceRecord: Codable {
        let peerId: String
        var displayName: String
        var host: String
        var port: UInt16
        var lastSeen: TimeInterval
    }

    private static let savedDevicesKey = "techuboard_saved_devices_v1"

    func loadSavedDevices() -> [SavedDeviceRecord] {
        if let data = UserDefaults.standard.data(forKey: Self.savedDevicesKey),
           let list = try? JSONDecoder().decode([SavedDeviceRecord].self, from: data) {
            return list
        }
        let auth = Set(PreferencesManager.shared.authorizedPeerIds)
        let cached = loadEndpointCacheEntries().filter { auth.contains($0.peerId) && $0.peerId != peerId }
        return cached.map {
            SavedDeviceRecord(peerId: $0.peerId, displayName: $0.name, host: $0.host, port: $0.port, lastSeen: $0.ts)
        }
    }

    func savePairedDevice(peerId: String, name: String, host: String, port: UInt16) {
        guard !peerId.isEmpty, peerId != self.peerId else { return }
        var list = loadSavedDevices()
        list.removeAll { $0.peerId == peerId }
        list.append(SavedDeviceRecord(peerId: peerId, displayName: name, host: host, port: port, lastSeen: Date().timeIntervalSince1970))
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.savedDevicesKey)
        }
        var auth = Set(PreferencesManager.shared.authorizedPeerIds)
        if !auth.contains(peerId) {
            auth.insert(peerId)
            PreferencesManager.shared.authorizedPeerIds = Array(auth).sorted()
        }
        notifyPeersChanged()
    }

    func removeSavedDevice(peerId: String) {
        var list = loadSavedDevices()
        list.removeAll { $0.peerId == peerId }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.savedDevicesKey)
        }
        var auth = Set(PreferencesManager.shared.authorizedPeerIds)
        auth.remove(peerId)
        PreferencesManager.shared.authorizedPeerIds = Array(auth).sorted()
        peersLock.lock()
        discoveredPeers.removeValue(forKey: peerId)
        peersLock.unlock()
        syncQueue.async { [weak self] in
            self?.closeSession(peerId: peerId, scheduleReconnect: false)
        }
        notifyPeersChanged()
    }

    func reconnectDevice(peerId: String) {
        guard let saved = loadSavedDevices().first(where: { $0.peerId == peerId }) else { return }
        dial(host: saved.host, port: saved.port, reason: "direct", peerId: saved.peerId)
        scheduleDiscovery(immediate: true, scanFullSubnet: true)
    }

    var availablePeers: [DiscoveredPeer] {
        peersLock.lock(); defer { peersLock.unlock() }
        return discoveredPeers.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    var availableDeviceNames: [String] { availablePeers.map(\.displayName) }
    var availableDeviceEntries: [DeviceEntry] {
        let peers = availablePeers
        let counts = peers.reduce(into: [String: Int]()) { $0[$1.displayName, default: 0] += 1 }
        var entries: [DeviceEntry] = peers.map {
            DeviceEntry(
                displayName: (counts[$0.displayName] ?? 0) > 1 ? "\($0.displayName) (\($0.peerId.prefix(6)))" : $0.displayName,
                peerId: $0.peerId,
                originalName: $0.displayName,
                host: $0.host,
                port: $0.port,
                isOnline: true,
                lastSeen: Date()
            )
        }
        let onlineIds = Set(peers.map(\.peerId))
        let savedList = loadSavedDevices()
        for s in savedList where !onlineIds.contains(s.peerId) && s.peerId != peerId {
            entries.append(
                DeviceEntry(
                    displayName: s.displayName,
                    peerId: s.peerId,
                    originalName: s.displayName,
                    host: s.host,
                    port: s.port,
                    isOnline: false,
                    lastSeen: Date(timeIntervalSince1970: s.lastSeen)
                )
            )
        }
        return entries
    }
    func enumerateLocalIPv4s() -> [String] { Self.localIPv4Addresses() }

    // MARK: - Broadcast APIs

    func broadcastSync(content: String, hash: String) {
        guard PreferencesManager.shared.isSyncEnabled else { appLog("broadcastSync skipped: sync disabled", level: .warning); return }
        guard let payload = encrypt(content) else { appLog("broadcastSync skipped: encryption failed", level: .warning); return }
        let env = SyncEnvelope.make(type: SyncType.history, peerId: peerId, name: displayName, hash: hash, payload: payload)
        appLog("broadcastSync: history hash \(hash.prefix(8)) to \(clipboardAuthIds()) auth peer(s)")
        fanoutReliable(env, requireAuth: true)
    }

    func broadcastImageSync(data: Data, hash: String) {
        guard PreferencesManager.shared.isSyncEnabled else { appLog("broadcastImageSync skipped: sync disabled", level: .warning); return }
        let prepared = prepareImageForSync(data)
        let base64 = prepared.base64EncodedString()
        guard let payload = encrypt(base64) else { appLog("broadcastImageSync skipped: encryption failed", level: .warning); return }
        let env = SyncEnvelope.make(type: SyncType.historyImage, peerId: peerId, name: displayName, hash: hash, payload: payload)
        appLog("broadcastImageSync: image hash \(hash.prefix(8)) (\(prepared.count / 1024)KB) to \(clipboardAuthIds()) auth peer(s)")
        fanoutReliable(env, requireAuth: true)
    }

    func broadcastFileSync(urls: [URL], hash: String) {
        guard PreferencesManager.shared.isSyncEnabled else { return }
        guard let first = urls.first else { return }
        let fileName = first.lastPathComponent
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: first.path),
              let size = attrs[.size] as? Int64 else { return }

        // If file is <= 1.2MB, embed directly into reliable history.file frame
        if size <= 1_200_000, let data = try? Data(contentsOf: first) {
            let meta: [String: Any] = [
                "fileName": fileName,
                "fileSize": Int(size),
                "sha256": hash,
                "base64": data.base64EncodedString()
            ]
            if let json = try? JSONSerialization.data(withJSONObject: meta),
               let jsonStr = String(data: json, encoding: .utf8),
               let payload = encrypt(jsonStr) {
                let env = SyncEnvelope.make(type: SyncType.historyFile, peerId: peerId, name: displayName, hash: hash, payload: payload)
                appLog("broadcastFileSync: small document/file \(fileName) (\(size / 1024)KB) to \(clipboardAuthIds()) peers")
                fanoutReliable(env, requireAuth: true)
                return
            }
        }

        // For larger files, trigger chunked transfer to authenticated peers
        for peer in availablePeers where clipboardAuthIds().contains(peer.peerId) {
            appLog("broadcastFileSync: chunked transfer of \(fileName) (\(size / 1024)KB) to \(peer.displayName)")
            sendFileToPeer(at: first, peerId: peer.peerId)
        }
    }

    private func prepareImageForSync(_ data: Data) -> Data {
        if data.count <= 750_000 { return data }
        guard let image = NSImage(data: data) else { return data }
        let maxDim: CGFloat = 1280
        let size = image.size
        guard size.width > 0, size.height > 0 else { return data }
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        let newSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let target = NSImage(size: newSize)
        target.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        target.unlockFocus()
        
        var quality: CGFloat = 0.80
        while quality >= 0.40 {
            if let tiff = target.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
                if jpg.count <= 750_000 || quality <= 0.45 {
                    return jpg
                }
            }
            quality -= 0.15
        }
        return data
    }

    func broadcastNotificationMessage(type: String, content: String, hash: String) {
        let mapped = mapNotificationType(type)
        guard mapped != nil || type.hasPrefix("notif.") else { appLog("Unknown notification type: \(type)", level: .warning); return }
        guard let payload = encrypt(content) else { return }
        fanoutReliable(SyncEnvelope.make(type: mapped ?? type, peerId: peerId, name: displayName, hash: hash.isEmpty ? nil : hash, payload: payload), requireAuth: true, allowWithoutClipboardSync: true)
    }

    func sendNotificationAck(hash: String, to senderPeerId: String) {
        guard !hash.isEmpty, !senderPeerId.isEmpty else { return }
        sendEnvelope(SyncEnvelope.make(type: SyncType.notifAck, peerId: peerId, hash: hash), to: senderPeerId, reliable: false)
    }

    func sendTextToPeer(_ content: String, hash: String, peerId targetId: String, completion: ((Bool) -> Void)? = nil) {
        guard PreferencesManager.shared.isSyncEnabled, let payload = encrypt(content) else { completion?(false); return }
        // Device-list send: history.direct bypasses mutual authorization on both ends.
        sendEnvelope(
            SyncEnvelope.make(type: SyncType.historyDirect, peerId: peerId, name: displayName, hash: hash, payload: payload),
            to: targetId,
            reliable: true,
            dialReason: "direct",
            completion: completion
        )
    }

    func sendText(_ content: String, hash: String, toDevice targetName: String) {
        guard let peer = availablePeers.first(where: { $0.displayName == targetName }) else { return }
        sendTextToPeer(content, hash: hash, peerId: peer.peerId)
    }
    // File transfer lives in SyncFileTransfer.swift:
    // sendFileToPeer(at:peerId:completion:) / sendFile(at:toDevice:).

    func mapNotificationType(_ apiType: String) -> String? {
        switch apiType {
        case "notification/post": return SyncType.notifPost
        case "notification/dismiss": return SyncType.notifDismiss
        case "notification/clear_all": return SyncType.notifClear
        case "notification/ack": return SyncType.notifAck
        case "notification/config": return SyncType.notifConfig
        default: return nil
        }
    }

    // MARK: - Business dispatch

    func handleFrame(_ data: Data, from remotePeerId: String, host: String) {
        guard let env = decodeEnvelope(data), env.v == SyncEnvelope.version else {
            diagnostics.noteError(peerId: remotePeerId, "badEnvelope")
            return
        }
        if env.type != SyncType.ping && env.type != SyncType.pong { diagnostics.noteReceived(peerId: remotePeerId) }
        switch env.type {
        case SyncType.ping:
            let pong = SyncEnvelope.make(type: SyncType.pong, peerId: peerId)
            if let data = encodeFrame(pong), let fd = sessions[remotePeerId]?.fd, !sendSessionFrame(fd, data) { appLog("pong send failed to \(remotePeerId.prefix(8))", level: .warning) }
        case SyncType.pong:
            if var session = sessions[remotePeerId] { session.lastPong = Date(); sessions[remotePeerId] = session }
        case SyncType.ack, SyncType.notifAck:
            guard let hash = env.hash else { return }; handleAck(hash: hash, from: remotePeerId)
        case SyncType.history, SyncType.historyDirect:
            // Inbound accept is unilateral: sender's allow-list gates who they push to;
            // receiver does not require reciprocal authorization (same as notifications).
            guard let text = decryptPayload(env, from: remotePeerId) else { return }
            DispatchQueue.main.async { [weak self] in
                ClipboardManager.shared.handleRemoteSync(content: text, hash: env.hash ?? "")
                self?.syncQueue.async { self?.replyAck(to: remotePeerId, hash: env.hash) }
            }
        case SyncType.historyImage:
            guard let base64 = decryptPayload(env, from: remotePeerId),
                  let data = Data(base64Encoded: base64) else { return }
            DispatchQueue.main.async { [weak self] in
                ClipboardManager.shared.handleRemoteImageSync(data: data, hash: env.hash ?? "")
                self?.syncQueue.async { self?.replyAck(to: remotePeerId, hash: env.hash) }
            }
        case SyncType.historyFile:
            guard let jsonStr = decryptPayload(env, from: remotePeerId),
                  let jsonData = jsonStr.data(using: .utf8),
                  let map = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let fileName = map["fileName"] as? String,
                  let b64 = map["base64"] as? String,
                  let fileData = Data(base64Encoded: b64) else { return }
            DispatchQueue.main.async { [weak self] in
                let destDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let fileUrl = destDir.appendingPathComponent(fileName)
                try? fileData.write(to: fileUrl)
                ClipboardManager.shared.handleRemoteFileSync(url: fileUrl, senderName: env.name ?? "Remote Device")
                self?.syncQueue.async { self?.replyAck(to: remotePeerId, hash: env.hash) }
            }
        case SyncType.historyFetch:
            // Responding = sending our history: only to clipboard-authorized peers.
            guard clipboardAuthIds().contains(remotePeerId) else {
                appLog("history.fetch from \(remotePeerId.prefix(8)) ignored (not a clipboard sync target)", level: .warning)
                return
            }
            respondToHistoryFetch(from: remotePeerId)
        case SyncType.snippetsFetch:
            respondToSnippetsFetch(from: remotePeerId)
        case SyncType.snippetsSync:
            guard let text = decryptPayload(env, from: remotePeerId) else { return }
            handleRemoteSnippetsSync(text)
        case SyncType.notifPost:
            guard let text = decryptPayload(env, from: remotePeerId) else { return }
            DispatchQueue.main.async { NotificationManager.shared.handleRemoteNotification(text, from: env.peerId) }
        case SyncType.notifDismiss:
            guard let text = decryptPayload(env, from: remotePeerId) else { return }
            DispatchQueue.main.async { NotificationManager.shared.handleRemoteDismiss(text) }
        case SyncType.notifClear:
            DispatchQueue.main.async { NotificationManager.shared.handleRemoteClearAll() }
        case SyncType.notifConfig: appLog("Ignored remote notification config", level: .warning)
        case SyncType.fileMeta:
            handleFileMeta(env, from: remotePeerId)
        case SyncType.fileChunk:
            handleFileChunk(env, from: remotePeerId)
        case SyncType.fileAck:
            handleFileAck(env, from: remotePeerId)
        case SyncType.hello, SyncType.welcome:
            if let name = env.name, let port = env.port { recordPeer(peerId: env.peerId, name: name, host: host, port: UInt16(port)) }
        default: break
        }
    }

    /// Decrypts a business payload; a failure here with a verified handshake
    /// means corrupted data or a peer that changed secrets mid-session.
    func decryptPayload(_ env: SyncEnvelope, from remotePeerId: String) -> String? {
        guard let payload = env.payload else { return nil }
        guard let text = decrypt(payload) else {
            appLog("Decrypt failed for \(env.type) from \(remotePeerId.prefix(8))", level: .warning)
            diagnostics.noteError(peerId: remotePeerId, "decryptFailed")
            return nil
        }
        return text
    }

    func respondToHistoryFetch(from remotePeerId: String) {
        syncQueue.async { [weak self] in
            guard let self else { return }
            if let last = self.lastHistoryFetchResponse[remotePeerId],
               Date().timeIntervalSince(last) < Self.historyFetchThrottle {
                appLog("history.fetch from \(remotePeerId.prefix(8)) ignored (throttled)")
                return
            }
            self.lastHistoryFetchResponse[remotePeerId] = Date()
            self.sessions[remotePeerId]?.historyReplayRows = HistoryRepository.shared.recentTextRowids(limit: 200)
            self.pumpHistoryReplay(for: remotePeerId)
            // Also push snippets upon history fetch
            self.respondToSnippetsFetch(from: remotePeerId)
        }
    }

    func respondToSnippetsFetch(from remotePeerId: String) {
        syncQueue.async { [weak self] in
            guard let self else { return }
            guard let jsonStr = SnippetManager.shared.exportJSONPayload() else { return }
            guard let encrypted = self.encrypt(jsonStr) else { return }
            let env = SyncEnvelope.make(
                type: SyncType.snippetsSync,
                peerId: self.peerId,
                name: self.displayName,
                port: Int(self.syncPort),
                payload: encrypted
            )
            guard let frame = self.encodeFrame(env) else { return }
            _ = self.sessions[remotePeerId]?.writer?.enqueue(frame)
        }
    }

    func handleRemoteSnippetsSync(_ jsonStr: String) {
        guard let data = jsonStr.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        DispatchQueue.main.async {
            let changed = SnippetManager.shared.mergeRemoteFolders(list)
            if changed {
                appLog("Snippets merged from remote device")
            }
        }
    }

    func broadcastSnippets() {
        syncQueue.async { [weak self] in
            guard let self else { return }
            guard let jsonStr = SnippetManager.shared.exportJSONPayload() else { return }
            guard let encrypted = self.encrypt(jsonStr) else { return }
            let env = SyncEnvelope.make(
                type: SyncType.snippetsSync,
                peerId: self.peerId,
                name: self.displayName,
                port: Int(self.syncPort),
                payload: encrypted
            )
            guard let frame = self.encodeFrame(env) else { return }
            for session in self.sessions.values {
                _ = session.writer?.enqueue(frame)
            }
        }
    }

    /// Keep row ids only. Resolve/encode one replay frame when the FIFO drains,
    /// rather than retaining up to 200 full (possibly externalized) texts.
    func pumpHistoryReplay(for peerId: String) {
        guard var session = sessions[peerId], let writer = session.writer else { return }
        while !session.historyReplayRows.isEmpty {
            let rowid = session.historyReplayRows.removeFirst()
            sessions[peerId]?.historyReplayRows = session.historyReplayRows
            guard let entry = HistoryRepository.shared.fetchByRowid(rowid) else { continue }
            let frame: Data?
            if case .image(let path) = entry.item,
               let data = HistoryMediaStore.shared.data(at: path) {
                let prepared = prepareImageForSync(data)
                let base64 = prepared.base64EncodedString()
                if let payload = encrypt(base64) {
                    frame = encodeFrame(SyncEnvelope.make(type: SyncType.historyImage,
                        peerId: self.peerId, name: displayName, port: Int(syncPort),
                        hash: entry.contentHash ?? "", payload: payload))
                } else { frame = nil }
            } else if let text = entry.resolvedText, let payload = encrypt(text) {
                frame = encodeFrame(SyncEnvelope.make(type: SyncType.history,
                    peerId: self.peerId, name: displayName, port: Int(syncPort),
                    hash: entry.contentHash ?? "", payload: payload))
            } else {
                continue
            }
            guard let validFrame = frame else { continue }
            if !writer.enqueue(validFrame) {
                sessions[peerId]?.historyReplayRows.insert(rowid, at: 0)
            }
            return
        }
    }

    // MARK: - Keepalive / path

    func startPingTimer() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: syncQueue)
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in self?.sendPings() }
        pingTimer = timer; timer.resume()
    }
    func sendPings() {
        guard let data = encodeFrame(SyncEnvelope.make(type: SyncType.ping, peerId: peerId)) else { return }
        let cutoff = Date().addingTimeInterval(-Self.pingInterval * 3)
        for id in Array(sessions.keys) {
            guard let session = sessions[id] else { continue }
            if session.lastPong < cutoff { closeSession(peerId: id, scheduleReconnect: true, keepaliveDriven: true); continue }
            if !sendSessionFrame(session.fd, data) { appLog("ping send failed to \(id.prefix(8))", level: .warning) }
            retryStalePendingHistory(for: id)
        }
    }
    func startPathMonitoring() {
        stopPathMonitoring()
        let monitor = NWPathMonitor(); pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard let self, let monitor else { return }
            guard self.pathMonitor === monitor else { return }
            let signature = "\(path.status)|" + path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map { "\($0.name):\($0.index)" }.sorted().joined(separator:",")
            let changed = self.lastPathSignature != nil && self.lastPathSignature != signature
            self.lastPathSignature = signature
            if path.status == .satisfied && changed {
                appLog("Network path changed; probing sessions and reconnecting relay")
                self.probeNetworkSessions()
                self.restartRelayConfiguration()
                self.loadEndpointCache()
                self.scheduleDiscovery(immediate: true, scanFullSubnet: false)
            }
        }
        monitor.start(queue: syncQueue)
    }
    func stopPathMonitoring() {
        pathMonitor?.cancel(); pathMonitor = nil; lastPathSignature = nil
        networkProbe?.cancel(); networkProbe = nil
    }
    /// One bounded check per network event/Scan burst; fresh pongs keep healthy LAN sessions.
    func probeNetworkSessions(delay: TimeInterval = 3) {
        guard networkProbe == nil else { return }
        let generation = currentGeneration
        let captured = sessions
        sendPings()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.networkProbe = nil
            guard generation == self.currentGeneration else { return }
            for (id, old) in captured {
                guard let current = self.sessions[id],
                    current.fd == old.fd, current.readSource === old.readSource,
                    current.lastPong <= old.lastPong else { continue }
                self.closeSession(peerId:id,scheduleReconnect:true)
            }
            self.relayClient?.refreshPeers()
        }
        networkProbe = work
        syncQueue.asyncAfter(deadline:.now()+delay,execute:work)
    }

    func notifyPeersChanged() {
        let peers = availablePeers, names = peers.map(\.displayName)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onDevicesChanged?(names); self.onPeersChanged?(peers)
            NotificationCenter.default.post(name: .syncAvailableDevicesDidChange, object: self, userInfo: ["devices": names, "peers": peers])
        }
    }
}

extension Notification.Name {
    static let syncAvailableDevicesDidChange = Notification.Name("SyncAvailableDevicesDidChange")
}
