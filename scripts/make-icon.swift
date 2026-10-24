#!/usr/bin/env swift
//
// Generates AppIcon.icns without any third party tooling.
//
//   swift scripts/make-icon.swift Resources/AppIcon.icns
//
// The artwork is deliberately simple: a dark rounded square with two usage bars,
// one for the 5 hour window and one for the week. It reads at 16 pt in Finder
// and has no text, so it needs no font licence and no localisation.

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

let fm = FileManager.default
let workDir = fm.temporaryDirectory.appendingPathComponent("usagebar-icon-\(UUID().uuidString)")
let iconsetDir = workDir.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// MARK: - Drawing

/// Renders the icon at `size` points into a PNG file.
func renderPNG(size: Int, to url: URL) {
    let pixels = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        fatalError("cannot allocate bitmap")
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)

    // macOS icons are drawn inside ~82% of the canvas; the rest is padding.
    let inset = pixels * 0.09
    let plate = canvas.insetBy(dx: inset, dy: inset)
    let corner = plate.width * 0.225
    let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

    let background = NSGradient(
        starting: NSColor(srgbRed: 0.09, green: 0.11, blue: 0.20, alpha: 1),
        ending: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.38, alpha: 1)
    )
    background?.draw(in: platePath, angle: -90)

    // Two quota bars, same idea as the menu: the filled part shows usage.
    func bar(y: CGFloat, height: CGFloat, fill: CGFloat, color: NSColor) {
        let padding = plate.width * 0.16
        let width = plate.width - padding * 2
        let rect = NSRect(x: plate.minX + padding,
                          y: y,
                          width: width,
                          height: height)
        let radius = height / 2

        NSColor(white: 1, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        let filled = NSRect(x: rect.minX, y: rect.minY, width: width * fill, height: height)
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    let barHeight = plate.height * 0.13
    bar(y: plate.midY + plate.height * 0.06,
        height: barHeight,
        fill: 0.62,
        color: NSColor(srgbRed: 0.20, green: 0.83, blue: 0.60, alpha: 1))
    bar(y: plate.midY - plate.height * 0.06 - barHeight,
        height: barHeight,
        fill: 0.28,
        color: NSColor(srgbRed: 0.96, green: 0.65, blue: 0.14, alpha: 1))

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode PNG")
    }
    try? png.write(to: url)
}

// MARK: - Iconset

/// The names `iconutil` expects, with the point size and scale of each entry.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    renderPNG(size: variant.size, to: iconsetDir.appendingPathComponent(variant.name))
}

// MARK: - Compile

let outputURL = URL(fileURLWithPath: outputPath)
try? fm.createDirectory(at: outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

try? fm.removeItem(at: workDir)

if iconutil.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("wrote \(outputURL.path)")
