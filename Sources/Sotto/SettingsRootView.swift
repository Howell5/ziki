import AppKit
import SottoAppCore
import SwiftUI
import SottoCore

struct SettingsRootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var navigation: SettingsNavigationState

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $navigation.selection) { pane in
                Label(pane.rawValue, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 152, ideal: 172, max: 190)
        } detail: {
            Group {
                switch navigation.selection ?? .start {
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
        .frame(width: 760, height: 560)
        .task {
            permissions.refresh()
        }
    }
}

private struct StartSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var permissions: PermissionCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speak. Keep typing.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("单击 fn 开始，自然说话，再次单击 fn，把整理后的文字写回原输入框。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                        detail: "写回原输入框，并识别独立的 fn 按键",
                        state: permissions.accessibility
                    )
                }
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前语音服务")
                            .font(.headline)
                        Text(settings.provider.title)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.canStart ? "checkmark.circle.fill" : "key.horizontal")
                        .foregroundStyle(model.canStart ? Color.green : Color.orange)
                    Text(model.canStart ? "已配置" : "需要完整服务配置")
                        .foregroundStyle(.secondary)
                }

                Button("完成设置") {
                    settings.onboardingComplete = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    permissions.microphone != .granted
                        || permissions.accessibility != .granted
                        || !model.canStart
                )
            }
            .padding(32)
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
            "请运行打包并签名后的 Sotto.app"
        default:
            detail
        }
    }
}

private struct SpeechSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore

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
        .navigationTitle("语音")
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
        .navigationTitle("百炼")
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
        .navigationTitle("隐私")
    }

    private var providerDisclosure: String {
        settings.cleanupEnabled
            ? "音频会实时发送到阿里云 Fun-ASR Realtime；转写文字随后发送到同一百炼 Workspace 的 Qwen3.5 Flash 整理。" + (settings.contextEnabled ? "已启用近期上下文：最多 3 轮、合计 8000 字的先前识别与整理文字也会随请求发送，不是只在本地使用。" : "近期上下文已关闭。")
            : "音频会实时发送到阿里云 Fun-ASR Realtime；文字整理当前已关闭。"
    }

    private var privacyDisclosure: String {
        if settings.diagnosticsEnabled {
            return "Sotto 会在本机诊断文件夹保存最近 7 天的原始音频、识别与整理文本；API Key 不会写入。整理后的历史文字另行保留 30 天。第三方服务商的数据处理仍受各自条款约束。"
        }
        return "Sotto 只将整理后的最终文本写入本机历史，30 天后自动删除；不将录音、实时识别片段或整理前原文写入磁盘。启用近期上下文时，少量识别与整理文字会暂存在内存，不会从历史记录恢复。第三方服务商的数据处理仍受各自条款约束。"
    }
}

private struct AboutSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 72, height: 72)
            Text("Sotto")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(versionDisplay)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
            Text("A focused native voice-to-text tool for macOS.")
                .foregroundStyle(.secondary)
            Text("首版只做听写、保守整理和可靠写回。")
                .foregroundStyle(.secondary)
            Divider()
                .padding(.vertical, 4)
            updateControls
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var updateControls: some View {
        switch updater.state {
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
            ProgressView("正在安装 \(version)，Sotto 即将退出…")
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
                forInfoDictionaryKey: "SottoBuildCommit"
            ) as? String
        )
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
