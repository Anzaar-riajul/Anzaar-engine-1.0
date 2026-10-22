// TechuAvroInstaller.swift
// Manages installation and activation of TechuAvro as a macOS Input Source.
// CRITICAL: Carbon HIToolbox TIS APIs (TISCreateInputSourceList, TISRegisterInputSource,
// TISEnableInputSource, TISDisableInputSource) MUST run exclusively on the main thread.
// Calling them on background threads triggers `dispatch_assert_queue` SIGTRAP crashes.

import Foundation
import AppKit
import Carbon.HIToolbox

enum TechuAvroInstaller {

    static let bundleID = "com.techuboard.techu-avro"

    // MARK: - Bundle Locator

    /// Discovers the built TechuAvro.app bundle across all standard staging and app locations.
    static func findBundleURL() -> URL? {
        // 1. Embedded inside currently running app Resources
        if let url = Bundle.main.url(forResource: "TechuAvro", withExtension: "app"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("TechuAvro.app"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        // 2. Installed inside /Applications/Techuboard.app
        let installedAppBundle = URL(fileURLWithPath: "/Applications/Techuboard.app/Contents/Resources/TechuAvro.app")
        if FileManager.default.fileExists(atPath: installedAppBundle.path) {
            return installedAppBundle
        }
        // 3. Local build tree
        let devBundle = URL(fileURLWithPath: "/Users/azaanmac/Documents/Clipy/techuboard_macos/TechuAvro/TechuAvro.app")
        if FileManager.default.fileExists(atPath: devBundle.path) {
            return devBundle
        }
        // 4. Staged app bundle
        let stagedBundle = URL(fileURLWithPath: "/Users/azaanmac/Documents/Clipy/techuboard_macos/Techuboard.app/Contents/Resources/TechuAvro.app")
        if FileManager.default.fileExists(atPath: stagedBundle.path) {
            return stagedBundle
        }
        return nil
    }

    // MARK: - Public API

    /// Returns true if TechuAvro is installed and enabled as a system input source.
    static func isInstalled() -> Bool {
        guard let source = findInputSource() else { return false }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        let cfBool = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(cfBool)
    }

    /// Copies the bundle to ~/Library/Input Methods/ and enables the input source.
    /// Runs file I/O in background and TIS registration safely on main thread.
    static func install(from bundlePath: URL? = nil, completion: @escaping (String?) -> Void) {
        guard let sourcePath = bundlePath ?? findBundleURL() else {
            completion("TechuAvro.app bundle not found.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let inputMethodsDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Input Methods")

            do {
                try fm.createDirectory(at: inputMethodsDir, withIntermediateDirectories: true)
                let dest = inputMethodsDir.appendingPathComponent("TechuAvro.app")
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: sourcePath, to: dest)
            } catch {
                DispatchQueue.main.async {
                    completion("Failed to copy bundle: \(error.localizedDescription)")
                }
                return
            }

            let destURL = inputMethodsDir.appendingPathComponent("TechuAvro.app")

            // Carbon TIS registration MUST execute on the main thread
            DispatchQueue.main.async {
                let cfDestURL = destURL as CFURL
                let registerResult = TISRegisterInputSource(cfDestURL)
                _ = registerResult

                // Launch the IME background process so InputMethodKit connects immediately
                NSWorkspace.shared.openApplication(at: destURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }

                // Allow HIToolbox to index the new bundle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let source = findInputSourceOnMain() {
                        _ = TISEnableInputSource(source)
                        _ = TISSelectInputSource(source)
                    }
                    completion(nil)
                }
            }
        }
    }

    /// Disables and removes TechuAvro from the system.
    static func uninstall(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            if let source = findInputSourceOnMain() {
                TISDisableInputSource(source)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let dest = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Input Methods/TechuAvro.app")

                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion("Failed to remove bundle: \(error.localizedDescription)")
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Safe Main-Thread Input Source Lookup

    static func findInputSource() -> TISInputSource? {
        if Thread.isMainThread {
            return findInputSourceOnMain()
        }
        var result: TISInputSource?
        DispatchQueue.main.sync {
            result = findInputSourceOnMain()
        }
        return result
    }

    private static func findInputSourceOnMain() -> TISInputSource? {
        let filter = [kTISPropertyBundleID: bundleID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              let sources = list as? [TISInputSource],
              let first = sources.first else { return nil }
        return first
    }
}
