#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let plist = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: root.appending(path: "Packaging/Info.plist")),
    format: nil
) as! [String: Any]
for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
    precondition(plist[key] as? String == "Ziki", "Old product name in \(key)")
}
precondition(plist["CFBundleIdentifier"] as? String == "com.willhong.sotto", "Stable identity changed")

for (name, size, isTemplate) in [
    ("ZikiIcon-1024.png", 1024, false),
    ("AppIcon.iconset/icon_16x16.png", 16, false),
    ("ZikiMenuBarTemplate.png", 36, true)
] {
    let data = try Data(contentsOf: root.appending(path: "Packaging/Assets/\(name)"))
    let bitmap = NSBitmapImageRep(data: data)!
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
