// TechuAvroInstaller.swift
// Registers TechuAvro.app as a system Input Source using TIS API.
// CRITICAL: TIS APIs MUST run on main thread.

import Foundation
import Carbon.HIToolbox

enum TechuAvroInstaller {

    static let bundleID = "com.techuboard.techu-avro"

    static func isInstalled() -> Bool {
        guard let source = findInputSource() else { return false }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        let cfBool = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(cfBool)
    }

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
