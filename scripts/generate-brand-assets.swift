#!/usr/bin/env swift

import AppKit
import Foundation

// Production masters are checked in; rebuilding never calls an image service.
private enum AssetError: Error {
    case invalidMaster(String)
    case bitmapCreation
    case pngEncoding
    case iconutilFailed(Int32)
}

private func writePNG(_ image: NSImage, size: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw AssetError.bitmapCreation
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw AssetError.pngEncoding
    }
    try png.write(to: url)
}

private let projectRoot = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? FileManager.default.currentDirectoryPath,
    isDirectory: true
)
private let assets = projectRoot.appending(path: "Packaging/Assets", directoryHint: .isDirectory)
private let iconset = assets.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

private func master(_ name: String) throws -> NSImage {
    guard let image = NSImage(contentsOf: assets.appending(path: name)) else {
        throw AssetError.invalidMaster(name)
    }
    return image
}

let icon = try master("ZikiIcon-1024.png")
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1_024)
]
for (filename, size) in variants {
    try writePNG(icon, size: size, to: iconset.appending(path: filename))
}
try writePNG(
    master("ZikiMenuBarMaster.png"), size: 36,
    to: assets.appending(path: "ZikiMenuBarTemplate.png")
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", assets.appending(path: "AppIcon.icns").path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw AssetError.iconutilFailed(iconutil.terminationStatus)
}
print("Generated Ziki brand assets in \(assets.path)")
