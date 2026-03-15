#!/usr/bin/env swift
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath

func renderIcon(pixels: Int) -> Data {
    let s = CGFloat(pixels)

    // Use NSBitmapImageRep directly so we get exact pixel dimensions,
    // regardless of the display's backing scale factor.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Dark navy background with rounded corners
    NSColor(srgbRed: 0.09, green: 0.12, blue: 0.22, alpha: 1.0).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
        xRadius: s * 0.22, yRadius: s * 0.22
    ).fill()

    // Gamecontroller SF Symbol in white
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.40, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sz = sym.size
        sym.draw(in: NSRect(
            x: (s - sz.width) / 2,
            y: (s - sz.height) / 2,
            width: sz.width, height: sz.height
        ))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// (pixel size, filename)
let icons: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixels, name) in icons {
    let data = renderIcon(pixels: pixels)
    let path = (outDir as NSString).appendingPathComponent(name)
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("  ✓ \(name) (\(pixels)px)")
    } catch {
        fputs("Error writing \(name): \(error)\n", stderr)
        exit(1)
    }
}
