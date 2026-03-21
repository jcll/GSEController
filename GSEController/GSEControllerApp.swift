import SwiftUI

@main
struct GSEControllerApp: App {
    init() {
        // Intercept SIGTERM so a graceful shutdown (launchd, Activity Monitor "Quit")
        // releases any held modifier keys via the FIFO before the process exits.
        // SIGKILL cannot be caught; this covers the common graceful-termination case.
        signal(SIGTERM, SIG_IGN) // prevent default termination before handler fires
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler {
            // Best-effort modifier release before exit.
            // The FIFO write may fail if the helper is already gone — that's acceptable.
            for modifier: KeyModifier in [.alt, .shift, .ctrl] {
                KeySimulator.modifierUp(modifier)
            }
            KeySimulator.stopHelper()
            exit(0)
        }
        src.resume()
        // Retain the source for the lifetime of the app.
        _ = Unmanaged.passRetained(src as AnyObject)
    }

    var body: some Scene {
        Window("GSE Controller", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
