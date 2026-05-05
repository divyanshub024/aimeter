#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    fputs("Usage: scripts/generate_dmg_background.swift /path/to/background.png\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = outputURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let width = 720
let height = 420

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
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
    fputs("Could not create DMG background bitmap.\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGraphicsContext.current?.imageInterpolation = .high

NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1).setFill()
canvas.fill()

let title = "Install AIMeter"
let subtitle = "Drag AIMeter into Applications"

drawCenteredText(
    title,
    y: 332,
    font: NSFont.systemFont(ofSize: 28, weight: .bold),
    color: NSColor.white.withAlphaComponent(0.94)
)
drawCenteredText(
    subtitle,
    y: 300,
    font: NSFont.systemFont(ofSize: 15, weight: .medium),
    color: NSColor.white.withAlphaComponent(0.58)
)

drawDropZone(center: NSPoint(x: 180, y: 205))
drawDropZone(center: NSPoint(x: 540, y: 205))
drawArrow()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode DMG background PNG.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
print("Generated DMG background at \(outputURL.path)")

func drawCenteredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    text.draw(
        in: NSRect(x: 0, y: y, width: CGFloat(width), height: 40),
        withAttributes: attributes
    )
}

func drawDropZone(center: NSPoint) {
    let rect = NSRect(x: center.x - 67, y: center.y - 67, width: 134, height: 134)
    let path = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
    NSColor.white.withAlphaComponent(0.04).setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = 1
    path.stroke()
}

func drawArrow() {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 292, y: 214))
    path.curve(
        to: NSPoint(x: 428, y: 214),
        controlPoint1: NSPoint(x: 330, y: 250),
        controlPoint2: NSPoint(x: 390, y: 250)
    )
    NSColor(calibratedRed: 0.05, green: 0.65, blue: 0.91, alpha: 0.95).setStroke()
    path.lineWidth = 6
    path.lineCapStyle = .round
    path.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 428, y: 214))
    head.line(to: NSPoint(x: 407, y: 231))
    head.move(to: NSPoint(x: 428, y: 214))
    head.line(to: NSPoint(x: 408, y: 196))
    head.lineWidth = 6
    head.lineCapStyle = .round
    head.stroke()
}
