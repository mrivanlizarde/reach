import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let engine = PointerEngine()
    private var observer: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Reach")
            b.image?.isTemplate = true
            b.action = #selector(togglePopover)
            b.target = self
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PanelView(engine: engine, settings: Settings.shared).frame(width: 300))

        // The icon tells the story at a glance: outline when off, filled when a hand is live.
        observer = engine.$handVisible.combineLatest(Settings.shared.$trackingEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] visible, on in
                let name = !on ? "hand.point.up.left" : (visible ? "hand.point.up.left.fill" : "hand.point.up.left")
                self?.statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Reach")
                self?.statusItem.button?.image?.isTemplate = true
                self?.statusItem.button?.appearsDisabled = false
            }

        // Sensors start only now, with the icon on screen and the run loop live.
        engine.activate()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // Calibration is a two-step hold; closing the panel mid-way should not leave it armed.
        if engine.calibration != .idle { engine.cancelCalibration() }
    }
}

enum LaunchAtLogin {
    static var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("Launch at login: \(error)") }
        }
    }
}
