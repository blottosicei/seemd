#!/usr/bin/env swift
// Generates the DMG install-window background image (dark canvas + centered
// arrow + tagline). Run as: swift scripts/make-dmg-bg.swift <out.png>
// Window content is 720x420; icons sit at (180,180) and (540,180) in DMG
// coordinates (origin top-left for Finder positions), so the arrow is drawn at
// the matching vertical center between them.

import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.dropFirst().first ?? "dmg-background.png"
let w: CGFloat = 720
let h: CGFloat = 420

let image = NSImage(size: NSSize(width: w, height: h))
image.lockFocus()

// Background — match seemd's toned dark, no pure black
NSColor(red: 0.078, green: 0.086, blue: 0.106, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()

// Subtle hairline at the bottom for a finished feel
NSColor(white: 1.0, alpha: 0.04).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: 1)).fill()

// Centered arrow between the two icon positions
let arrowColor = NSColor(white: 0.55, alpha: 0.85)
let startX: CGFloat = 305
let endX: CGFloat = 415
// Finder positions are top-left origin; NSImage drawing is bottom-left.
// Icons placed at y=180 (top-left) → vertical center ≈ y=h-180-32 (image space).
let y: CGFloat = h - 180 - 28

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: startX, y: y))
shaft.line(to: NSPoint(x: endX - 14, y: y))
shaft.lineWidth = 3
shaft.lineCapStyle = .round
arrowColor.setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: endX - 16, y: y + 10))
head.line(to: NSPoint(x: endX, y: y))
head.line(to: NSPoint(x: endX - 16, y: y - 10))
head.lineWidth = 3
head.lineJoinStyle = .round
head.lineCapStyle = .round
arrowColor.setStroke()
head.stroke()

// Tagline beneath the icons
let tagline = "Drag seemd to Applications to install"
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(white: 0.6, alpha: 0.7),
    .paragraphStyle: para,
]
NSAttributedString(string: tagline, attributes: attrs)
    .draw(in: NSRect(x: 0, y: 72, width: w, height: 22))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render PNG\n".utf8))
    exit(2)
}

try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
