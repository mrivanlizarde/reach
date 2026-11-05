import AVFoundation
import Accelerate

/// Listens on the microphone array for the sound of a fingertip tapping the glass.
/// A tap is a sharp, short, broadband transient. We look for a sudden jump in loudness
/// against a slow running average, and in the high band specifically (speech and
/// keyboard rumble live lower). The camera says where; this says when.
final class TapListener {
    private let engine = AVAudioEngine()
    private var slowLevel: Float = 0
    private var slowHigh: Float = 0
    private var lastTap: Double = 0
    private var armed = true
    var onTap: ((Float) -> Void)?
    /// The most recent onset ratio worth noticing, for the panel's readout.
    private(set) var lastOnset: Float = 0
    /// 0 = needs a hard knock, 1 = a brush of the glass. Mapped onto the onset ratio.
    var sensitivity: Double = 0.5
    private(set) var isRunning = false
    private(set) var lastError: String?

    func start() {
        guard !isRunning else { return }
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { lastError = "No microphone input."; return }
        input.installTap(onBus: 0, bufferSize: 512, format: fmt) { [weak self] buffer, time in
            self?.analyze(buffer, at: time)
        }
        do {
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func analyze(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 8 else { return }

        // Total energy.
        var rms: Float = 0
        vDSP_rmsqv(ch, 1, &rms, vDSP_Length(n))

        // High-band energy: first difference is a crude high-pass that is free with vDSP.
        var diff = [Float](repeating: 0, count: n - 1)
        vDSP_vsub(ch, 1, ch + 1, 1, &diff, 1, vDSP_Length(n - 1))
        var hi: Float = 0
        vDSP_rmsqv(diff, 1, &hi, vDSP_Length(n - 1))

        let now = Double(time.sampleTime) / time.sampleRate
        // Slow averages track the room; a tap has to beat them by a margin.
        let decay: Float = 0.97
        let floorLevel: Float = 0.0008
        let onset = hi / max(slowHigh, floorLevel)
        let loud = rms / max(slowLevel, floorLevel)
        // Sensitivity 0.5 asks for a 6x jump in the high band; 1.0 for 3x; 0 for 9x.
        let needed = Float(9.0 - 6.0 * sensitivity)

        let fire = armed && onset > needed && loud > 2.5 && now - lastTap > 0.18
        if onset > 2 {
            lastOnset = onset
            Diagnostics.shared.log("audio", onset, loud, hi, fire ? 1 : 0)
        }
        if fire {
            lastTap = now
            armed = false
            onTap?(onset)
        }
        // Re-arm once the transient has passed.
        if !armed, hi < slowHigh * 1.5 { armed = true }

        slowLevel = decay * slowLevel + (1 - decay) * rms
        slowHigh = decay * slowHigh + (1 - decay) * hi
    }
}
