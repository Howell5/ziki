#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func image(_ relativePath: String) -> NSBitmapImageRep {
    let path = root.appending(path: relativePath)
    return try! NSBitmapImageRep(data: Data(contentsOf: path))!
}

let plist = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: root.appending(path: "Packaging/Info.plist")),
    format: nil
) as! [String: Any]
for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
    precondition(plist[key] as? String == "Ziki", "Old product name in \(key)")
}
precondition(plist["CFBundleIdentifier"] as? String == "com.willhong.sotto", "Stable identity changed")

let master = image("website/design/ziki-ink.png")
precondition(master.pixelsWide == master.pixelsHigh, "Brand master is not square")
var darkNeutralPixels = 0
var lightNeutralPixels = 0
for y in 0..<master.pixelsHigh {
    for x in 0..<master.pixelsWide {
        let color = master.colorAt(x: x, y: y)!
        let channels = [color.redComponent, color.greenComponent, color.blueComponent]
        let spread = channels.max()! - channels.min()!
        if channels.max()! < 0.35 {
            darkNeutralPixels += 1
            precondition(spread <= 0.08, "Ink is not neutral-colored")
        } else if channels.min()! > 0.8 {
            lightNeutralPixels += 1
            precondition(spread <= 0.08, "Paper is not neutral-colored")
        }
    }
}
precondition(darkNeutralPixels > 0 && lightNeutralPixels > 0, "Master lacks ink or paper")

let appIcon = image("Packaging/Assets/ZikiIcon-1024.png")
let representativePoints = [0.10, 0.30, 0.50, 0.70, 0.90]
for fraction in representativePoints {
    let masterX = Int(fraction * Double(master.pixelsWide - 1))
    let masterY = Int(fraction * Double(master.pixelsHigh - 1))
    let iconX = Int(fraction * Double(appIcon.pixelsWide - 1))
    let iconY = Int(fraction * Double(appIcon.pixelsHigh - 1))
    let source = master.colorAt(x: masterX, y: masterY)!
    let derived = appIcon.colorAt(x: iconX, y: iconY)!
    let differences = [
        abs(source.redComponent - derived.redComponent),
        abs(source.greenComponent - derived.greenComponent),
        abs(source.blueComponent - derived.blueComponent)
    ]
    precondition(differences.max()! <= 0.08, "App icon differs from master at representative point")
}

for (name, size, isTemplate) in [
    ("ZikiIcon-1024.png", 1024, false),
    ("AppIcon.iconset/icon_16x16.png", 16, false),
    ("ZikiMenuBarTemplate.png", 36, true)
] {
    let bitmap = image("Packaging/Assets/\(name)")
    precondition(bitmap.pixelsWide == size && bitmap.pixelsHigh == size, "Wrong size: \(name)")
    var opaque = 0
    var transparent = 0
    for y in 0..<size {
        for x in 0..<size {
            let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
            if alpha > 0.9 { opaque += 1 }
            if alpha < 0.1 { transparent += 1 }
        }
    }
    if isTemplate {
        // A blank asset or opaque square must not become a menu bar template.
        precondition(opaque > size * size / 10 && transparent > size * size / 4, "Invalid template alpha")
    } else {
        precondition(opaque == size * size, "Icon has damaged transparency")
    }
}
print("PASS: Ziki bundle identity, icon sizes, opaque master and transparent menu template")
