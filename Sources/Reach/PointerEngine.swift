import AppKit
import CoreGraphics
import Combine

/// Turns hand samples into pointer motion and clicks. Owns the two sensors.
@MainActor
final class PointerEngine: ObservableObject, HandTrackerDelegate {
    enum CalibrationStep { case idle, topLeft, bottomRight }

    @Published var handVisible = false
    @Published var pinching = false
    @Published var lastHand: HandSample?
    @Published var preview: CGImage?
    @Published var status: String = "Off"
    @Published var calibration: CalibrationStep = .idle
    @Published var tapCount = 0
    @Published var fps: Double = 0

    private let tracker = HandTracker()
    private let taps = TapListener()
    private let settings = Settings.shared
    private var fx = OneEuroFilter(minCutoff: 1.2, beta: 0.01)
    private var fy = OneEuroFilter(minCutoff: 1.2, beta: 0.01)
    private var pinchFrames = 0
    private var releaseFrames = 0
    private var mouseIsDown = false
    private var lastPoint = CGPoint.zero
    private var lastSeen: Double = 0
    private var frameTimes: [Double] = []
    private var calibSamples: [CGPoint] = []
    private var calibTL: CGPoint?
    private var cancellables = Set<AnyCancellable>()

    init() {
        tracker.delegate = self
        taps.onTap = { [weak self] strength in
            Task { @MainActor in self?.handleTap(strength) }
        }
        settings.$trackingEnabled.removeDuplicates().sink { [weak self] on in
            on ? self?.start() : self?.stop()
        }.store(in: &cancellables)
        settings.$cameraID.dropFirst().removeDuplicates().sink { [weak self] id in
            guard let self, self.settings.trackingEnabled else { return }
            self.tracker.start(cameraID: id)
        }.store(in: &cancellables)
        settings.$tapSoundToClick.removeDuplicates().sink { [weak self] on in
            guard let self, self.settings.trackingEnabled else { return }
            on ? self.taps.start() : self.taps.stop()
        }.store(in: &cancellables)
        settings.$tapSensitivity.sink { [weak self] v in self?.taps.sensitivity = v }.store(in: &cancellables)
        settings.$smoothing.sink { [weak self] v in self?.applySmoothing(v) }.store(in: &cancellables)
        settings.$showPreview.sink { [weak self] v in self?.tracker.wantsPreview = v }.store(in: &cancellables)
    }

    /// 0 = raw and twitchy, 1 = heavy and calm. Both filter knobs move together.
    private func applySmoothing(_ v: Double) {
        let cutoff = 4.0 - 3.4 * v          // 4 Hz down to 0.6 Hz
        let beta = 0.05 - 0.045 * v
        fx.minCutoff = cutoff; fx.beta = beta
        fy.minCutoff = cutoff; fy.beta = beta
    }

    func start() {
        guard Permissions.camera == .authorized else {
            status = "Camera access needed"
            Permissions.requestCamera { [weak self] ok in
                Task { @MainActor in
                    if ok { self?.start() } else { self?.settings.trackingEnabled = false }
                }
            }
            return
        }
        if !Permissions.accessibility {
            status = "Accessibility access needed"
            Permissions.promptAccessibility()
        }
        tracker.start(cameraID: settings.cameraID)
        if settings.tapSoundToClick { taps.start() }
        status = "Looking for a hand"
    }

    func stop() {
        tracker.stop()
        taps.stop()
        releaseMouse()
        handVisible = false
        pinching = false
        preview = nil
        status = "Off"
    }

    // MARK: Calibration

    /// Two-point calibration: point at the top-left corner of the screen, hold, then the
    /// bottom-right. The region between becomes the full screen, so the hand never has to
    /// travel the whole camera frame to reach an edge.
    func beginCalibration() {
        calibSamples = []
        calibTL = nil
        calibration = .topLeft
        status = "Point at the top-left corner and hold"
    }

    func cancelCalibration() {
        calibration = .idle
        status = handVisible ? "Tracking" : "Looking for a hand"
    }

