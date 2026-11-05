import SwiftUI
import AVFoundation

/// The whole interface. One popover: a switch, a live preview, two click methods, and the
/// permissions it depends on. Nothing that needs a window.
struct PanelView: View {
    @ObservedObject var engine: PointerEngine
    @ObservedObject var settings: Settings
    @State private var cameras: [AVCaptureDevice] = []
    @State private var launchAtLogin = LaunchAtLogin.enabled
    @State private var tick = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            Divider()
            clicks
            Divider()
            permissions
            Divider()
            footer
        }
        .padding(14)
        .onAppear { cameras = HandTracker.availableCameras(); if settings.cameraID.isEmpty { settings.cameraID = cameras.first?.uniqueID ?? "" } }
        .onReceive(timer) { _ in tick += 1 }   // refreshes the permission rows while System Settings is open
    }

    private var header: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $settings.trackingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reach").font(.headline)
                    Text(engine.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.large)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                if settings.showPreview, let img = engine.preview {
                    GeometryReader { geo in
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .scaleEffect(x: settings.mirror ? -1 : 1, y: 1)
                        regionOverlay(in: geo.size)
                        if let hand = engine.lastHand { handOverlay(hand, in: geo.size) }
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: settings.trackingEnabled ? "hand.raised" : "camera")
                            .font(.title2).foregroundStyle(.secondary)
                        Text(settings.trackingEnabled ? "Show a hand to the camera" : "Turn on to see the camera")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 150)

            HStack {
                Picker("", selection: $settings.cameraID) {
                    ForEach(cameras, id: \.uniqueID) { Text(cameraLabel($0)).tag($0.uniqueID) }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                Spacer()
                if engine.calibration == .idle {
                    Button("Calibrate") { engine.beginCalibration() }
                        .disabled(!settings.trackingEnabled)
                        .help("Point at the top-left corner, hold, then the bottom-right. The space between becomes the whole screen.")
                } else {
                    Button("Cancel") { engine.cancelCalibration() }
                }
            }
            HStack {
                Text("Smoothing").font(.caption)
                Slider(value: $settings.smoothing, in: 0...1)
                Text(engine.handVisible ? "\(Int(engine.fps)) fps" : " ").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            if engine.handVisible {
                // The numbers the thresholds see. Pinch fires below 0.40, releases above 0.52.
                HStack(spacing: 10) {
                    Text(String(format: "pinch %.2f", engine.pinchRatio))
                    Text(engine.handRaised ? "raised" : "resting")
                    if engine.lastTapOnset > 0 { Text(String(format: "tap %.0fx", engine.lastTapOnset)) }
                }
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
    }

    private func cameraLabel(_ d: AVCaptureDevice) -> String {
        d.deviceType == .deskViewCamera ? "Desk View (wide, looks down)" : d.localizedName
    }

    private func regionOverlay(in size: CGSize) -> some View {
        let r = settings.region
        // Preview is drawn mirrored when `mirror` is on and the region is stored in
        // already-mirrored coordinates, so it maps straight onto the mirrored image.
        let rect = CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height,
                          width: r.width * size.width, height: r.height * size.height)
        return RoundedRectangle(cornerRadius: 4)
            .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func handOverlay(_ hand: HandSample, in size: CGSize) -> some View {
        var tip = hand.indexTip, thumb = hand.thumbTip
        if settings.mirror { tip.x = 1 - tip.x; thumb.x = 1 - thumb.x }
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: tip.x * size.width, y: (1 - tip.y) * size.height))
                p.addLine(to: CGPoint(x: thumb.x * size.width, y: (1 - thumb.y) * size.height))
            }.stroke(Color.white.opacity(0.7), lineWidth: 1.5)
            Circle().fill(engine.pinching ? Color.accentColor : Color.white)
                .frame(width: 12, height: 12)
                .position(x: tip.x * size.width, y: (1 - tip.y) * size.height)
            Circle().fill(Color.white.opacity(0.8))
                .frame(width: 8, height: 8)
                .position(x: thumb.x * size.width, y: (1 - thumb.y) * size.height)
        }
    }

    private var clicks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Click").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            Toggle(isOn: $settings.pinchToClick) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pinch")
                    Text("Thumb to index. Hold to drag.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.tapSoundToClick) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tap the glass")
                    Text("The mics hear the tap, the camera knows where.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.tapSoundToClick) { _, on in
                if on, Permissions.microphone != .authorized { Permissions.requestMicrophone { _ in } }
            }
            if settings.tapSoundToClick {
                HStack {
                    Text("Tap sensitivity").font(.caption)
                    Slider(value: $settings.tapSensitivity, in: 0...1)
                    Text(engine.tapCount > 0 ? "\(engine.tapCount)" : " ").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 6) {
            let _ = tick
            permissionRow("Camera", ok: Permissions.camera == .authorized) {
                if Permissions.camera == .notDetermined { Permissions.requestCamera { _ in } } else { Permissions.openCameraSettings() }
            }
            permissionRow("Accessibility", ok: Permissions.accessibility, detail: "Moves the pointer and clicks") {
                Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
            }
            if settings.tapSoundToClick {
                permissionRow("Microphone", ok: Permissions.microphone == .authorized) {
                    if Permissions.microphone == .notDetermined { Permissions.requestMicrophone { _ in } }
                    else if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(u) }
                }
            }
        }
    }

    private func permissionRow(_ name: String, ok: Bool, detail: String? = nil, fix: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.callout)
                if let detail, !ok { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !ok { Button("Allow…", action: fix).controlSize(.small) }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox).controlSize(.small)
                .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.enabled = v }
            Spacer()
            Menu {
                Toggle("Mirror camera", isOn: $settings.mirror)
                Toggle("Show preview", isOn: $settings.showPreview)
                Button("Reset calibration") { settings.resetRegion() }
                Button("Show signal log") { NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.shared.url]) }
                Divider()
                Link("Source on GitHub", destination: URL(string: "https://github.com/mrivanlizarde/reach")!)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
            Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
        }
    }
}
