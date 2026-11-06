import AppKit
import CoreGraphics
import Combine

/// Turns hand samples into pointer motion, clicks, and scrolls. Owns the two sensors.
@MainActor
final class PointerEngine: ObservableObject, HandTrackerDelegate {
    enum CalibrationStep { case idle, topLeft, bottomRight }
    /// What the hand is doing right now, for the panel and the log.
    enum Mode: String { case point, aim, scroll, hold }

    @Published var handVisible = false
    @Published var pinching = false
    @Published var rightPinching = false
    @Published var lastHand: HandSample?
    @Published var preview: CGImage?
    @Published var status: String = "Off"
    @Published var calibration: CalibrationStep = .idle
    @Published var tapCount = 0
    @Published var fps: Double = 0
    @Published var pinchRatio: Double = 0
    @Published var lastTapOnset: Float = 0
    @Published var handRaised = false
    @Published var fingers = "00000"
    @Published var mode: Mode = .point
    /// A hand that has not moved for two seconds is parked: it stops driving the pointer
    /// until it moves again. Two runs on 2026-11-05 showed the pose model holding a
    /// motionless "hand" at 30 fps for minutes; with the grant on, that pins the pointer.
    @Published var asleep = false
    private var recentTips: [(t: Double, p: CGPoint)] = []
    private var sleepAnchor: CGPoint?

    private let tracker = HandTracker()
    private let taps = TapListener()
    private let settings = Settings.shared
    private var fx = OneEuroFilter(minCutoff: 1.2, beta: 0.01)
    private var fy = OneEuroFilter(minCutoff: 1.2, beta: 0.01)
    private var pinchFrames = 0
    private var releaseFrames = 0
    private var rightFrames = 0
    private var rightReleaseFrames = 0
    private var mouseIsDown = false
    private var rightIsDown = false
    /// Where the pointer is on screen: the last point posted.
    private var lastPoint = CGPoint.zero
    /// Where the hand says the pointer should be, before the pinned offset.
    private var lastTarget = CGPoint.zero
    private var lastSeen: Double = 0
    private var lastFrameTime: Double = 0

    // MARK: Steadiness
    //
    // Three things keep the cursor from shaking (Ivan, 2026-11-05: "it's following my
    // fingers too accurately so the cursor moves off my intended target").
    //
    // 1. The cursor trails the hand on a short string: it only moves once the hand's point
    //    is more than `lazyRadius` away, and then only by the excess. Jitter inside the
    //    radius never reaches the screen.
    // 2. The moment the thumb starts closing, the cursor is pinned where it was aimed, for
    //    up to `aimHold` seconds. The hand rotates as it pinches; the click still lands.
    // 3. A pinch is a click until the hand has moved `dragSlop` pixels from the press
    //    point; only then does it become a drag. iOS treats touches the same way.
    //
    // Every time the cursor is held still while the hand keeps moving, the gap between
    // them is pinned as an offset that then fades out, so letting go never makes the
    // cursor jump to where the hand already is.
    private let lazyRadius: CGFloat = 5
    private let aimHold: Double = 0.5
    private let dragSlop: CGFloat = 24
    /// How far back the click reaches for its point. The thumb takes about six frames to
    /// close and the pinch three more to be believed, and the knuckles turn the whole way.
    /// In Ivan's run of 2026-11-05 17:02 every one of eleven pinches drifted past the old
    /// 14 px slop while held still. The click lands where the cursor was before the thumb
    /// moved, and the button is not pressed until the pinch either travels (a drag) or lets
    /// go (a click at that one point).
    private let aimLookback: Double = 0.25
    private var aimSince: Double?
    private var pressPoint: CGPoint?
    private var pressTime: Double = 0
    private var pressed = false      // the pinch is held; the button may not be down yet
    private var dragging = false
    private var pin = CGVector.zero
    private var trail: [(t: Double, p: CGPoint)] = []

    // MARK: Gestures
    private var twoFrames = 0
    private var notTwoFrames = 0
    private var fistFrames = 0
    private var scrolling = false
    private var holding = false
    private var lastScrollTarget: CGPoint?
    private let scrollGain = 1.5

    /// When a raised hand was last in frame. The camera does not see the hand on its way to
    /// the glass at all: in Ivan's fourth run (2026-11-05 14:30) every glass tap arrived 3 to
    /// 20 seconds after the last raised sighting. So the rule is "point, then reach and
    /// tap": a tap heard within five seconds of a raised hand clicks at the last known point.
    private var lastRaisedSeen: Double = 0
    private var frameTimes: [Double] = []
    private var calibSamples: [CGPoint] = []
    private var calibTL: CGPoint?
    private var cancellables = Set<AnyCancellable>()

