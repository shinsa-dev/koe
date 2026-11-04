// usage: swift scripts/icon.swift — writes Resources/Koe.icns: a waveform on a blue squircle, until Koe has a real icon.
import AppKit

let out = URL(fileURLWithPath: "Resources/Koe.iconset")
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(side)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.55, blue: 1, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.33, blue: 0.93, alpha: 1)])!.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = glyph.size
        glyph.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2,
                              width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", out.path, "-o", "Resources/Koe.icns"]
try task.run()
task.waitUntilExit()
try FileManager.default.removeItem(at: out)
