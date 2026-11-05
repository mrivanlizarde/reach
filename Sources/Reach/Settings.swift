import Foundation
import Combine

/// Every user-facing knob. Persisted in UserDefaults so the app comes back the way it was left.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var trackingEnabled: Bool { didSet { d.set(trackingEnabled, forKey: "trackingEnabled") } }
    @Published var cameraID: String { didSet { d.set(cameraID, forKey: "cameraID") } }
    @Published var pinchToClick: Bool { didSet { d.set(pinchToClick, forKey: "pinchToClick") } }
    @Published var tapSoundToClick: Bool { didSet { d.set(tapSoundToClick, forKey: "tapSoundToClick") } }
    @Published var smoothing: Double { didSet { d.set(smoothing, forKey: "smoothing") } }
    @Published var tapSensitivity: Double { didSet { d.set(tapSensitivity, forKey: "tapSensitivity") } }
    @Published var showPreview: Bool { didSet { d.set(showPreview, forKey: "showPreview") } }
    @Published var mirror: Bool { didSet { d.set(mirror, forKey: "mirror") } }
    /// The region of the camera frame that maps to the full screen, in normalized camera
    /// coordinates (origin bottom-left, as Vision reports them). Set by calibration.
    @Published var region: CGRect { didSet { d.set(NSStringFromRect(region), forKey: "region") } }

    private init() {
        d.register(defaults: [
            "trackingEnabled": false,
            "cameraID": "",
            "pinchToClick": true,
            "tapSoundToClick": true,
            "smoothing": 0.5,
            "tapSensitivity": 0.5,
            "showPreview": true,
            "mirror": true,
            "region": NSStringFromRect(CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5)),
        ])
        trackingEnabled = d.bool(forKey: "trackingEnabled")
        cameraID = d.string(forKey: "cameraID") ?? ""
        pinchToClick = d.bool(forKey: "pinchToClick")
        tapSoundToClick = d.bool(forKey: "tapSoundToClick")
        smoothing = d.double(forKey: "smoothing")
        tapSensitivity = d.double(forKey: "tapSensitivity")
        showPreview = d.bool(forKey: "showPreview")
        mirror = d.bool(forKey: "mirror")
        region = NSRectFromString(d.string(forKey: "region") ?? "")
        if region.isEmpty { region = CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5) }
    }

    func resetRegion() { region = CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5) }
}
