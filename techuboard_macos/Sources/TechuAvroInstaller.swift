// TechuAvroInstaller.swift  (main app copy — thin bridge)
// The actual heavy lifting lives in TechuAvro.app;
// this copy only handles copy-install + TIS registration from the host app.

import Foundation
import Carbon.HIToolbox

/// Manages installation and activation of TechuAvro as a macOS Input Source.
enum TechuAvroInstaller {

    static let bundleID = "com.techuboard.techu-avro"

    // MARK: - Public API

    /// Returns true if TechuAvro is installed and enabled as a system input source.
    static func isInstalled() -> Bool {
        guard let source = findInputSource() else { return false }
        let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
        guard let ptr = raw else { return false }
        let cfBool = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(cfBool)
    }

    /// Copies the bundle to ~/Library/Input Methods/ and enables the input source.
    /// - Parameter bundlePath: Path to the built TechuAvro.app
    /// - Returns: nil on success, error message string on failure
    @discardableResult
    static func install(from bundlePath: URL) -> String? {
        let fm = FileManager.default
        let inputMethodsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods")

        do {
            try fm.createDirectory(at: inputMethodsDir, withIntermediateDirectories: true)
            let dest = inputMethodsDir.appendingPathComponent("TechuAvro.app")
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: bundlePath, to: dest)
        } catch {
            return "Failed to copy bundle: \(error.localizedDescription)"
        }

        // Register with TIS (bundle must already be in ~/Library/Input Methods/)
        let inputMethodsDir2 = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/TechuAvro.app") as CFURL
        let registerResult = TISRegisterInputSource(inputMethodsDir2)
        guard registerResult == noErr || registerResult == -50 /* already registered */ else {
            return "TISRegisterInputSource failed: OSStatus \(registerResult)"
        }

        // Small delay to let TIS process the registration
        Thread.sleep(forTimeInterval: 0.5)

        if let source = findInputSource() {
            let enableResult = TISEnableInputSource(source)
            if enableResult != noErr {
                return "TISEnableInputSource failed: OSStatus \(enableResult)"
            }
        }

        return nil // success
    }

    /// Disables and removes TechuAvro from the system.
    @discardableResult
    static func uninstall() -> String? {
        if let source = findInputSource() {
            TISDisableInputSource(source)
        }

        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/TechuAvro.app")

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
        } catch {
            return "Failed to remove bundle: \(error.localizedDescription)"
        }

        return nil
    }

    // MARK: - Private

    static func findInputSource() -> TISInputSource? {
        let filter = [kTISPropertyBundleID: bundleID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              let sources = list as? [TISInputSource],
              let first = sources.first else { return nil }
        return first
    }
}
