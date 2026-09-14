import AppKit
import SwiftUI
import ZikiAppCore

/// A quiet paper-and-ink palette; semantic states retain their native colors.
enum ZikiTheme {
    static let paper = adaptive("paper", light: 0xF7F6F2, dark: 0x1D1E1C)
    static let sidebar = adaptive("sidebar", light: 0xEFEEE9, dark: 0x242521)
    static let surface = adaptive("surface", light: 0xFFFFFF, dark: 0x292A26)
    static let ink = adaptive("ink", light: 0x242622, dark: 0xF1F0E9)
    static let line = adaptive("line", light: 0xDEDCD4, dark: 0x41423C)
    static let selection = adaptive("selection", light: 0xDEDCD4, dark: 0x3B3D35)

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: "Ziki.\(name)") { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark : light
            return NSColor(
                srgbRed: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension SettingsPane {
    var heading: String {
        switch self {
        case .start: "把想法说出来。"
        case .history: "听写历史"
        case .speech: "你的表达习惯"
        case .providers: "连接你的模型"
        case .privacy: "数据，由你掌握"
        case .about: "关于 Ziki"
        }
    }

    var subtitle: String {
        switch self {
        case .start: "自然地说，留下清楚、有条理的文字。"
        case .history: "最终文字仅保存在本机，30 天后自动删除。"
        case .speech: "从倾听到成文，让 Ziki 按你的习惯工作。"
        case .providers: "使用自己的百炼 API Key，连接语音识别与文字整理。"
        case .privacy: "清楚知道哪些留在本机，哪些会交给模型处理。"
        case .about: "一个专注于倾听与表达的 macOS 原生工具。"
        }
    }

    var accessibilityName: String {
        switch self {
        case .start: "start"
        case .history: "history"
        case .speech: "speech"
        case .providers: "providers"
        case .privacy: "privacy"
        case .about: "about"
        }
    }
}

extension View {
    func zikiCard() -> some View {
        background(ZikiTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ZikiTheme.line.opacity(0.7), lineWidth: 1)
            }
    }
}

struct ZikiMark: View {
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Text("Z").font(.system(size: size * 0.65, design: .serif))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}