    init() {
        tracker.delegate = self
        taps.onTap = { [weak self] strength in
            Task { @MainActor in self?.handleTap(strength) }
        }
        // Every sink drops its first value. Starting sensors from inside init hung the app at
        // launch on 2026-11-05: the microphone engine blocked the main thread before the
        // menu bar icon existed. `activate()` starts things once the app is up.
        settings.$trackingEnabled.dropFirst().removeDuplicates().sink { [weak self] on in
            on ? self?.start() : self?.stop()
        }.store(in: &cancellables)
        settings.$cameraID.dropFirst().removeDuplicates().sink { [weak self] id in
            guard let self, self.settings.trackingEnabled else { return }
            self.tracker.start(cameraID: id)
        }.store(in: &cancellables)
        settings.$tapSoundToClick.dropFirst().removeDuplicates().sink { [weak self] on in
            guard let self, self.settings.trackingEnabled else { return }
            on ? self.startTapsIfAllowed() : self.taps.stop()
        }.store(in: &cancellables)
        settings.$tapSensitivity.sink { [weak self] v in self?.taps.sensitivity = v }.store(in: &cancellables)
        settings.$smoothing.sink { [weak self] v in self?.applySmoothing(v) }.store(in: &cancellables)
        settings.$showPreview.sink { [weak self] v in self?.tracker.wantsPreview = v }.store(in: &cancellables)
    }

    /// Called once the app has finished launching. Never from init.
    func activate() {
        if settings.trackingEnabled { start() }
    }

    /// The microphone engine is only touched with the grant in hand. Asking for the grant
    /// from inside the engine's own setup is what deadlocked the launch.
    private func startTapsIfAllowed() {
        switch Permissions.microphone {
        case .authorized:
            DispatchQueue.main.async { [weak self] in
                guard let self, self.settings.trackingEnabled, self.settings.tapSoundToClick else { return }
                self.taps.start()
                if let e = self.taps.lastError { Diagnostics.shared.log("note", "mic: \(e)") }
            }
        case .notDetermined:
            Permissions.requestMicrophone { [weak self] ok in
                Task { @MainActor in if ok { self?.startTapsIfAllowed() } }
            }
        default:
            Diagnostics.shared.log("note", "mic not granted; tap-to-click off")
        }
    }

