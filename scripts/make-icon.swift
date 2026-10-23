// Renders the 1024 px app icon. Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png")

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext

// macOS icon grid: an 824 pt rounded square centred on the canvas, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
context.addPath(shape)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
// Near-black #0F0F10, a touch lighter at the top.
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [
        NSColor(srgbRed: 0.145, green: 0.145, blue: 0.155, alpha: 1).cgColor,
        NSColor(srgbRed: 0.059, green: 0.059, blue: 0.063, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

// A hairline edge so the icon doesn't disappear on dark backgrounds.
context.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
context.setLineWidth(4)
context.strokePath()
context.restoreGState()

// Glyph: two stacked photos in white.
let configuration = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)!
    .withSymbolConfiguration(configuration)!
let symbolSize = symbol.size
let symbolRect = CGRect(
    x: (size - symbolSize.width) / 2,
    y: (size - symbolSize.height) / 2 - 6,
    width: symbolSize.width,
    height: symbolSize.height
)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.4).cgColor)
symbol.draw(in: symbolRect)
context.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
