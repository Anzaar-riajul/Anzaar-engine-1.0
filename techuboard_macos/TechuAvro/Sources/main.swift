import Foundation
import InputMethodKit
import AppKit

// Bootstrap: create the IMKServer and bind controller class.
// The name "TechuAvro_Connection" MUST match Info.plist InputMethodConnectionName.
guard let server = IMKServer(name: "TechuAvro_Connection",
                             controllerClass: TechuAvroController.self,
                             delegateClass: TechuAvroController.self) else {
    fputs("[TechuAvro] Fatal: IMKServer failed to initialize.\n", stderr)
    exit(1)
}

_ = server
NSApplication.shared.run()
