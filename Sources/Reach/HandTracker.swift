import AVFoundation
import Vision
import CoreGraphics
import CoreImage

/// One frame's worth of hand knowledge, in Vision's normalized coordinates (origin bottom-left).
struct HandSample: Sendable {
    let indexTip: CGPoint
    let thumbTip: CGPoint
    let wrist: CGPoint
    let middleMCP: CGPoint
    let confidence: Float
    let time: Double
    /// Thumb tip to index tip distance, divided by hand size (wrist to middle knuckle),
    /// so a pinch means the same thing near and far from the camera.
    var pinchRatio: CGFloat {
        let handSize = max(hypot(wrist.x - middleMCP.x, wrist.y - middleMCP.y), 0.02)
        return hypot(indexTip.x - thumbTip.x, indexTip.y - thumbTip.y) / handSize
    }
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
                let tips = try obs.recognizedPoints(.all)
                if let idx = tips[.indexTip], let th = tips[.thumbTip], let w = tips[.wrist], let m = tips[.middleMCP],
                   idx.confidence > 0.3, th.confidence > 0.3 {
                    sample = HandSample(indexTip: idx.location, thumbTip: th.location, wrist: w.location,
                                        middleMCP: m.location, confidence: min(idx.confidence, th.confidence), time: t)
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
