import AppKit
import SwiftUI
import ZikiCore
import ZikiAppCore

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var outputMute: RecordingOutputMute

    var body: some View {
        Text(statusLine)
            .foregroundStyle(.secondary)

        Divider()

        Button(actionTitle) {
            if model.phase == .listening {
                model.finishDictation()
            } else {
                model.toggleDictation()
            }
        }
        .disabled(primaryActionDisabled)

        if model.phase == .listening {
            Button("取消听写", role: .cancel) {
                model.cancelDictation()
            }
        }

        Button("复制上次结果") {
            model.copyLastResult()
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled(model.lastResult == nil)

        Button("听写历史…") {
            model.openHistory()
        }

        Button("开始新对话（清空上下文）") {
            model.clearDictationContext()
        }
        .disabled(model.phase != .idle)

        Divider()

        if let notice = outputMute.notice {
            Text(notice)
        }
        if outputMute.hasPendingRecovery && model.phase == .idle {
            Button("恢复上次由 Ziki 静音的设备") { outputMute.recoverPending() }
        }

        Button("设置…") {
            model.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("退出 Ziki") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var statusLine: String {
        switch model.phase {
        case .idle: "就绪 · \(settings.provider.title)"
        case .listening: DictationOverlayCopy.listening
        case .processing, .polishing: DictationOverlayCopy.thinking
        case .inserting: "就绪"
        case .success: "就绪"
        case .cancelled: "已取消"
        case let .error(message, _): message
        }
    }

    private var actionTitle: String {
        switch model.phase {
        case .idle: "开始听写"
        case .listening: "完成听写"
        case .processing, .polishing: DictationOverlayCopy.thinking
        case .inserting: "开始听写"
        case .success: "开始听写"
        case .cancelled: "已取消"
        case .error: "暂不可用"
        }
    }

    private var primaryActionDisabled: Bool {
        switch model.phase {
        case .idle:
            !model.canStart
        case .listening:
            false
        case .processing, .polishing, .inserting, .success, .cancelled, .error:
            true
        }
    }
}
