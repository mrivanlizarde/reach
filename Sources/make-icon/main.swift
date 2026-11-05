import AppKit
import CoreGraphics
import Foundation

// Draws the Reach app icon: a fingertip's point of contact on glass. A dark rounded square,
// one soft ring where the finger lands, and a small bright dot at the centre. Abstract,
// not a drawn hand. Reads at 16pt as a dot in a ring, which is exactly what it is.
//
//   make-icon <output-directory>

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("icon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func draw(size: CGFloat) -> CGImage? {
    let s = size / 1024.0
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let body = rect.insetBy(dx: 62 * s, dy: 62 * s)
    let path = CGPath(roundedRect: body, cornerWidth: 228 * s, cornerHeight: 228 * s, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1), CGColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    let c = CGPoint(x: size / 2, y: size / 2 - 20 * s)
    // Contact rings: a pressed fingertip spreads, so the rings fade outward.
    for (i, r) in [300.0, 220.0, 150.0].enumerated() {
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.18 + 0.18 * Double(i)))
        ctx.setLineWidth((14 + CGFloat(i) * 4) * s)
        ctx.addEllipse(in: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s))
        ctx.strokePath()
    }
    // The touch itself.
    ctx.setFillColor(CGColor(red: 0.62, green: 0.82, blue: 1.0, alpha: 1))
    let dot = 84 * s
    ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: 2 * dot, height: 2 * dot))
    return ctx.makeImage()
}

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                   (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    guard let img = draw(size: CGFloat(px)) else { continue }
    let rep = NSBitmapImageRep(cgImage: img)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: outDir.appendingPathComponent("icon_\(name).png"))
    }
}
print("icons written to \(outDir.path)")
