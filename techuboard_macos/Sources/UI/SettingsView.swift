import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var languageObserver: AppLanguageObserver
  @State private var selectedSettingsPage = "general"
  @State private var selectedLanguage: AppLanguage
  @State private var launchAtLogin: Bool
  @State private var deviceName: String
  @FocusState private var deviceNameFocused: Bool
  @State private var historyLimit: Int
  @State private var historyLimitText: String
  @FocusState private var historyLimitFocused: Bool
  @State private var currentHistoryCount: Int
  @State private var historyRetentionDays: Int
  @State private var historyEncryptionEnabled: Bool
  @State private var historyImageOCRIndexing: Bool
  @State private var imageAutoDeleteEnabled: Bool
  @State private var imageThresholdOption: Int
  @State private var imageThresholdCustom: Int
  @State private var searchGlobalShortcutEnabled: Bool
  @State private var searchHistoryShortcut: ShortcutCombo?
  @State private var wordShortcutEnabled: Bool
  @State private var wordLookupShortcut: ShortcutCombo?
  @State private var wordShortcutFailed = false
  @State private var syncEnabled: Bool
  @State private var syncPort: String
  @State private var autoImageSync: Bool
  @State private var availablePeers: [DiscoveredPeer] = []
  @State private var clipboardSyncTargets: Set<String> = Set(
    PreferencesManager.shared.clipboardSyncPeerIds)
  @State private var notificationSyncTargets: Set<String> = Set(
    PreferencesManager.shared.notificationSyncPeerIds)
  @State private var isRefreshingDevices = false
  @ObservedObject private var relayGroups = SyncRelayGroups.shared
  @State private var showEnterPhoneCode = false
  @State private var phoneCodeInput = ""
  @State private var copiedPairingCode = false
  @State private var copiedDownloadLink = false
  @State private var showPairingSection = false
  @State private var isReencryptingHistory = false

  init() {
    let prefs = PreferencesManager.shared
    _selectedLanguage = State(initialValue: prefs.appLanguage)
    _launchAtLogin = State(initialValue: LaunchAtLoginManager.isEnabled)
    _deviceName = State(initialValue: prefs.deviceName)
    let limit = prefs.historyLimit
    _historyLimit = State(initialValue: limit)
    _historyLimitText = State(initialValue: "\(limit)")
    _currentHistoryCount = State(initialValue: ClipboardManager.shared.totalHistoryCount)
    _historyRetentionDays = State(initialValue: prefs.historyRetentionDays)
    _historyEncryptionEnabled = State(initialValue: prefs.isHistoryEncryptionEnabled)
    _historyImageOCRIndexing = State(initialValue: prefs.isHistoryImageOCRIndexingEnabled)
    let autoDel = prefs.isImageAutoDeleteEnabled
    let thresh = prefs.imageAutoDeleteThreshold
    _imageAutoDeleteEnabled = State(initialValue: autoDel)
    _imageThresholdCustom = State(initialValue: thresh)
    _imageThresholdOption = State(initialValue: [10, 20, 30, 40].contains(thresh) ? thresh : -1)
    _searchGlobalShortcutEnabled = State(initialValue: prefs.isSearchGlobalShortcutEnabled)
    _searchHistoryShortcut = State(initialValue: prefs.searchHistoryShortcut)
    _wordShortcutEnabled = State(initialValue: prefs.isWordShortcutEnabled)
    _wordLookupShortcut = State(initialValue: prefs.wordLookupShortcut)
    _syncEnabled = State(initialValue: prefs.isSyncEnabled)
    _syncPort = State(initialValue: "\(prefs.syncPort)")
    _autoImageSync = State(initialValue: prefs.isAutoImageSyncEnabled)
  }

  private var settingsPages: [AppSettingsPage] {
    [
      .init(id: "general", title: L10n.t(.designGeneral), symbol: "gearshape"),
      .init(id: "banglaKeyboard", title: "বাংলা কীবোর্ড", symbol: "character.textbox"),
      .init(id: "sync", title: L10n.t(.lanDevices), symbol: "arrow.triangle.2.circlepath"),
      .init(id: "shortcuts", title: L10n.t(.shortcut), symbol: "keyboard"),
      .init(id: "permissions", title: L10n.t(.designPermissions), symbol: "hand.raised"),
      .init(id: "about", title: L10n.t(.settingsAbout), symbol: "info.circle"),
    ]
  }

  /// Retention choices in days; 0 keeps history forever.
  private static let retentionOptions = [0, 7, 30, 90, 365]

  var body: some View {
    let _ = languageObserver.revision

    AppSettingsLayout(selection: $selectedSettingsPage, pages: settingsPages) { pageID in

      if pageID == "general" {
        Section(L10n.t(.designGeneral)) {
          Picker(L10n.t(.language), selection: $selectedLanguage) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
              Text(language.displayName).tag(language)
            }
          }
          .onChange(of: selectedLanguage) { newValue in
            PreferencesManager.shared.appLanguage = newValue
          }

          Toggle(L10n.t(.launchAtLogin), isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
              do {
                try LaunchAtLoginManager.setEnabled(newValue)
              } catch {
                launchAtLogin = !newValue
                AlertPresenter.showWarning(
                  title: L10n.t(.launchAtLoginFailed),
                  message: error.localizedDescription
                )
              }
            }

          TextField(L10n.t(.designDeviceName), text: $deviceName)
            .focused($deviceNameFocused)
            .onSubmit { saveDeviceName() }
            .onChange(of: deviceNameFocused) { focused in
              if !focused { saveDeviceName() }
            }
        }

        Section(L10n.t(.history)) {
          HStack {
            Text(L10n.t(.historyLimit))
            TextField("", text: $historyLimitText)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
              .focused($historyLimitFocused)
              .onSubmit {
                commitHistoryLimitText()
              }
            Stepper("", value: $historyLimit, in: Self.historyLimitRange, step: 100)
              .labelsHidden()
          }
          .onChange(of: historyLimit) { newValue in
            let text = "\(newValue)"
            if historyLimitText != text {
              historyLimitText = text
            }
            saveHistoryLimit(newValue)
          }
          .onChange(of: historyLimitFocused) { focused in
            if !focused {
              commitHistoryLimitText()
            }
          }

          Toggle("স্বয়ংক্রিয় পুরানো ছবি অটো-ক্লিনআপ (Auto Image Cleanup)", isOn: $imageAutoDeleteEnabled)
            .onChange(of: imageAutoDeleteEnabled) { newValue in
              PreferencesManager.shared.isImageAutoDeleteEnabled = newValue
              if newValue {
                ClipboardManager.shared.applyImageAutoDeleteLimit()
              }
            }

          HStack {
            Text(L10n.format(.historyLimitCaption, currentHistoryCount))
              .font(AppFont.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
              AlertPresenter.confirm(
                title: "ক্লিপবোর্ড হিস্ট্রি মুছবেন?",
                message: "আপনার বর্তমান হিস্ট্রি মুছে ফেলা হবে। পিন করা আইটেম এবং নোট সুরক্ষিত থাকবে।",
                confirmTitle: "মুছে ফেলুন"
              ) {
                ClipboardManager.shared.clearHistory()
                currentHistoryCount = 0
              }
            } label: {
              Text("হিস্ট্রি পরিষ্কার করুন")
            }
          }
        }
      }
      if pageID == "shortcuts" {
        Section(L10n.t(.searchGlobalShortcut)) {
          Toggle(L10n.t(.searchGlobalShortcut), isOn: $searchGlobalShortcutEnabled)
            .onChange(of: searchGlobalShortcutEnabled) { newValue in
              PreferencesManager.shared.isSearchGlobalShortcutEnabled = newValue
              SearchGlobalHotKeyManager.register()
            }
          ShortcutRecorderRepresentable(combo: $searchHistoryShortcut) { combo in
            PreferencesManager.shared.searchHistoryShortcut = combo
            SearchGlobalHotKeyManager.register()
          }
          .frame(height: 30)
          Text(L10n.t(.searchGlobalShortcutDescription))
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
        }
        Section(L10n.t(.wordLookup)) {
          Toggle(L10n.t(.wordShortcut), isOn: $wordShortcutEnabled)
            .onChange(of: wordShortcutEnabled) { value in
              PreferencesManager.shared.isWordShortcutEnabled = value
              wordShortcutFailed = !WordGlobalHotKeyManager.register()
            }
          ShortcutRecorderRepresentable(combo: $wordLookupShortcut) { combo in
            PreferencesManager.shared.wordLookupShortcut = combo
            wordShortcutFailed = !WordGlobalHotKeyManager.register()
          }
          .frame(height: 30)
          Text(L10n.t(.wordShortcutDescription)).font(AppFont.caption).foregroundStyle(
            .secondary)
          if wordShortcutFailed {
            Text(L10n.t(.wordShortcutConflict)).font(AppFont.caption).foregroundStyle(.orange)
          }
        }
      }
      if pageID == "sync" {
        Section("স্বয়ংক্রিয় সিঙ্ক (Auto Sync)") {
          Toggle("স্বয়ংক্রিয় ছবি ও ফাইল সিঙ্ক (Auto Image & File Sync)", isOn: $autoImageSync)
            .onChange(of: autoImageSync) { newValue in
              PreferencesManager.shared.isAutoImageSyncEnabled = newValue
            }
          Text("চালু থাকলে কপি করা ছবি, স্ক্রিনশট এবং ফাইল স্বয়ংক্রিয়ভাবে আপনার ফোনে সিঙ্ক হবে।")
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
        }

        Section("ডিভাইস সংযোগ ও সিঙ্ক (Device Connection & Sync)") {
          Toggle("ডিভাইস সিঙ্ক চালু রাখুন (Enable Sync)", isOn: $syncEnabled)
            .onChange(of: syncEnabled) { newValue in
              PreferencesManager.shared.isSyncEnabled = newValue
              if newValue {
                SyncManager.shared.start()
                ensureRelaySetup()
              } else {
                SyncManager.shared.stop()
              }
            }

          let remoteMembers = relayGroups.members.filter { ($0["device"] as? String) != relayGroups.device }
          let isConnected = !remoteMembers.isEmpty || !availablePeers.isEmpty

          if isConnected {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(remoteMembers.indices, id: \.self) { idx in
                let m = remoteMembers[idx]
                let devName = m["name"] as? String ?? "Android Phone"
                HStack(spacing: 12) {
                  Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(.blue)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(devName)
                      .fontWeight(.semibold)
                    HStack(spacing: 6) {
                      Circle().fill(Color.green).frame(width: 8, height: 8)
                      Text("কানেক্টেড · লাইভ সিঙ্ক চালু")
                        .font(AppFont.caption)
                        .foregroundStyle(.green)
                    }
                  }
                  Spacer()
                  Button(role: .destructive) {
                    relayGroups.perform {
                      try await relayGroups.exitGroup(disband: false)
                    }
                  } label: {
                    Text("ডিসকানেক্ট")
                  }
                  .buttonStyle(.bordered)
                  .controlSize(.small)
                }
                .padding(12)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
              }

              ForEach(availablePeers, id: \.peerId) { peer in
                if !remoteMembers.contains(where: { ($0["device"] as? String) == peer.peerId }) {
                  HStack(spacing: 12) {
                    Image(systemName: peer.displayName.lowercased().contains("phone") || peer.displayName.lowercased().contains("android") ? "iphone" : "laptopcomputer")
                      .font(.title2)
                      .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(peer.displayName)
                        .fontWeight(.semibold)
                      HStack(spacing: 6) {
                        Circle().fill(peer.isOnline ? Color.green : Color.secondary).frame(width: 8, height: 8)
                        Text(peer.isOnline ? "অনলাইন · লাইভ সিঙ্ক চালু" : "অফলাইন")
                          .font(AppFont.caption)
                          .foregroundStyle(peer.isOnline ? .green : .secondary)
                      }
                    }
                    Spacer()
                  }
                  .padding(12)
                  .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
              }

              Button {
                showPairingSection.toggle()
              } label: {
                Label(showPairingSection ? "পেয়ারিং QR কোড লুকান" : "অন্য ডিভাইস যুক্ত করুন (Pair Another Device)", systemImage: "qrcode")
              }
              .buttonStyle(.link)
              .padding(.top, 4)
            }
          }

          if !isConnected || showPairingSection {
            VStack(alignment: .leading, spacing: 14) {
              Text("QR কোড বা পিন দিয়ে সহজে যুক্ত হোন")
                .font(.headline)
              Text("আপনার Android ফোনে Techuboard অ্যাপে 'Scan Mac QR Code' বাটনে ট্যাপ করে এই কোডটি স্ক্যান করুন:")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)

              if let inv = relayGroups.invitation,
                 let code = try? SyncRelayGroups.encode(inv),
                 let image = qrImage(for: code) {
                HStack(alignment: .center, spacing: 20) {
                  Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 170)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                  VStack(alignment: .leading, spacing: 12) {
                    Text("অথবা ৬-ডিজিটের কোড ব্যবহার করুন:")
                      .font(AppFont.caption)
                      .foregroundStyle(.secondary)

                    let pin = shortPin(from: inv)
                    HStack(spacing: 10) {
                      Text(pin)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                      Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        copiedPairingCode = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                          copiedPairingCode = false
                        }
                      } label: {
                        Image(systemName: copiedPairingCode ? "checkmark" : "doc.on.doc")
                      }
                      .buttonStyle(.bordered)
                      .help("কোড কপি করুন")
                    }

                    Button("ফোনের কোড দিয়ে যুক্ত হোন") {
                      showEnterPhoneCode = true
                    }
                    .buttonStyle(.link)
                  }
                }
              } else {
                HStack {
                  ProgressView().controlSize(.small)
                  Text("পেয়ারিং কোড প্রস্তুত হচ্ছে...")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
              }
            }
            .padding(14)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
          }
        }

        Section("Android অ্যাপ ডাউনলোড ও ইনস্টল (Download Android App)") {
          VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
              if let qr = qrImage(for: "https://github.com/Anzaar-riajul/Anzaar-engine-1.0/releases/latest/download/Techuboard-Android-v1.0.apk") {
                VStack(spacing: 8) {
                  Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                  Text("ক্যামেরা দিয়ে স্ক্যান করুন")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                }
              }

              VStack(alignment: .leading, spacing: 10) {
                Text("ফোনে Techuboard অ্যাপ নেই? এখনই ইনস্টল করুন")
                  .font(.headline)
                Text("আপনার Android ফোনের সাধারণ ক্যামেরা দিয়ে পাশের QR কোডটি স্ক্যান করলে সরাসরি APK ডাউনলোড করতে পারবেন। অথবা নিচের বিকল্পগুলো ব্যবহার করুন:")
                  .font(AppFont.caption)
                  .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                  Button {
                    if let url = Bundle.main.url(forResource: "Techuboard-Android", withExtension: "apk") {
                      NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else if let github = URL(string: "https://github.com/Anzaar-riajul/Anzaar-engine-1.0/releases/latest/download/Techuboard-Android-v1.0.apk") {
                      NSWorkspace.shared.open(github)
                    }
                  } label: {
                    Label("APK ফাইল দেখুন", systemImage: "arrow.down.doc")
                  }
                  .buttonStyle(.bordered)

                  Button {
                    if let url = Bundle.main.url(forResource: "Techuboard-Android", withExtension: "apk") {
                      let picker = NSSharingServicePicker(items: [url])
                      if let window = NSApp.keyWindow {
                        picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
                      }
                    } else if let github = URL(string: "https://github.com/Anzaar-riajul/Anzaar-engine-1.0/releases/latest/download/Techuboard-Android-v1.0.apk") {
                      NSWorkspace.shared.open(github)
                    }
                  } label: {
                    Label("AirDrop / শেয়ার করুন", systemImage: "square.and.arrow.up")
                  }
                  .buttonStyle(.borderedProminent)

                  Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://anzaar-riajul.github.io/Anzaar-engine-1.0/", forType: .string)
                    copiedDownloadLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                      copiedDownloadLink = false
                    }
                  } label: {
                    Label(copiedDownloadLink ? "লিঙ্ক কপি হয়েছে" : "লিঙ্ক কপি করুন", systemImage: copiedDownloadLink ? "checkmark" : "doc.on.doc")
                  }
                  .buttonStyle(.bordered)
                }
              }
            }
          }
          .padding(14)
          .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
      }
      if pageID == "banglaKeyboard" {
        BanglaKeyboardSettingsSection()
      }
      if pageID == "permissions" {
        Section(L10n.t(.designPermissions)) {
          let granted = AccessibilityManager.isTrusted
          HStack(spacing: AppSpacing.sm) {
            Circle()
              .fill(granted ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
            Text(L10n.t(.accessibilityPermission)).font(AppFont.body)
            Spacer(minLength: AppSpacing.sm)
            Text(granted ? L10n.t(.accessibilityGranted) : L10n.t(.accessibilityNotGranted))
              .font(AppFont.caption)
              .foregroundStyle(granted ? .green : .orange)
          }
          .contentShape(Rectangle())
          .onTapGesture {
            if granted {
              AccessibilityManager.openSettings()
            } else {
              AccessibilityManager.requestSystemPrompt()
              AccessibilityManager.openSettings()
            }
          }
          .help(L10n.t(.openSystemSettings))
        }
      }
      if pageID == "about" {
        Section {
          LabeledContent(L10n.t(.settingsVersion), value: AppVersion.displayString)
          HStack {
            Button(L10n.t(.showLogs)) { LogWindow.show() }
            Button(L10n.t(.openLogFolder)) {
              NSWorkspace.shared.open(LogManager.logDirectory)
            }
          }
          Text(L10n.t(.diagnosticsHint))
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
        }
      }

    }
    .frame(minWidth: AppWindowSize.settingsMin.width, minHeight: AppWindowSize.settingsMin.height)
    .onReceive(NotificationCenter.default.publisher(for: .syncAvailableDevicesDidChange)) {
      notification in
      if let peers = notification.userInfo?["peers"] as? [DiscoveredPeer] {
        availablePeers = peers
      } else if notification.userInfo?["devices"] is [String] {
        // Legacy name-only payload carries no peer objects; read the
        // manager's current list instead.
        availablePeers = SyncManager.shared.availablePeers
      }
    }
    .onAppear {
      availablePeers = SyncManager.shared.availablePeers
      clipboardSyncTargets = Set(PreferencesManager.shared.clipboardSyncPeerIds)
      notificationSyncTargets = Set(PreferencesManager.shared.notificationSyncPeerIds)
      for peer in availablePeers {
        PreferencesManager.shared.setClipboardSync(peerId: peer.peerId, enabled: true)
      }
      if PreferencesManager.shared.isSyncEnabled {
        SyncManager.shared.triggerCrossBandDiscovery()
        ensureRelaySetup()
      }
    }
    .sheet(isPresented: $showEnterPhoneCode) {
      VStack(alignment: .leading, spacing: 16) {
        Text("ফোনের পেয়ারিং কোড প্রবেশ করান")
          .font(.headline)
        Text("আপনার Android ফোনে Techuboard-এ 'Show My Phone QR / Code' থেকে পাওয়া কোডটি এখানে লিখুন বা পেস্ট করুন।")
          .font(AppFont.caption)
          .foregroundStyle(.secondary)
        TextField("যেমন: common-relay://... বা ৭৪৯ ২১৫", text: $phoneCodeInput)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("বাতিল") {
            showEnterPhoneCode = false
            phoneCodeInput = ""
          }
          .keyboardShortcut(.cancelAction)
          Spacer()
          Button("কানেক্ট করুন") {
            let code = phoneCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return }
            showEnterPhoneCode = false
            phoneCodeInput = ""
            relayGroups.perform {
              let macName = Host.current().localizedName ?? "Mac"
              try await relayGroups.join(text: code, name: macName)
            }
          }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
        }
      }
      .padding(20)
      .frame(width: 440)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      launchAtLogin = LaunchAtLoginManager.isEnabled
      currentHistoryCount = ClipboardManager.shared.totalHistoryCount
    }
    .onReceive(NotificationCenter.default.publisher(for: .clipboardHistoryDidChange)) { _ in
      currentHistoryCount = ClipboardManager.shared.totalHistoryCount
    }
  }

  private static let historyLimitRange = 1...100_000

  private struct AuthDeviceRow: Identifiable {
    var id: String { peerId }
    let peerId: String
    let displayName: String
    let hostPort: String?
    let isOnline: Bool
  }

  /// Authorized peers (always) ∪ currently discovered (for new checkboxes).
  private static func authDeviceRows(
    availablePeers: [DiscoveredPeer],
    clipboard: Set<String>,
    notification: Set<String>
  ) -> [AuthDeviceRow] {
    let onlineIds = Set(availablePeers.map(\.peerId))
    let ids = clipboard.union(notification).union(onlineIds)
    let sync = SyncManager.shared
    return ids.sorted().map { peerId in
      let online = availablePeers.first(where: { $0.peerId == peerId })
      return AuthDeviceRow(
        peerId: peerId,
        displayName: online?.displayName ?? sync.resolvedPeerLabel(peerId: peerId),
        hostPort: online.map { SyncEndpointDisplay.label(host: $0.host, port: $0.port) }
          ?? sync.resolvedPeerHostPort(peerId: peerId),
        isOnline: online != nil
      )
    }
  }

  private func commitHistoryLimitText() {
    let trimmed = historyLimitText.trimmingCharacters(in: .whitespaces)
    guard let limit = Int(trimmed), Self.historyLimitRange.contains(limit) else {
      historyLimitText = "\(historyLimit)"
      return
    }
    if historyLimit != limit {
      historyLimit = limit
    } else {
      historyLimitText = "\(limit)"
      saveHistoryLimit(limit)
    }
  }

  private func saveHistoryLimit(_ limit: Int) {
    PreferencesManager.shared.historyLimit = limit
    ClipboardManager.shared.applyHistoryLimit()
  }

  private static func isValidIPv4(_ string: String) -> Bool {
    let parts = string.split(separator: ".")
    guard parts.count == 4 else { return false }
    for part in parts {
      guard let value = Int(part), (0...255).contains(value) else { return false }
    }
    return true
  }

  private func saveDeviceName() {
    let newName = deviceName.trimmingCharacters(in: .whitespaces)
    guard !newName.isEmpty else {
      deviceName = PreferencesManager.shared.deviceName
      return
    }
    deviceName = newName
    guard newName != PreferencesManager.shared.deviceName else { return }
    PreferencesManager.shared.deviceName = newName
    SyncManager.shared.restartService()
  }

  private func qrImage(for text: String) -> NSImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let outputImage = filter.outputImage else { return nil }
    let transform = CGAffineTransform(scaleX: 8, y: 8)
    let scaled = outputImage.transformed(by: transform)
    let rep = NSCIImageRep(ciImage: scaled)
    let nsImage = NSImage(size: rep.size)
    nsImage.addRepresentation(rep)
    return nsImage
  }

  private func shortPin(from invitation: [String: Any]?) -> String {
    guard let inv = invitation, let id = inv["id"] as? String, id.count >= 6 else {
      return "749 215"
    }
    let hex = String(id.prefix(6))
    if let num = Int(hex, radix: 16) {
      let pin = (num % 900000) + 100000
      let s = "\(pin)"
      return "\(s.prefix(3)) \(s.suffix(3))"
    }
    return "749 215"
  }

  private func ensureRelaySetup() {
    relayGroups.perform {
      try await relayGroups.refresh()
      if !relayGroups.enrolled && !relayGroups.creationPending {
        let macName = Host.current().localizedName ?? "Mac"
        try await relayGroups.createGroup(title: "Techuboard", name: macName)
      }
      if relayGroups.invitation == nil && relayGroups.manager {
        relayGroups.automaticJoin = true
        try await relayGroups.createInvitation()
      }
      for m in relayGroups.members {
        if let devId = m["device"] as? String, devId != relayGroups.device {
          PreferencesManager.shared.setClipboardSync(peerId: devId, enabled: true)
        }
      }
      for peer in availablePeers {
        PreferencesManager.shared.setClipboardSync(peerId: peer.peerId, enabled: true)
      }
    }
  }
}

enum AlertPresenter {
  static func showInfo(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: L10n.t(.ok))
    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window, completionHandler: nil)
    } else {
      alert.runModal()
    }
  }

  static func showWarning(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.t(.ok))
    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window, completionHandler: nil)
    } else {
      alert.runModal()
    }
  }

  static func confirm(
    title: String, message: String, confirmTitle: String, onConfirm: @escaping () -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: confirmTitle)
    alert.addButton(withTitle: L10n.t(.cancel))
    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window) { response in
        if response == .alertFirstButtonReturn {
          onConfirm()
        }
      }
    } else if alert.runModal() == .alertFirstButtonReturn {
      onConfirm()
    }
  }
}
