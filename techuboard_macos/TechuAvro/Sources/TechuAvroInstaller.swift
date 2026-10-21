// TechuAvroInstaller.swift
// Registers TechuAvro.app as a system Input Source using TIS (Text Input Sources) API.
// Called from the main Techuboard app's Settings UI.

import Foundation
import Carbon.HIToolbox

/// Manages installation and activation of TechuAvro as a macOS Input Source.
enum TechuAvroInstaller {

    static let bundleID = "com.techuboard.techu-avro"
    static let installPath = "~/Library/Input Methods/TechuAvro.app"

    // MARK: - Public API

    /// Returns true if TechuAvro is installed and enabled as a system input source.
    static func isInstalled() -> Bool {
        guard let source = findInputSource() else { return false }
        let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
        // TISGetInputSourceProperty returns CFTypeRef; for boolean props use CFBooleanRef
        let cfBool = enabled.map { Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue() }
        return cfBool.map { CFBooleanGetValue($0) } ?? false
    }

    /// Copies the bundle to ~/Library/Input Methods/ and enables the input source.
    /// - Parameter bundlePath: Path to the built TechuAvro.app
    /// - Returns: nil on success, error message on failure
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

        // Register with TIS
        // The bundle must be in ~/Library/Input Methods/ BEFORE calling TISRegisterInputSource
        let destURL = inputMethodsDir.appendingPathComponent("TechuAvro.app") as CFURL
        let registerResult = TISRegisterInputSource(destURL)
        guard registerResult == noErr else {
            return "TISRegisterInputSource failed with OSStatus: \(registerResult)"
        }

        // Enable it
        if let source = findInputSource() {
            let enableResult = TISEnableInputSource(source)
            if enableResult != noErr {
                return "TISEnableInputSource failed with OSStatus: \(enableResult)"
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

    private static func findInputSource() -> TISInputSource? {
        let filter = [kTISPropertyBundleID: bundleID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let first = sources.first else { return nil }
        return first
    }
}
