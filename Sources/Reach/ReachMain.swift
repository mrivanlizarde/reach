import AppKit

// Reach: a menu bar app that turns the built-in camera into a pointing device.
// No Dock icon, no main window. Everything lives in the status item.
@main
struct ReachMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
