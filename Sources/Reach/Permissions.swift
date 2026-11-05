import AVFoundation
import ApplicationServices
import AppKit

enum Permissions {
    static var camera: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    /// Posting mouse events needs the Accessibility grant. Without it the hand is tracked
    /// and nothing moves, which is the confusing failure, so the UI names it loudly.
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestCamera(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: done)
    }
    static func requestMicrophone(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: done)
    }
    static func promptAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
    static func openAccessibilitySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }
    static func openCameraSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(u)
        }
    }
}
