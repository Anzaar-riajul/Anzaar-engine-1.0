import Foundation
import InputMethodKit
import AppKit

final class TechuAvroAppDelegate: NSObject, NSApplicationDelegate {
}

let appDelegate = TechuAvroAppDelegate()
NSApplication.shared.delegate = appDelegate

// Bootstrap: create the IMKServer.
// The name "TechuAvro_Connection" MUST match Info.plist InputMethodConnectionName.
guard let server = IMKServer(name: "TechuAvro_Connection",
                             bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.techuboard.techu-avro") else {
    fputs("[TechuAvro] Fatal: IMKServer failed to initialize.\n", stderr)
    exit(1)
}

_ = server
NSApplication.shared.run()
