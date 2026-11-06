import AVFoundation
import Vision
import CoreGraphics
import CoreImage

/// Vision's 21 hand joints, wrist first, then one chain per finger from knuckle to tip.
enum Joint: Int, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    static let visionNames: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]
}

enum Finger: Int, CaseIterable, Sendable {
    case thumb, index, middle, ring, little
    /// Knuckle to tip. The thumb's chain starts at the CMC joint near the wrist.
    var chain: [Joint] {
        switch self {
        case .thumb: return [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]
        case .index: return [.indexMCP, .indexPIP, .indexDIP, .indexTip]
        case .middle: return [.middleMCP, .middlePIP, .middleDIP, .middleTip]
        case .ring: return [.ringMCP, .ringPIP, .ringDIP, .ringTip]
        case .little: return [.littleMCP, .littlePIP, .littleDIP, .littleTip]
        }
    }
    var tip: Joint { chain[3] }
    var pip: Joint { chain[1] }
}

/// One frame's worth of hand knowledge: all 21 joints in Vision's normalized coordinates
/// (origin bottom-left), with what the pointer and the gestures read off them.
struct HandSample: Sendable {
    let points: [CGPoint]
    let confidences: [Float]
    let time: Double

    subscript(_ j: Joint) -> CGPoint { points[j.rawValue] }
    func confident(_ j: Joint) -> Bool { confidences[j.rawValue] > 0.3 }

    var wrist: CGPoint { self[.wrist] }
    var thumbTip: CGPoint { self[.thumbTip] }
    var indexTip: CGPoint { self[.indexTip] }
    var middleTip: CGPoint { self[.middleTip] }
    var indexMCP: CGPoint { self[.indexMCP] }
    var middleMCP: CGPoint { self[.middleMCP] }
    var pinkyMCP: CGPoint { self[.littleMCP] }
    var confidence: Float { min(confidences[Joint.indexTip.rawValue], confidences[Joint.thumbTip.rawValue]) }

    /// Hand size: the longest of three palm edges. A palm turned edge-on to the camera
    /// foreshortens any single one of them.
    var palm: CGFloat {
        max(dist(wrist, middleMCP), dist(wrist, indexMCP), dist(indexMCP, pinkyMCP), 0.02)
    }
    /// Thumb tip to index tip, divided by hand size, so a pinch means the same thing near
    /// and far from the camera.
    var pinchRatio: CGFloat { dist(indexTip, thumbTip) / palm }
    /// Thumb tip to middle tip, same scale. The right-click pinch.
    var middlePinchRatio: CGFloat { dist(middleTip, thumbTip) / palm }

    /// Where the pointer is read from: the middle of the knuckle row, not the fingertip.
    /// The fingertip is the one joint that moves when you pinch, so a tip-anchored cursor
    /// ran off its target at the moment of every click (Ivan, 2026-11-05). The knuckles
    /// stay put through a pinch, a scroll, and a fist.
    var anchor: CGPoint {
        CGPoint(x: (indexMCP.x + middleMCP.x) / 2, y: (indexMCP.y + middleMCP.y) / 2)
    }

    /// Fingertip above the wrist in the frame: a hand held up to point, not one resting on
    /// the keyboard. Typing hands read as pinches to the pose model; this is the gate.
    var raised: Bool { indexTip.y > wrist.y + 0.02 }

