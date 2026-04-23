#!/usr/bin/env swift
// make-icon.swift — Generate Loft app icon at all required sizes.
// Composites scripts/assets/loft-airplane.png (alpha-cut subject) onto a
// teal→deep-blue gradient squircle. Run: swift scripts/make-icon.swift

import AppKit
import CoreGraphics

func hexColor(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
    if h.count == 6 { h += "FF" }
    var value: UInt64 = 0
    Scanner(string: h).scanHexInt64(&value)
    let r = CGFloat((value >> 24) & 0xFF) / 255
    let g = CGFloat((value >> 16) & 0xFF) / 255
    let b = CGFloat((value >>  8) & 0xFF) / 255
    let a = CGFloat((value      ) & 0xFF) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// MARK: - Main setup

let args = CommandLine.arguments
let scriptPath = args[0]
let repoRoot: String = {
    if scriptPath.hasPrefix("/") {
        let parts = scriptPath.split(separator: "/", omittingEmptySubsequences: false)
        return "/" + parts.dropLast(2).joined(separator: "/")
    }
    return FileManager.default.currentDirectoryPath
}()

let planeURL = URL(fileURLWithPath: "\(repoRoot)/scripts/assets/loft-airplane.png")
guard let planeImage = NSImage(contentsOf: planeURL),
      let planeTIFF = planeImage.tiffRepresentation,
      let planeRep = NSBitmapImageRep(data: planeTIFF),
      let planeCG = planeRep.cgImage else {
    fputs("Error: could not load \(planeURL.path)\n", stderr)
    exit(1)
}

func renderIcon(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cgCtx = ctx.cgContext
    cgCtx.interpolationQuality = .high

    // Background: rounded rect, full bleed, clipped to squircle-ish shape
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                        transform: nil)
    cgCtx.saveGState()
    cgCtx.addPath(bgPath)
    cgCtx.clip()

    let teal     = hexColor("#0EA5E9").cgColor
    let deepBlue = hexColor("#1E3A8A").cgColor
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [teal, deepBlue] as CFArray,
                              locations: [0, 1])!
    cgCtx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end:   CGPoint(x: s, y: s),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Composite the paper-airplane PNG centered with ~8% padding.
    let planeCanvasFraction: CGFloat = 1.02
    let planeSize = s * planeCanvasFraction
    let planeX = (s - planeSize) / 2
    let planeY = (s - planeSize) / 2

    cgCtx.saveGState()
    cgCtx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.015),
        blur: s * 0.03,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    )
    cgCtx.draw(planeCG, in: CGRect(x: planeX, y: planeY, width: planeSize, height: planeSize))
    cgCtx.restoreGState()

    cgCtx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

struct IconSize {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String {
        scale == 2 ? "icon_\(points)x\(points)@2x.png" : "icon_\(points)x\(points).png"
    }
}

let sizes: [IconSize] = [
    IconSize(points: 16,  scale: 1), IconSize(points: 16,  scale: 2),
    IconSize(points: 32,  scale: 1), IconSize(points: 32,  scale: 2),
    IconSize(points: 128, scale: 1), IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1), IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1), IconSize(points: 512, scale: 2),
]

let iconsetDir = "\(repoRoot)/build/AppIcon.iconset"
do {
    try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
} catch {
    fputs("Error: could not create iconset dir: \(error)\n", stderr)
    exit(1)
}

for sz in sizes {
    let rep = renderIcon(size: sz.pixels)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Error: could not encode PNG for \(sz.filename)\n", stderr)
        exit(1)
    }
    let path = "\(iconsetDir)/\(sz.filename)"
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("  wrote \(sz.filename) (\(sz.pixels)×\(sz.pixels))")
    } catch {
        fputs("Error writing \(path): \(error)\n", stderr)
        exit(1)
    }
}

print("✓ Iconset written to \(iconsetDir)")