    /// 0 = raw and twitchy, 1 = heavy and calm. Both filter knobs move together.
    private func applySmoothing(_ v: Double) {
        let cutoff = 3.0 - 2.5 * v          // 3 Hz down to 0.5 Hz
        let beta = 0.03 - 0.027 * v
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
            status = "Needs Device Control and Data Access"
            Permissions.promptAccessibility()
        }
        tracker.start(cameraID: settings.cameraID)
        if settings.tapSoundToClick { startTapsIfAllowed() }
        Diagnostics.shared.log("note", "start camera=\(settings.cameraID) tapSens=\(settings.tapSensitivity) smoothing=\(settings.smoothing) scroll=\(settings.scrollGesture) rightPinch=\(settings.rightClickPinch) accessibility=\(Permissions.accessibility)")
        status = "Looking for a hand"
    }

    func stop() {
        tracker.stop()
        taps.stop()
        releaseAll()
        handVisible = false
        preview = nil
        status = "Off"
    }

    // MARK: Calibration

    /// Two-point calibration: point at the top-left corner of the screen, hold, then the
    /// bottom-right. The region between becomes the full screen, so the hand never has to
    /// travel the whole camera frame to reach an edge. Measured at the knuckles, like the
    /// pointer itself.
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
            if handVisible, CACurrentMediaTime() - lastSeen > 0.7 {
                handVisible = false
                handRaised = false
                asleep = false; sleepAnchor = nil; recentTips = []
                lastHand = nil
                Diagnostics.shared.log("note", "hand lost")
                releaseAll()
                leaveGestures()
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
            pin = .zero
            if calibration == .idle { status = "Tracking" }
        }
        lastHand = hand
        handRaised = hand.raised
        if hand.raised { lastRaisedSeen = lastSeen }
        pinchRatio = Double(hand.pinchRatio)
        fingers = hand.extendedMask
        Diagnostics.shared.log("hand", String(format: "%.3f", hand.pinchRatio), String(format: "%.3f", hand.middlePinchRatio),
                               hand.raised ? 1 : 0, mouseIsDown ? 1 : rightIsDown ? 2 : 0)

        // A hand on the keyboard is not pointing. Let go of anything held and wait.
        if !hand.raised && calibration == .idle {
            releaseAll()
            leaveGestures()
            return
        }

        // Mirror so moving your hand right moves the pointer right (the camera faces you).
        var p = hand.anchor, tip = hand.indexTip
        if settings.mirror { p.x = 1 - p.x; tip.x = 1 - tip.x }

        if calibration != .idle {
            feedCalibration(p)
            return
        }

        // Stillness gate, measured at the fingertip. Spread of the last two seconds under
        // 1.5% of the frame means parked; waking needs a move of 3% from where it fell
        // asleep. The tip, not the knuckles: a pinch moves the tip, so a pinch always wakes
        // a parked hand, while the phantom hands this guards against never move at all.
        recentTips.append((hand.time, tip))
        recentTips.removeAll { $0.t < hand.time - 2.0 }
        if asleep {
            if let a = sleepAnchor, hypot(tip.x - a.x, tip.y - a.y) > 0.03 {
                asleep = false; sleepAnchor = nil; recentTips = [(hand.time, tip)]
                fx.reset(); fy.reset()
                Diagnostics.shared.log("note", "hand awake")
                status = "Tracking"
                // The filters restart at the hand's real position; keep the cursor where it is
                // and let it ease over.
                lastTarget = screenTarget(for: p, at: hand.time) ?? lastTarget
                pinCursor()
            } else {
                return
            }
        } else if recentTips.count > 20, recentTips.first!.t < hand.time - 1.9 {
            let xs = recentTips.map(\.p.x), ys = recentTips.map(\.p.y)
            if xs.max()! - xs.min()! < 0.015, ys.max()! - ys.min()! < 0.015 {
                asleep = true; sleepAnchor = tip
                releaseAll()
                leaveGestures()
                Diagnostics.shared.log("note", "hand asleep")
                status = "Still. Move to wake"
                return
            }
        }

        guard let target = screenTarget(for: p, at: hand.time) else { return }
        let dt = lastFrameTime > 0 ? min(hand.time - lastFrameTime, 0.2) : 1.0 / 30
        lastFrameTime = hand.time
        let targetStep = hypot(target.x - lastTarget.x, target.y - lastTarget.y)
        lastTarget = target
        trail.append((hand.time, lastPoint))
        trail.removeAll { $0.t < hand.time - 1.0 }

        let ratio = hand.pinchRatio
        let mratio = hand.middlePinchRatio
        let rightPose = settings.rightClickPinch && hand.extended(.index) && ratio > 0.35
        // "Closing": a thumb on its way to a fingertip. The aim pin starts here, before the
        // pinch itself is certain. A pointing hand with the thumb relaxed alongside sits at
        // 0.4 to 0.6 (run of 17:02), so closing has to start well under that.
        let closing = ratio < 0.35 || (rightPose && mratio < 0.35)
        let anyDown = mouseIsDown || rightIsDown   // a pinch is held, button posted or not

        // Scroll pose, with a few frames of evidence either way.
        if settings.scrollGesture, hand.isTwoFinger, !closing, !anyDown { twoFrames += 1; notTwoFrames = 0 }
        else { notTwoFrames += 1; twoFrames = 0 }
        if !scrolling, twoFrames >= 3 {
            scrolling = true; lastScrollTarget = target
            Diagnostics.shared.log("note", "scroll on")
        } else if scrolling, notTwoFrames >= 3 {
            scrolling = false; lastScrollTarget = nil
            pinCursor()
            Diagnostics.shared.log("note", "scroll off")
        }

        // Fist: lift the mouse. Not while a thumb is closing on a finger, which a loose
        // pinch can look like.
        if hand.isFist, !closing, !anyDown { fistFrames += 1 } else { fistFrames = 0 }
        let fist = fistFrames >= 3
        if fist != holding {
            holding = fist
            if !fist { pinCursor() }
            Diagnostics.shared.log("note", holding ? "hold on" : "hold off")
        }

        // Aim pin: cursor stays put from the first closing frame until the pinch lands or
        // `aimHold` runs out. A hand that just hovers half-closed is released to move.
        if closing, !anyDown {
            if aimSince == nil { aimSince = hand.time }
        } else if !closing, aimSince != nil {
            aimSince = nil
            if !anyDown { pinCursor() }
        }
        let aiming = !anyDown && aimSince.map { hand.time - $0 < aimHold } == true
        if !aiming, aimSince != nil, !closing { aimSince = nil }

        // Decide the mode and move, scroll, or hold.
        if scrolling {
            mode = .scroll
            if let prev = lastScrollTarget {
                let dy = Double(target.y - prev.y) * scrollGain
                let dx = Double(target.x - prev.x) * scrollGain
                if abs(dy) >= 1 || abs(dx) >= 1 { postScroll(dy: dy, dx: dx) }
            }
            lastScrollTarget = target
        } else if holding {
            mode = .hold
        } else if aiming || (anyDown && !dragging) {
            mode = .aim
            if anyDown, !dragging, let pp = pressPoint {
                let goal = CGPoint(x: target.x + pin.dx, y: target.y + pin.dy)
                if hypot(goal.x - pp.x, goal.y - pp.y) > dragSlop {
                    beginDrag()
                }
            }
        } else {
            mode = .point
            // The pinned offset fades once nothing is holding the cursor.
            if !anyDown {
                let k = exp(-dt / 0.4)
                pin.dx *= k; pin.dy *= k
                if abs(pin.dx) < 0.5, abs(pin.dy) < 0.5 { pin = .zero }
            }
            let goal = CGPoint(x: target.x + pin.dx, y: target.y + pin.dy)
            let d = hypot(goal.x - lastPoint.x, goal.y - lastPoint.y)
            if d > lazyRadius {
                let f = (d - lazyRadius) / d
                let np = CGPoint(x: lastPoint.x + (goal.x - lastPoint.x) * f, y: lastPoint.y + (goal.y - lastPoint.y) * f)
                move(to: np)
            }
        }
        Diagnostics.shared.log("pose", fingers, hand.extensionRatios, mode.rawValue,
                               String(format: "%.1f|%.1f", hypot(target.x + pin.dx - lastPoint.x, target.y + pin.dy - lastPoint.y), targetStep))

        // Pinch with hysteresis and a few frames of evidence, as Apple's WWDC20 sample does.
        // Not within a third of a second of a keystroke: that hand is typing, not clicking.
        // Thumb to index clicks. Thumb to middle, with the index still pointing, right-clicks.
        if settings.pinchToClick, secondsSinceKey() > 0.3, !scrolling, !holding {
            let rightWins = rightPose && mratio < 0.22
            let leftWins = ratio < 0.22 && !rightWins
            // From Ivan's runs of 2026-11-05: a deliberate pinch goes from 0.8 to 0.05 in three
            // frames and holds at 0.03 to 0.12. A pointing hand with the thumb relaxed beside
            // the index sits at 0.4 to 0.6, and under the old 0.40 / 0.52 gate it held the
            // button down for 27 seconds in the 17:02 run. Press under 0.22, let go over 0.30.
            if leftWins { pinchFrames += 1; releaseFrames = 0 } else if ratio > 0.30 { releaseFrames += 1; pinchFrames = 0 }
            if !anyDown, pinchFrames >= 3 { pressMouse() }
            if mouseIsDown, releaseFrames >= 3 { releaseMouse() }

            if rightWins { rightFrames += 1; rightReleaseFrames = 0 } else if mratio > 0.30 || !rightPose { rightReleaseFrames += 1; rightFrames = 0 }
            if !anyDown, rightFrames >= 3 { pressRight() }
            if rightIsDown, rightReleaseFrames >= 3 { releaseRight() }
        } else if anyDown {
            releaseAll()
        }
    }

    /// Map the calibrated region onto the main screen. Vision y grows upward; screen y
    /// for CGEvent grows downward from the top-left of the main display.
    private func screenTarget(for p: CGPoint, at t: Double) -> CGPoint? {
        let r = settings.region
        let nx = ((p.x - r.minX) / r.width).clamped(0, 1)
        let ny = ((p.y - r.minY) / r.height).clamped(0, 1)
        guard let screen = NSScreen.main else { return nil }
        let sx = fx.filter(Double(screen.frame.minX + nx * screen.frame.width), at: t)
        let sy = fy.filter(Double(screen.frame.minY + (1 - ny) * screen.frame.height), at: t)
        return CGPoint(x: sx, y: sy)
    }

    /// Remember the gap between where the cursor is and where the hand says it should be,
    /// so releasing a hold eases rather than jumps.
    private func pinCursor() {
        pin = CGVector(dx: lastPoint.x - lastTarget.x, dy: lastPoint.y - lastTarget.y)
    }

    private func leaveGestures() {
        if scrolling { Diagnostics.shared.log("note", "scroll off") }
        if holding { Diagnostics.shared.log("note", "hold off") }
        scrolling = false; holding = false; lastScrollTarget = nil
        twoFrames = 0; notTwoFrames = 0; fistFrames = 0
        aimSince = nil
        if mode != .point { mode = .point }
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
        lastTapOnset = strength
        let sinceKey = secondsSinceKey()
        let recentlyRaised = CACurrentMediaTime() - lastRaisedSeen < 5.0
        let accept = settings.tapSoundToClick && recentlyRaised && !asleep && calibration == .idle
            && Permissions.accessibility && sinceKey > 0.3
        Diagnostics.shared.log("tap", strength, String(format: "%.2f", sinceKey), recentlyRaised ? 1 : 0, accept ? 1 : 0)
        if !accept {
            let why = !Permissions.accessibility ? "no accessibility" : !recentlyRaised ? "no raised hand in last 5s" : asleep ? "hand parked" : sinceKey <= 0.3 ? "typing" : "off"
            Diagnostics.shared.log("note", "tap rejected: \(why)")
            return
        }
        tapCount += 1
        if mouseIsDown || rightIsDown { return }
        post(.leftMouseDown, at: lastPoint)
        post(.leftMouseUp, at: lastPoint)
    }

    /// Time since the last physical keystroke anywhere. Needs no permission: it reads the
    /// session's event clock, not the keys. A keyboard tap sounds exactly like a screen tap.
    private func secondsSinceKey() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    private func move(to p: CGPoint) {
        lastPoint = p
        guard Permissions.accessibility else { return }
        post(mouseIsDown && dragging ? .leftMouseDragged : rightIsDown && dragging ? .rightMouseDragged : .mouseMoved, at: p)
    }

    /// Where the cursor was `aimLookback` seconds ago: the point aimed at before the thumb
    /// began to move.
    private func aimedPoint(at t: Double) -> CGPoint {
        trail.last(where: { $0.t <= t - aimLookback })?.p ?? trail.first?.p ?? lastPoint
    }

    /// A pinch is held. The button is not posted yet: if the hand travels it becomes a
    /// drag from the aimed point, and if it lets go first it is a click at that point.
    private func pressMouse() {
        guard Permissions.accessibility else { return }
        mouseIsDown = true
        pinching = true
        beginPress()
    }

    private func pressRight() {
        guard Permissions.accessibility else { return }
        rightIsDown = true
        rightPinching = true
        beginPress()
    }

    private func beginPress() {
        pressTime = lastFrameTime
        pressPoint = aimedPoint(at: lastFrameTime)
        pressed = true
        dragging = false
        aimSince = nil
        // Walk the cursor back to the aimed point so what the user sees is where the click
        // will land.
        if let pp = pressPoint, pp != lastPoint { lastPoint = pp; post(.mouseMoved, at: pp) }
        pinCursor()
        Diagnostics.shared.log("note", "press")
    }

    private func beginDrag() {
        guard let pp = pressPoint else { return }
        dragging = true
        post(mouseIsDown ? .leftMouseDown : .rightMouseDown, at: pp, button: mouseIsDown ? .left : .right)
        Diagnostics.shared.log("note", "drag")
    }

    private func releaseMouse() {
        pinching = false
        guard mouseIsDown else { return }
        mouseIsDown = false
        endPress(button: .left)
    }

    private func releaseRight() {
        rightPinching = false
        guard rightIsDown else { return }
        rightIsDown = false
        endPress(button: .right)
    }

    /// The pinch let go. A drag ends where the cursor is; a click lands, down and up, at
    /// the aimed point. Then pin so the cursor eases over to the hand instead of jumping.
    private func endPress(button: CGMouseButton) {
        let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        if dragging {
            post(up, at: lastPoint, button: button)
        } else if let pp = pressPoint {
            post(down, at: pp, button: button)
            post(up, at: pp, button: button)
            Diagnostics.shared.log("note", button == .left ? "click" : "right click")
        }
        pressPoint = nil
        pressed = false
        dragging = false
        pinCursor()
    }

    /// Let go of everything without clicking. A hand that leaves the frame, parks, or drops
    /// to the keyboard mid-pinch must not fire the click it never finished; a drag in
    /// progress is dropped where it is.
    private func releaseAll() {
        if mouseIsDown || rightIsDown {
            if dragging { post(mouseIsDown ? .leftMouseUp : .rightMouseUp, at: lastPoint, button: mouseIsDown ? .left : .right) }
            Diagnostics.shared.log("note", dragging ? "drag dropped" : "press cancelled")
        }
        mouseIsDown = false; rightIsDown = false
        pinching = false; rightPinching = false
        pressPoint = nil; pressed = false; dragging = false
        pinchFrames = 0; releaseFrames = 0; rightFrames = 0; rightReleaseFrames = 0
    }

    private func post(_ type: CGEventType, at p: CGPoint, button: CGMouseButton = .left) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.post(tap: .cghidEventTap)
    }

    /// Natural scrolling: the content follows the hand. Hand up, page moves up.
    private func postScroll(dy: Double, dx: Double) {
        guard Permissions.accessibility else { return }
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