    /// A finger is extended when its tip is clearly farther from the wrist than its middle
    /// joint is. A curled finger folds its tip back toward the palm. The thumb is measured
    /// from the little finger's knuckle instead: tucked across the palm it ends up near
    /// there, held out it ends up far away.
    func extended(_ f: Finger) -> Bool {
        let tip = f.tip, pip = f.pip
        guard confident(tip), confident(pip) else { return f == .index }
        if f == .thumb {
            return dist(self[.thumbTip], pinkyMCP) > dist(self[.thumbIP], pinkyMCP) * 1.08
        }
        return dist(self[tip], wrist) > dist(self[pip], wrist) * 1.12
    }
    /// Thumb, index, middle, ring, little as five digits, 1 for extended. "01100" is two up.
    var extendedMask: String { Finger.allCases.map { extended($0) ? "1" : "0" }.joined() }
    /// Index and middle up, ring and little down: the scroll pose.
    var isTwoFinger: Bool { extended(.index) && extended(.middle) && !extended(.ring) && !extended(.little) }
    /// All four fingers down: the hold pose, like lifting a mouse off the desk.
    var isFist: Bool { !extended(.index) && !extended(.middle) && !extended(.ring) && !extended(.little) }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

@MainActor
protocol HandTrackerDelegate: AnyObject {
    func tracker(_ tracker: HandTracker, didSee hand: HandSample?)
    func tracker(_ tracker: HandTracker, didCapture image: CGImage)
    func tracker(_ tracker: HandTracker, didFail message: String)
}

/// Runs the camera and Vision's hand pose detector. Everything heavy happens on `queue`;
/// results are handed to the delegate on the main actor.
final class HandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var delegate: HandTrackerDelegate?
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "reach.camera", qos: .userInteractive)
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    private var previewCounter = 0
    var wantsPreview = true
    private(set) var isRunning = false

    /// Every camera that could drive the pointer, Desk View included. Desk View is Apple's
    /// virtual overhead camera cut from the ultra-wide sensor: it sees the desk and the
    /// space just in front of the keyboard, which is where hands tend to be.
    static func availableCameras() -> [AVCaptureDevice] {
        let s = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .deskViewCamera, .continuityCamera, .external],
            mediaType: .video, position: .unspecified)
        return s.devices
    }

    func start(cameraID: String) {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            for i in session.inputs { session.removeInput(i) }
            for o in session.outputs { session.removeOutput(o) }

            let cams = HandTracker.availableCameras()
            guard let device = cams.first(where: { $0.uniqueID == cameraID })
                    ?? cams.first(where: { $0.deviceType == .builtInWideAngleCamera })
                    ?? cams.first else {
                session.commitConfiguration()
                report("No camera found.")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw NSError(domain: "Reach", code: 1) }
                session.addInput(input)
                // 1280x720 is plenty for hand pose and keeps Vision under 10 ms a frame.
                session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(output) else { throw NSError(domain: "Reach", code: 2) }
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
                isRunning = true
            } catch {
                session.commitConfiguration()
                report("Could not open \(device.localizedName): \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            isRunning = false
        }
    }

    private func report(_ message: String) {
        Task { @MainActor in self.delegate?.tracker(self, didFail: message) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        var sample: HandSample? = nil
        do {
            try handler.perform([request])
            if let obs = request.results?.first {
                let all = try obs.recognizedPoints(.all)
                var pts = [CGPoint](repeating: .zero, count: Joint.allCases.count)
                var conf = [Float](repeating: 0, count: Joint.allCases.count)
                for j in Joint.allCases {
                    if let p = all[Joint.visionNames[j.rawValue]] { pts[j.rawValue] = p.location; conf[j.rawValue] = p.confidence }
                }
                // The pointer needs the knuckle row and the pinch needs the two tips. Without
                // those four, the frame is noise.
                let needed: [Joint] = [.indexTip, .thumbTip, .indexMCP, .middleMCP]
                if needed.allSatisfy({ conf[$0.rawValue] > 0.3 }) {
                    sample = HandSample(points: pts, confidences: conf, time: t)
                }
            }
        } catch {
            // A failed frame is just a missed frame.
        }
        let s = sample
        Task { @MainActor in self.delegate?.tracker(self, didSee: s) }

        // Preview at ~10 fps and a quarter of the size: enough to see the hand, cheap enough to ignore.
        previewCounter += 1
        if wantsPreview, previewCounter % 3 == 0 {
            let ci = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
            if let cg = HandTracker.ciContext.createCGImage(ci, from: ci.extent) {
                Task { @MainActor in self.delegate?.tracker(self, didCapture: cg) }
            }
        }
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
}