    private func feedCalibration(_ p: CGPoint) {
        calibSamples.append(p)
        guard calibSamples.count >= 45 else { return }   // ~1.5 s of frames
        let recent = calibSamples.suffix(30)
        let mean = CGPoint(x: recent.map(\.x).reduce(0, +) / CGFloat(recent.count),
                           y: recent.map(\.y).reduce(0, +) / CGFloat(recent.count))
        // Require the hand to be still: spread under 2% of the frame.
        let spread = recent.map { hypot($0.x - mean.x, $0.y - mean.y) }.max() ?? 1
        guard spread < 0.02 else { return }
        calibSamples = []
        switch calibration {
        case .topLeft:
            calibTL = mean
            calibration = .bottomRight
            status = "Now the bottom-right corner"
            NSSound(named: "Tink")?.play()
        case .bottomRight:
            guard let tl = calibTL else { return }
            // Vision's origin is bottom-left, so the top-left corner has the larger y.
            let x0 = min(tl.x, mean.x), x1 = max(tl.x, mean.x)
            let y0 = min(tl.y, mean.y), y1 = max(tl.y, mean.y)
            if x1 - x0 > 0.1, y1 - y0 > 0.1 {
                settings.region = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                status = "Calibrated"
                NSSound(named: "Glass")?.play()
            } else {
                status = "Corners too close, try again"
            }
            calibration = .idle
        case .idle: break
        }
    }

    // MARK: HandTrackerDelegate

    func tracker(_ tracker: HandTracker, didSee hand: HandSample?) {
        guard let hand else {
            if handVisible, CACurrentMediaTime() - lastSeen > 0.4 {
                handVisible = false
                lastHand = nil
                releaseMouse()
                if calibration == .idle { status = "Looking for a hand" }
            }
            return
        }
        lastSeen = CACurrentMediaTime()
        frameTimes.append(lastSeen)
        frameTimes.removeAll { $0 < lastSeen - 1 }
        fps = Double(frameTimes.count)
        if !handVisible {
            handVisible = true
            fx.reset(); fy.reset()
            if calibration == .idle { status = "Tracking" }
        }
        lastHand = hand

        // Mirror so moving your hand right moves the pointer right (the camera faces you).
        var p = hand.indexTip
        if settings.mirror { p.x = 1 - p.x }

        if calibration != .idle {
            feedCalibration(p)
            return
        }

        // Map the calibrated region onto the main screen. Vision y grows upward; screen y
        // for CGEvent grows downward from the top-left of the main display.
        let r = settings.region
        let nx = ((p.x - r.minX) / r.width).clamped(0, 1)
        let ny = ((p.y - r.minY) / r.height).clamped(0, 1)
        guard let screen = NSScreen.main else { return }
        let sx = fx.filter(Double(screen.frame.minX + nx * screen.frame.width), at: hand.time)
        let sy = fy.filter(Double(screen.frame.minY + (1 - ny) * screen.frame.height), at: hand.time)
        let point = CGPoint(x: sx, y: sy)
        lastPoint = point
        if Permissions.accessibility {
            post(mouseIsDown ? .leftMouseDragged : .mouseMoved, at: point)
        }

        // Pinch with hysteresis and a few frames of evidence, as Apple's WWDC20 sample does.
        if settings.pinchToClick {
            let ratio = hand.pinchRatio
            if ratio < 0.28 { pinchFrames += 1; releaseFrames = 0 } else if ratio > 0.4 { releaseFrames += 1; pinchFrames = 0 }
            if !mouseIsDown, pinchFrames >= 3 { pressMouse() }
            if mouseIsDown, releaseFrames >= 3 { releaseMouse() }
        } else if mouseIsDown {
            releaseMouse()
        }
    }

    func tracker(_ tracker: HandTracker, didCapture image: CGImage) {
        preview = image
    }

    func tracker(_ tracker: HandTracker, didFail message: String) {
        status = message
    }

    // MARK: Clicks

    /// A tap heard on the glass clicks wherever the hand is. Only when a hand is in view,
    /// so a dropped pen or a knock on the desk does nothing.
    private func handleTap(_ strength: Float) {
        guard settings.tapSoundToClick, handVisible, calibration == .idle, Permissions.accessibility else { return }
        tapCount += 1
        if mouseIsDown { return }
        post(.leftMouseDown, at: lastPoint)
        post(.leftMouseUp, at: lastPoint)
    }

    private func pressMouse() {
        guard Permissions.accessibility else { return }
        mouseIsDown = true
        pinching = true
        post(.leftMouseDown, at: lastPoint)
    }

    private func releaseMouse() {
        pinching = false
        guard mouseIsDown else { return }
        mouseIsDown = false
        post(.leftMouseUp, at: lastPoint)
    }

    private func post(_ type: CGEventType, at p: CGPoint) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        e.post(tap: .cghidEventTap)
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
