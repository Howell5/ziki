import AppKit
import ZikiAppCore
import SwiftUI
import ZikiCore

struct SettingsRootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var navigation: SettingsNavigationState

    private var selection: SettingsPane { navigation.selection ?? .start }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(ZikiTheme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.heading)
                        .font(.system(size: 27, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(selection.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)

                Group {
                    switch selection {
                    case .start: StartSettingsView()
                    case .history: DictationHistoryView()
                    case .speech: SpeechSettingsView()
                    case .providers: ProviderSettingsView()
                    case .privacy: PrivacySettingsView()
                    case .about: AboutSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 800, minHeight: 580)
        .foregroundStyle(ZikiTheme.ink)
        .tint(ZikiTheme.ink)
        .background(ZikiTheme.paper)
        .task {
            permissions.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZikiMark(size: 38)
                Text("Ziki")
                    .font(.system(size: 25, weight: .medium, design: .serif))
            }
            .padding(.horizontal, 10)
            .padding(.top, 28)
            .padding(.bottom, 32)

            VStack(spacing: 5) {
                ForEach(Array(SettingsPane.allCases.enumerated()), id: \.element.id) { index, pane in
                    Button {
                        navigation.selection = pane
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pane.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                            Text(pane.rawValue)
                                .font(.system(size: 14, weight: selection == pane ? .semibold : .regular))
                            Spacer(minLength: 0)
                            if selection == pane {
                                Circle().fill(ZikiTheme.ink).frame(width: 4, height: 4)
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                        .background(
                            selection == pane ? ZikiTheme.selection : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .accessibilityIdentifier("settings-\(pane.accessibilityName)")
                    .accessibilityAddTraits(selection == pane ? .isSelected : [])
                    .help("\(pane.rawValue) · ⌘\(index + 1)")
                }
            }
            .onMoveCommand { direction in
                let panes = SettingsPane.allCases
                guard let index = panes.firstIndex(of: selection) else { return }
                if direction == .down { navigation.selection = panes[min(index + 1, panes.count - 1)] }
                if direction == .up { navigation.selection = panes[max(index - 1, 0)] }
            }

            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text("不止听见，更懂你。")
                    .font(.system(size: 12, weight: .medium))
                Text("为自然表达而作")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 12)
        .frame(width: 184)
        .background(ZikiTheme.sidebar)
    }
}

private struct StartSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var navigation: SettingsNavigationState

    private var isReady: Bool {
        permissions.microphone == .granted
            && permissions.accessibility == .granted && model.canStart
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    Text("fn")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .frame(width: 68, height: 68)
                        .background(ZikiTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ZikiTheme.line))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("一按，说话。再按，成文。")
                            .font(.system(size: 19, weight: .medium))
                        Text("在输入框中单击 fn 开始听写，再按一次完成。\nZiki 整理表达后，写入当前输入位置。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(22)
                .zikiCard()

                Text("准备好这三件事")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    PermissionRow(
                        kind: .microphone,
                        title: "麦克风",
                        detail: "只在你主动开始听写时使用",
                        state: permissions.microphone
                    )
                    Divider().padding(.leading, 44)
                    PermissionRow(
                        kind: .accessibility,
                        title: "辅助功能",
                        detail: "写入文字，并识别独立的 fn 按键",
                        state: permissions.accessibility
                    )
                }
                .padding(.vertical, 4)
                .zikiCard()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("连接百炼")
                            .font(.headline)
                        Text(settings.provider.title)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.canStart ? "checkmark.circle.fill" : "key.horizontal")
                        .foregroundStyle(model.canStart ? Color.green : Color.orange)
                    Text(model.canStart ? "已配置" : "需要完整服务配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("配置") { navigation.selection = .providers }
                }
                .padding(16)
                .zikiCard()

                HStack(spacing: 12) {
                    Label(isReady ? "已就绪，随时开始表达" : "完成授权与配置，即可开始", systemImage: isReady ? "checkmark.circle" : "circle.dotted")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(settings.onboardingComplete ? "设置已完成" : "完成设置") {
                        settings.onboardingComplete = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady || settings.onboardingComplete)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }
}

private struct PermissionRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var permissions: PermissionCenter

    let kind: AppPermissionKind
    let title: String
    let detail: String
    let state: PermissionCenter.State

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(state == .granted ? Color.green : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(effectiveDetail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state == .granted {
                Text("已允许")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if permissions.isRequesting(kind) {
                ProgressView()
                    .controlSize(.small)
                Text("等待授权")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if permissions.action(for: kind) == .unavailable {
                Text(state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(actionTitle) {
                    Task {
                        let result = await permissions.perform(kind)
                        if result == .completedInApp {
                            model.restoreSettingsAfterPermissionPrompt()
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private var actionTitle: String {
        switch permissions.action(for: kind) {
        case .request: "允许"
        case .openSystemSettings: "打开设置"
        case .none: "已允许"
        case .unavailable: state.title
        }
    }

    private var effectiveDetail: String {
        switch state {
        case .restricted:
            "这项权限被系统策略或设备管理限制"
        case .misconfigured:
            "请运行打包并签名后的 Ziki.app"
        default:
            detail
        }
    }
}

private struct SpeechSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var outputMute: RecordingOutputMute

    var body: some View {
        Form {
            Section("识别") {
                Picker("语言", selection: $settings.languageRawValue) {
                    Text("自动识别").tag(ASRLanguage.automatic.rawValue)
                    Text("中文").tag(ASRLanguage.chinese.rawValue)
                    Text("English").tag(ASRLanguage.english.rawValue)
                }
                LabeledContent("快捷键") {
                    Text("单击 fn 开始／结束")
                        .foregroundStyle(.secondary)
                }
            }

            Section("录音时的声音") {
                Toggle("录音时静音系统声音", isOn: $settings.muteOutputWhileRecording)
                    .disabled(model.phase != .idle)
                Text("默认开启。视频和音乐继续播放，仅静音当前系统输出，不修改音量；麦克风停止后立即恢复。该输出上的通知声也会静音，不覆盖单独指定到其他设备的播放器。不支持静音的设备会提示你手动操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notice = outputMute.notice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
                if outputMute.hasPendingRecovery && model.phase == .idle {
                    Text("有尚未恢复的静音记录。请确认设备已连接，再恢复；强制退出无法即时恢复声音。")
                        .font(.caption)
                    Button("恢复上次由 Ziki 静音的设备") { outputMute.recoverPending() }
                }
            }

            Section("fn 与 macOS") {
                Text("如果 macOS 把 fn／🌐 设为“显示表情与符号”，一次按键会同时触发两个动作。请在键盘设置里将“按下 fn／🌐 键时”改为“无操作”。")
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开键盘设置") {
                    NSWorkspace.shared.open(SystemSettingsLink.keyboard)
                }
            }

            Section("写作") {
                Toggle("自动整理口述内容", isOn: $settings.cleanupEnabled)
                Text("由模型结合语境纠正识别错误、去除口癖并整理结构，不再按字符差异或字数比例否决结果。请求失败、空响应或输出未完成时保留原始转写。金额、日期等重要信息仍请核对。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("参考最近几轮听写", isOn: $settings.contextEnabled)
                    .disabled(!settings.cleanupEnabled)
                Text("启用后，最多 3 轮、合计 8000 字的近期识别与整理文字会随本次请求发送给千问。上下文默认仅在内存中暂存，开启诊断会额外记录请求上下文；切换目标应用、间隔 10 分钟或重启后不再沿用。同一应用内切换聊天或话题时，可手动开始新对话。不读取聊天窗口，也不把模型结果当作已确认术语。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("开始新对话（清空上下文）") {
                    model.clearDictationContext()
                }
                .disabled(model.phase != .idle)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 8)
        .onChange(of: settings.contextEnabled) { _ in
            model.clearDictationContext()
        }
        .onChange(of: settings.cleanupEnabled) { _ in
            model.clearDictationContext()
        }
    }
}

private struct ProviderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @State private var speechKey = ""

    var body: some View {
        Form {
            Section("百炼模型") {
                LabeledContent("语音识别") {
                    Text("Fun-ASR Realtime")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("文字整理") {
                    Text("Qwen3.5 Flash")
                        .foregroundStyle(.secondary)
                }
                Picker("区域", selection: $settings.funRegion) {
                    ForEach(FunRegion.allCases) { region in
                        Text(region.title).tag(region)
                    }
                }
                TextField("Workspace ID", text: $settings.funWorkspaceID)
                Text("填写百炼工作空间 ID。语音识别和文字整理会自动使用同一 Workspace、区域和 API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !settings.funWorkspaceID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    if let workspaceID = BailianWorkspaceInput.normalizedID(
                        from: settings.funWorkspaceID
                    ) {
                        Label("已识别 Workspace：\(workspaceID)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("无法识别这个 Workspace ID", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                SecureField("百炼 API Key", text: $speechKey)
                HStack {
                    connectionLabel
                    Spacer()
                    Button {
                        model.testSpeechConnection()
                    } label: {
                        if model.connectionTestState == .testing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("测试中")
                            }
                        } else {
                            Text("测试两个模型")
                        }
                    }
                    .accessibilityIdentifier("fun-asr-connection-test")
                    .disabled(!canTestFunASRConnection)
                    Button("保存 API Key") {
                        Task {
                            let saved = await model.saveCredential(speechKey, for: .funASR)
                            if saved {
                                speechKey = ""
                            }
                        }
                    }
                    .disabled(speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                connectionTestStatus

                if let credentialSaveError = model.credentialSaveError {
                    Label("API Key 保存失败：\(credentialSaveError)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let lastServiceError = model.lastServiceError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近一次听写错误")
                            .font(.caption.weight(.semibold))
                        Text(lastServiceError)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if !settings.cleanupEnabled {
                    Label("文字整理已在“语音”设置中关闭", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 8)
        .onChange(of: settings.funRegion) { _ in
            model.invalidateConnectionTest()
        }
        .onChange(of: settings.funWorkspaceID) { _ in
            model.invalidateConnectionTest()
        }
        .onChange(of: speechKey) { newValue in
            if !newValue.isEmpty {
                model.invalidateConnectionTest()
            }
        }
    }

    private var providerConnected: Bool {
        model.funKeyConfigured
    }

    private var connectionLabel: some View {
        Label(
            providerConnected ? "Key 已安全保存" : "尚未配置",
            systemImage: providerConnected ? "checkmark.circle.fill" : "circle"
        )
        .foregroundStyle(.secondary)
    }

    private var canTestFunASRConnection: Bool {
        model.funKeyConfigured
            && model.phase == .idle
            && model.connectionTestState != .testing
            && speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && BailianWorkspaceInput.normalizedID(from: settings.funWorkspaceID) != nil
    }

    @ViewBuilder
    private var connectionTestStatus: some View {
        switch model.connectionTestState {
        case .idle:
            Text("测试会真实连接 Fun-ASR，并让 Qwen 整理“6 点改 8 点”的样例；不会启用麦克风。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("fun-asr-connection-test-status")
        case .testing:
            Label("正在验证 Fun-ASR 和 Qwen3.5 Flash…", systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("fun-asr-connection-test-status")
        case .succeeded:
            Label("两个模型均连接成功 · 改口整理验证通过", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("fun-asr-connection-test-status")
        case let .failed(userMessage, diagnostic):
            VStack(alignment: .leading, spacing: 4) {
                Label(userMessage, systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(diagnostic)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fun-asr-connection-test-status")
        }
    }
}

private struct PrivacySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("本机") {
                LabeledContent("转写历史", value: "本机保存 30 天")
                LabeledContent(
                    "原始音频",
                    value: settings.diagnosticsEnabled
                        ? "诊断记录保存 7 天"
                        : "请求完成后释放"
                )
                LabeledContent("API Key", value: "macOS Keychain")
            }
            Section("诊断") {
                Toggle("保存本地诊断记录", isOn: $settings.diagnosticsEnabled)
                Text("开启后，每次听写会在本机保存 WAV 音频、ASR 原文、整理时使用的上下文与模型版本、千问结果、最终文字和阶段错误，7 天后自动删除。记录可能包含敏感内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("打开诊断文件夹") {
                        model.openDiagnosticsFolder()
                    }
                    Button("清除诊断记录", role: .destructive) {
                        model.clearDiagnostics()
                    }
                }
            }
            Section("当前数据路径") {
                Text(providerDisclosure)
                    .fixedSize(horizontal: false, vertical: true)
                Text(privacyDisclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 8)
    }

    private var providerDisclosure: String {
        settings.cleanupEnabled
            ? "音频会实时发送到阿里云 Fun-ASR Realtime；转写文字随后发送到同一百炼 Workspace 的 Qwen3.5 Flash 整理。" + (settings.contextEnabled ? "已启用近期上下文：最多 3 轮、合计 8000 字的先前识别与整理文字也会随请求发送，不是只在本地使用。" : "近期上下文已关闭。")
            : "音频会实时发送到阿里云 Fun-ASR Realtime；文字整理当前已关闭。"
    }

    private var privacyDisclosure: String {
        if settings.diagnosticsEnabled {
            return "Ziki 会在本机诊断文件夹保存最近 7 天的原始音频、识别与整理文本；API Key 不会写入。整理后的历史文字另行保留 30 天。第三方服务商的数据处理仍受各自条款约束。"
        }
        return "Ziki 只将整理后的最终文本写入本机历史，30 天后自动删除；不将录音、实时识别片段或整理前原文写入磁盘。启用近期上下文时，少量识别与整理文字会暂存在内存，不会从历史记录恢复。第三方服务商的数据处理仍受各自条款约束。"
    }
}

private struct AboutSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: AppUpdater

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 22) {
                    ZikiMark(size: 88)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ziki")
                            .font(.system(size: 40, weight: .medium, design: .serif))
                        Text("不止听见，更懂你。")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text(versionDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(24)
                .zikiCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("从「知音」而来")
                        .font(.system(size: 17, weight: .medium))
                    Text("伯牙抚琴，子期听出了高山与流水。\nZiki 的名字取意于子期，也取意于这份被听懂的默契。")
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("让说出口的想法，成为真正想表达的文字。")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zikiCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("版本更新")
                        .font(.system(size: 13, weight: .semibold))
                    updateControls
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zikiCard()

                HStack(spacing: 20) {
                    Link(destination: URL(string: "https://getziki.com")!) {
                        Label("访问官网", systemImage: "arrow.up.right")
                    }
                    Link(destination: URL(string: "https://github.com/Howell5/ziki")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var updateControls: some View {
        switch updater.state {
        case .disabled:
            Text("开发版本不提供自动更新")
                .foregroundStyle(.secondary)
        case .idle:
            Button("检查更新") {
                updater.check()
            }
        case .checking:
            ProgressView("正在检查更新…")
                .controlSize(.small)
        case let .current(version):
            Text("已是最新版本 \(version)")
                .foregroundStyle(.secondary)
            Button("再次检查") {
                updater.check()
            }
        case let .available(package):
            Text("发现新版本 \(package.version)")
                .font(.headline)
            Button("更新到 \(package.version) 并退出") {
                updater.install()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.phase != .idle)
            if model.phase != .idle {
                Text("请先结束当前听写，再安装更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .downloading(version):
            ProgressView("正在下载 \(version)…")
                .controlSize(.small)
        case let .preparing(version):
            ProgressView("正在安装 \(version)，Ziki 即将退出…")
                .controlSize(.small)
        case let .failed(message):
            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新检查") {
                updater.check()
            }
        }
    }

    private var versionDisplay: String {
        AppVersionPolicy.displayVersion(
            shortVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String,
            commitHash: Bundle.main.object(
                forInfoDictionaryKey: "ZikiBuildCommit"
            ) as? String
        )
    }
}
