import Foundation
import InputMethodKit

// TechuAvroApp: NSObject subclass used as NSPrincipalClass by InputMethodKit.
// IMKServer is the bridge between macOS text services and our controller.
final class TechuAvroApp: NSObject {
    // Intentionally empty; IMKServer drives the event loop.
}

// Bootstrap: create the IMKServer and hand off to the run loop.
// The name "TechuAvro" MUST match Info.plist InputMethodConnectionName.
guard let server = IMKServer(name: "TechuAvro",
                              bundleIdentifier: Bundle.main.bundleIdentifier) else {
    fputs("[TechuAvro] Fatal: IMKServer failed to initialize.\n", stderr)
    exit(1)
}

// Keep server alive (ARC would collect it otherwise).
_ = server

RunLoop.main.run()
