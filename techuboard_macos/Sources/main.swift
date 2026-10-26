import AppKit

#if TECHUBOARD_CORE_TESTS
if CommandLine.arguments.contains("--techuboard-panel-snapshot") {
    runMenuBarPanelSnapshot()
} else if CommandLine.arguments.contains("--techuboard-token-snapshot") {
    runTokenUsageSnapshot()
} else if CommandLine.arguments.contains("--techuboard-overflow-fixture-menu") {
    runMenuBarOverflowFixture(popover: false)
} else if CommandLine.arguments.contains("--techuboard-overflow-fixture-popover") {
    runMenuBarOverflowFixture(popover: true)
} else if CommandLine.arguments.contains("--techuboard-overflow-live-tests") {
    runMenuBarOverflowLiveTests()
} else {
    runCoreRegressionTests()
}
#else
// OCR child mode must branch before any AppKit state exists: this same
// executable is re-invoked with a flag as a short-lived Vision worker, and
// must never build NSApplication.
if CommandLine.arguments.contains(OCRSubprocess.childModeArgument) {
    OCRSubprocess.runChildMode()
}

// Local, explicit administration; credentials are read from a private file, never command arguments.
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--relay-device-id" {
    print(SyncRelaySettings.deviceID)
    exit(0)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--relay-import" {
    do {
        let path = CommandLine.arguments[2]
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0,
              (attributes[.size] as? NSNumber)?.intValue ?? 65537 <= 65536 else {
            throw NSError(domain: "SyncRelay", code: 1)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let raw = String(decoding: data, as: UTF8.self)
        guard let _ = SyncRelayClient.Access.parse(raw),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["url"] as? String else { throw NSError(domain: "SyncRelay", code: 2) }
        try SyncRelaySettings.save(enabled: true, url: url, token: raw)
        UserDefaults.standard.synchronize()
        print("Relay configuration imported; restart Techuboard to connect.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Relay import failed; verify private file permissions and device configuration.\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
#endif

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuController: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogManager.shared.startSession()
        CrashReporter.install()
        SystemNotificationRouter.shared.install()
        setupMainMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
        menuController = MenuController()
        SmartSwitchVoiceRouter.shared.start()
        MemoryFootprintReclaimer.registerIdleHandlers()
        LaunchAtLoginManager.syncWithPreference()
        SyncManager.shared.start()
        DispatchQueue.main.async {
            SyncRelayGroups.shared.ensureReady()
            MacAppUpdater.shared.start()
        }
        print("Techuboard started!")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { menuController?.showControlPanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeManager.shared.stop()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: L10n.t(.quitTechuboard),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: L10n.t(.editMenu))
        editMenu.addItem(NSMenuItem(title: L10n.t(.undo), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: L10n.t(.redo), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: L10n.t(.cut), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L10n.t(.copy), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L10n.t(.paste), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L10n.t(.selectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func languageDidChange() {
        setupMainMenu()
    }
}

#if !TECHUBOARD_CORE_TESTS
app.run()
#endif
