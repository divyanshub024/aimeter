#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSlot {
    let name: String
    let pixels: Int
}

let slots = [
    IconSlot(name: "icon_16x16.png", pixels: 16),
    IconSlot(name: "icon_16x16@2x.png", pixels: 32),
    IconSlot(name: "icon_32x32.png", pixels: 32),
    IconSlot(name: "icon_32x32@2x.png", pixels: 64),
    IconSlot(name: "icon_128x128.png", pixels: 128),
    IconSlot(name: "icon_128x128@2x.png", pixels: 256),
    IconSlot(name: "icon_256x256.png", pixels: 256),
    IconSlot(name: "icon_256x256@2x.png", pixels: 512),
    IconSlot(name: "icon_512x512.png", pixels: 512),
    IconSlot(name: "icon_512x512@2x.png", pixels: 1024)
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root
    .appendingPathComponent("Sources/AIMeter/Resources/Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    let image = renderIconBitmap(pixels: slot.pixels)
    let destination = outputDirectory.appendingPathComponent(slot.name)
    try writePNG(image, to: destination)
}

print("Generated \(slots.count) app icon images in \(outputDirectory.path)")

func renderIconBitmap(pixels: Int) -> NSBitmapImageRep {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        fatalError("Could not create bitmap context for \(pixels)x\(pixels) icon.")
    }

    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSGraphicsContext.current?.imageInterpolation = .high

    let tileInset = CGFloat(pixels) * 0.085
    let tileRect = canvas.insetBy(dx: tileInset, dy: tileInset)
    let radius = CGFloat(pixels) * 0.20
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)

    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1).setFill()
    tilePath.fill()

    NSColor.white.withAlphaComponent(0.12).setStroke()
    tilePath.lineWidth = max(1, CGFloat(pixels) * 0.018)
    tilePath.stroke()

    let center = NSPoint(x: CGFloat(pixels) * 0.50, y: CGFloat(pixels) * 0.414)
    let radiusMeter = CGFloat(pixels) * 0.255
    let meterRect = NSRect(
        x: center.x - radiusMeter,
        y: center.y - radiusMeter,
        width: radiusMeter * 2,
        height: radiusMeter * 2
    )
    let meterLineWidth = max(2, CGFloat(pixels) * 0.074)

    let backgroundArc = NSBezierPath()
    backgroundArc.appendArc(
        withCenter: center,
        radius: radiusMeter,
        startAngle: 0,
        endAngle: 180,
        clockwise: false
    )
    NSColor.white.withAlphaComponent(0.18).setStroke()
    backgroundArc.lineWidth = meterLineWidth
    backgroundArc.lineCapStyle = .round
    backgroundArc.stroke()

    let accentArc = NSBezierPath()
    accentArc.appendArc(
        withCenter: center,
        radius: radiusMeter,
        startAngle: 180,
        endAngle: 44,
        clockwise: true
    )
    NSColor(calibratedRed: 0.05, green: 0.65, blue: 0.91, alpha: 1).setStroke()
    accentArc.lineWidth = meterLineWidth
    accentArc.lineCapStyle = .round
    accentArc.stroke()

    let needleAngle = CGFloat(44) * .pi / 180
    let needleLength = radiusMeter * 0.82
    let needleEnd = NSPoint(
        x: center.x + cos(needleAngle) * needleLength,
        y: center.y + sin(needleAngle) * needleLength
    )
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: needleEnd)
    NSColor.white.withAlphaComponent(0.96).setStroke()
    needle.lineWidth = max(2, CGFloat(pixels) * 0.038)
    needle.lineCapStyle = .round
    needle.stroke()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - CGFloat(pixels) * 0.047,
        y: center.y - CGFloat(pixels) * 0.047,
        width: CGFloat(pixels) * 0.094,
        height: CGFloat(pixels) * 0.094
    )).fill()

    NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - CGFloat(pixels) * 0.019,
        y: center.y - CGFloat(pixels) * 0.019,
        width: CGFloat(pixels) * 0.038,
        height: CGFloat(pixels) * 0.038
    )).fill()

    _ = meterRect
    return bitmap
}

func writePNG(_ image: NSBitmapImageRep, to url: URL) throws {
    guard
        let pngData = image.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "AIMeterIconGeneration",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG for \(url.lastPathComponent)."]
        )
    }

    try pngData.write(to: url)
}
