#!/usr/bin/env swift
// generate-icon.swift — Renders the QuadcastRGB app icon at all required sizes
// Usage: swift generate-icon.swift <output-directory>

import AppKit

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let px = pixels
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px) // 1:1 points-to-pixels (72 DPI)

    let gfx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gfx
    let ctx = gfx.cgContext

    let s = CGFloat(px)

    // ── Background: dark rounded rect with subtle gradient ──────────────
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.185
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(
        starting: NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
        ending: NSColor(red: 0.16, green: 0.16, blue: 0.22, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: -90)

    NSColor(white: 1.0, alpha: 0.06).setStroke()
    bgPath.lineWidth = s * 0.004
    bgPath.stroke()

    // ── Mic body ────────────────────────────────────────────────────────
    let micW = s * 0.42
    let micH = s * 0.48
    let micX = (s - micW) / 2
    let micY = s * 0.38

    let micRect = NSRect(x: micX, y: micY, width: micW, height: micH)
    let micPath = NSBezierPath(roundedRect: micRect, xRadius: micW / 2, yRadius: micW / 2)

    let micGradient = NSGradient(
        starting: NSColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1.0),
        ending: NSColor(red: 0.28, green: 0.28, blue: 0.34, alpha: 1.0)
    )!
    micGradient.draw(in: micPath, angle: 0)

    NSColor(white: 1.0, alpha: 0.1).setStroke()
    micPath.lineWidth = s * 0.005
    micPath.stroke()

    // ── LED strips (3 horizontal bars) ──────────────────────────────────
    let ledColors: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (1.0, 0.0, 0.3),   // Red-pink
        (0.0, 0.8, 1.0),   // Cyan
        (0.4, 0.0, 1.0),   // Purple
    ]

    let stripW = micW * 0.65
    let stripH = s * 0.028
    let stripX = (s - stripW) / 2
    let stripSpacing = micH * 0.22

    for i in 0..<3 {
        let stripY = micY + micH * 0.22 + CGFloat(i) * stripSpacing
        let stripRect = NSRect(x: stripX, y: stripY, width: stripW, height: stripH)
        let stripPath = NSBezierPath(roundedRect: stripRect, xRadius: stripH / 2, yRadius: stripH / 2)

        let c = ledColors[i]
        let ledColor = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
        ledColor.setFill()
        stripPath.fill()

        // Glow effect
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.03, color: ledColor.withAlphaComponent(0.6).cgColor)
        stripPath.fill()
        ctx.restoreGState()
    }

    // ── Stand/neck ──────────────────────────────────────────────────────
    let neckW = s * 0.08
    let neckH = s * 0.12
    let neckX = (s - neckW) / 2
    let neckY = micY - neckH

    let neckRect = NSRect(x: neckX, y: neckY, width: neckW, height: neckH)
    let neckPath = NSBezierPath(rect: neckRect)
    NSColor(red: 0.22, green: 0.22, blue: 0.26, alpha: 1.0).setFill()
    neckPath.fill()

    // ── Base ────────────────────────────────────────────────────────────
    let baseW = s * 0.36
    let baseH = s * 0.055
    let baseX = (s - baseW) / 2
    let baseY = neckY - baseH

    let baseRect = NSRect(x: baseX, y: baseY, width: baseW, height: baseH)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: baseH / 2, yRadius: baseH / 2)
    let baseGradient = NSGradient(
        starting: NSColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1.0),
        ending: NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0)
    )!
    baseGradient.draw(in: basePath, angle: -90)

    NSGraphicsContext.current = nil
    return rep
}

// ── Main ────────────────────────────────────────────────────────────────

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift generate-icon.swift <output-directory>")
    exit(1)
}

let outputDir = CommandLine.arguments[1]

// macOS icon sizes: (points, scale) → pixel size
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (points, scale) in sizes {
    let pixels = points * scale
    let rep = drawIcon(pixels: pixels)
    let filename = "icon_\(points)x\(points)@\(scale)x.png"
    let path = "\(outputDir)/\(filename)"

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("ERROR: Failed to create PNG for \(filename)")
        continue
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Generated \(filename) (\(pixels)x\(pixels)px)")
    } catch {
        print("ERROR: \(error)")
    }
}

print("Done.")
