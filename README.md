# Ziki

<img src="Packaging/Assets/ZikiIcon-1024.png" alt="Ziki 双弦 Z 标识" width="96" height="96">

Ziki 是一个专注于 macOS 的原生语音输入 App：单击 `fn` 开始说话，再次单击 `fn`，把识别并整理后的文本粘贴到完成处理时的系统键盘焦点。

当前 Apple Silicon 测试版可从 [GitHub Releases](https://github.com/Howell5/ziki/releases/tag/v0.5.0) 下载。

Ziki 取意于子期与知音：听懂，再成文。新图标以两道相互呼应的弦形成 Z。

### 从旧品牌升级到 Ziki

本版全面更名：应用为 `Ziki.app`，发布包为 `Ziki-<版本>-macOS-<架构>`，代码模块与构建参数也使用 Ziki。不再提供旧名兼容包。旧版 Sotto 的更新器只识别旧包名，因此这一次需退出旧应用、移走旧应用后安装 Ziki；后续 Ziki 版本仍可应用内更新。

为延续现有权限与数据，仅保留固定证书 `Sotto Local Development`、Bundle ID `com.willhong.sotto`、Keychain service `com.sotto.voice.credentials` 和 Application Support 下的 `Sotto` 存储目录。它们是持久身份，不是对外产品名。设置、密钥、历史和诊断不会因改名被清空；macOS 仍可能因安装路径／可执行文件改名要求重新确认权限，请按系统提示处理，不绕过权限检查。

首版只保留这条核心闭环：

- 标准 Dock App，同时在菜单栏常驻
- `fn` toggle 开始／结束听写，`Esc` 取消
- 阿里百炼 Fun-ASR Realtime 实时识别
- 同一 Workspace 与 API Key 调用 Qwen3.5 Flash 做保守整理
- 通过系统 `⌘V` 写入当前键盘焦点；结果同时保留在剪贴板
- API Key 存在 macOS Keychain；默认不保存录音，最终听写文本只在本机保留 30 天

翻译、聊天、云端历史和模板系统不在当前范围内。

## 安装 GitHub 预览版

当前发布包面向 Apple Silicon，支持 macOS 13 及以上版本。项目目前选择零成本分发，因此维护者构建使用固定的本地自签名证书，未经过 Apple Developer ID 签名和公证。

1. 只从 [Ziki GitHub Release](https://github.com/Howell5/ziki/releases/tag/v0.5.0) 下载 DMG；同页的 `SHA256SUMS.txt` 可用于校验文件。
2. 打开 DMG，把 Ziki 拖入 **Applications**。
3. 首次打开如果被 macOS 阻止，先尝试右键 Ziki 并选择 **打开**。
4. 如果仍被阻止，先触发一次打开，再进入“系统设置 → 隐私与安全性”，只对 Ziki 点击 **仍要打开**，验证本机密码后确认打开。
5. 按下文开启麦克风和辅助功能权限，并配置自己的百炼 Workspace ID 与 API Key。

安装包含应用内更新功能的版本后，后续升级可在 **设置 → 关于** 中点击 **检查更新**，再点击 **更新到新版本并退出**。Ziki 会下载 GitHub Latest Release 中与当前架构匹配的 ZIP，校验 SHA-256、Bundle ID、版本号和代码签名身份，验证通过后退出并替换当前应用；更新完成后需要手动重新打开 Ziki。

不要全局关闭 Gatekeeper，也不要运行来源不明的“解除签名限制”命令。公司或学校管理的 Mac 可能禁止“仍要打开”，这种设备需要管理员允许。

API Key 保存在 macOS Keychain。首次保存或首次从旧 ad-hoc 签名迁移到固定本地签名时，系统可能询问 Ziki 是否可访问对应项目；确认来源后选择 **始终允许**。同一台维护者 Mac 使用相同证书、Bundle ID 和安装路径升级时，后续版本不应继续反复询问。其他 Mac 不信任这张本地证书，公开分发仍需 Developer ID。

## 系统要求

- macOS 13 Ventura 或更高版本
- Swift 6.0 或更高版本的命令行工具链
- 麦克风和辅助功能权限
- 百炼 Workspace ID 和对应区域的 API Key

项目是纯 Swift Package，不包含也不依赖 `.xcodeproj`。构建和打包都通过 `swift build` 完成，不需要打开 Xcode。`package-app.sh` 默认只构建当前 Mac 架构；需要同时分发 Apple Silicon 和 Intel 时，应分别构建后再合并或分别发布。

## 构建与运行

编译源码：

```bash
swift build
```

不要直接运行 `swift run Ziki` 或 `.build/.../Ziki`。裸 SwiftPM 可执行文件没有应用的 `Info.plist` 和音频输入 entitlement；macOS 在它请求麦克风时可能直接终止进程。需要运行应用时，始终先执行下面的打包脚本，再打开生成的 `.app`。

运行核心测试工具：

```bash
swift run ZikiCoreTestHarness
swift run ZikiAppTestHarness
swift scripts/verify-brand.swift
```

按需运行真实整理模型评测（会使用自己的百炼配额，不启用麦克风、不读取听写历史）：

```bash
swift build
ZIKI_BUILD_DIR="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$ZIKI_BUILD_DIR/Modules" \
  "$ZIKI_BUILD_DIR"/ZikiCore.build/*.o \
  Sources/Ziki/TranscriptPolisher.swift scripts/evaluate-cleanup.swift \
  -o .build/evaluate-cleanup
ZIKI_EVAL_API_KEY="$(security find-generic-password -s com.sotto.voice.credentials -a fun-asr-api-key -w)" \
ZIKI_EVAL_WORKSPACE="$(defaults read com.willhong.sotto funWorkspaceID)" \
ZIKI_EVAL_REGION="$(defaults read com.willhong.sotto funRegion)" \
  .build/evaluate-cleanup
```

评测顺序提交 6 个固定样例，复用生产请求构造和整理调用；输出供人工核对。断言只用于评测，不参与运行时文本审核，也不代表模型永远不会误改。请勿在开启 shell 命令追踪（`set -x`）时运行含凭据的命令。

打包 release 应用：

```bash
./scripts/package-app.sh
open outputs/Ziki.app
```

脚本会：

1. 执行 `swift build -c release --product Ziki`；
2. 生成 `outputs/Ziki.app`；
3. 把独立更新助手 `ZikiUpdater` 放入 App bundle；
4. 复制 `Info.plist`；
5. 使用 `Packaging/Ziki.entitlements` 做 hardened runtime 的 ad-hoc 签名；
6. 验证 app bundle 和签名。

默认签名身份是 `-`。将来有 Developer ID 时，可以指定证书：

```bash
ZIKI_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package-app.sh
```

这只会签名，不会自动提交 notarization。

### 本地开发：固定签名，避免反复弹 Keychain

`package-app.sh` 默认使用 ad-hoc 签名，每次重新编译后代码哈希都会改变。Keychain 因此可能把新构建视为另一个 App，并重新询问是否允许读取 API Key。这是 macOS 的安全校验，不是 API 服务的问题。

本机开发可以免费创建一个只供自己使用的稳定代码签名证书：

1. 打开“钥匙串访问”；
2. 选择“钥匙串访问 → 证书助理 → 创建证书”；
3. 名称填写 `Sotto Local Development`；
4. “身份类型”选择 **自签名根证书**，“证书类型”选择 **代码签名**；
5. 勾选“让我覆盖默认设置”，其余项目保留默认值并完成创建。

确认签名身份存在：

```bash
security find-identity -v -p codesigning
```

之后开发时使用：

```bash
./scripts/package-dev-app.sh
open outputs/Ziki.app
```

脚本会固定使用 `Sotto Local Development`，并为本机自签名禁用无意义的在线时间戳请求。第一次让 `/usr/bin/codesign` 使用证书私钥时，Keychain 仍可能询问一次；确认是系统的 `codesign` 后选择 **始终允许**。从旧 ad-hoc 构建切换过来时，Ziki 读取现有 API Key 也可能再询问一次；固定签名后的后续重建不应继续反复弹窗。

这个自签名证书只解决本机身份稳定性，不能替代 Apple 公证，也不要把它当作公开可信的签名。若证书使用其他名称，可以这样指定：

```bash
ZIKI_DEVELOPMENT_CODESIGN_IDENTITY="Your Local Code Signing" \
  ./scripts/package-dev-app.sh
```

## 首次设置与权限

首次启动会打开设置窗口。请完成两项权限：

1. **麦克风**：只在用户主动开始听写后采集语音。
2. **辅助功能**：识别独立的 `fn` 按键、避开安全输入框，并向当前系统键盘焦点发送粘贴。

如果系统权限面板已经打开但 Ziki 仍显示未允许：

1. 在“系统设置 → 隐私与安全性”确认 Ziki 已启用；
2. 完全退出并重新打开 Ziki；
3. ad-hoc 版本重建后如果签名身份发生变化，可能需要移除旧条目再重新授权。

Ziki 不会自动写入密码等安全输入框。最终文本会先放入剪贴板，再向处理完成时真正拥有系统键盘焦点的位置发送一次 `⌘V`；Ziki 不再按组件类型、窗口或进程关系预先判断目标。

## 配置语音服务

从 Dock、Spotlight、Launchpad 或菜单栏打开 Ziki，然后进入 **百炼**。

Fun-ASR 在录音时持续发送 PCM 音频并接收实时结果；Qwen3.5 Flash 在转写完成后处理口头语、重复和明确改口。两次调用共用一套百炼配置。

1. 选择与阿里云 Model Studio 账号一致的区域：
   - 中国大陆（北京）
   - 国际（新加坡）
2. 填写百炼 **Workspace ID**；
3. 填入对应区域的 API Key；
4. 点击 **保存 API Key**；
5. 点击 **测试两个模型**，同时验证 Fun-ASR 和“6 点改 8 点”的整理流程。

不同区域的 API Key 和 endpoint 不能混用。如果返回未授权错误，先检查区域，再检查 Key。

整理默认开启，可在 **语音 → 自动整理口述内容** 中关闭。整理输出始终跟随说话语言：中文口述输出中文，英文口述输出英文，不会翻译。模型结合语境恢复听错的术语、去除口癖、保留问题与不确定语气，并只在适合时使用列表。正常完成的模型结果直接交付，不再通过正则、数字差异或字数比例审核；请求失败、空响应或未完成输出时保留原始转写。模型仍可能出错，金额、日期、邮箱等重要信息请核对。

**语音 → 参考最近几轮听写** 默认开启：在同一目标应用连续听写时，最多保留 3 轮、合计 8000 字的完整识别与整理文字，随下一次整理请求发送给千问，不额外调用摘要或审核模型。超过预算时舍弃整轮，不截取片段；当前听写仍完整提交。近期内容只作为可能有误的参考，不是已确认术语，不会从 30 天历史中恢复，也不会读取其他应用的聊天正文或 AI 回复。

切换听写目标应用、距上一轮整理完成超过 10 分钟、手动清空或重启后，不再沿用旧上下文。同一应用不等于同一对话：切换聊天或话题时，可从菜单栏或语音设置点击 **开始新对话（清空上下文）**。也可单独关闭近期上下文。上下文默认只暂存在内存；开启诊断时，实际使用的上下文也会随该次诊断记录写入磁盘。API Key 保存在 macOS Keychain；Workspace ID 和区域等非机密设置保存在 UserDefaults。

## 使用 Fn toggle

1. 把光标留在目标输入框中；
2. 单击一次 `fn`，底部胶囊出现 **Listening…**；
3. 自然说话；
4. 再单击一次 `fn`，进入 **Thinking…**；
5. 识别和整理完成后，Thinking 浮层先消失，再向此刻的系统键盘焦点发送 `⌘V`；
6. 成功发送后不再显示额外状态；最终文本会保留在剪贴板，必要时可再次按 `⌘V`。

听写时按 `Esc` 会取消本次录音。Ziki 对 `fn` 有约 120ms 的防误触判断；`fn` 与 F 功能键、方向键或其他组合键一起使用时不会触发听写。也可以从菜单栏选择 **Start Listening / Stop Listening**。

**语音 → 录音时静音系统声音** 默认开启：开始采集麦克风前静音当前系统输出，停止采集后立即恢复，不等待 ASR 或千问。音乐和视频继续播放，音量值不变；原本静音的设备不会被自动解除静音，手动调节的音量也不会被覆盖。录音失败、取消、超时结束及正常退出共用恢复路径；录音引擎内部重启不会提前恢复声音。

切换默认输出设备时，先静音新设备，再恢复旧设备。仅支持提供设备级可写静音开关的输出，不支持的 HDMI／声道级设备会提示手动静音；不控制单独路由到其他设备的播放器。该设备上的通知音也会静音。

设备断开、恢复失败或应用强制退出时，按设备 UID 保留少量恢复记录（不含音频）。重新启动不会擅自开声；连接设备后，可从菜单栏或语音设置点击 **恢复上次由 Ziki 静音的设备**。强制结束进程无法保证即时恢复，可先用系统静音键手动恢复。录制期间主动解除静音后不会被持续强制静音；当前实现按恢复时的静音状态判断，不能区分用户“解除后又重新静音”和原本由 Ziki 设置的静音，因此这种情况下建议关闭自动静音功能。

如果默认输入是经典蓝牙耳机，Ziki 会显示提示但仍正常录音。受蓝牙 HFP 限制，录音期间耳机播放音质会暂时下降；结束或取消听写后，Ziki 会完整释放音频引擎，让系统切回高质量播放。希望听写时音乐也保持高质量，可把系统输入改为 MacBook 麦克风，耳机只作为输出。

每次有效听写的最终文本会先写入本机历史，再尝试系统粘贴。可从设置侧边栏的 **历史** 或菜单栏 **Open History…** 搜索、复制或删除记录；复制只写入剪贴板，不会替你再次粘贴。历史固定保留 30 天，也可手动清空全部。

排查听写截断或无结果时，可在 **隐私 → 保存本地诊断记录** 中开启诊断模式。每次听写会在 `~/Library/Application Support/Sotto/Diagnostics/` 下生成 WAV 音频和 `session.json`，关联记录 ASR 原文、整理所用上下文、模型与 prompt 版本、千问结果、交付／回退决策、最终文字和错误阶段；诊断记录仅存本机、排除系统备份并在 7 天后自动删除。诊断记录可能包含敏感内容，问题排查结束后应关闭并清除。

如果单击 `fn` 完全没有反应，优先检查辅助功能权限，并确认 macOS 没有把单独的 `fn` 配置为系统听写、输入法切换或表情面板。

如果按 `fn` 时同时打开表情面板，请进入“系统设置 → 键盘”，把“按下 fn／🌐 键时”改为“无操作”。macOS 的系统动作和 Ziki 的全局快捷键是两个独立监听，必须先清除这一快捷键冲突。

## 数据与隐私

- 音频发送到所选区域的阿里云 Fun-ASR Realtime。
- 启用整理时，转写文本会发送到同一百炼 Workspace 的 Qwen3.5 Flash；启用近期上下文时，最近几轮的识别与整理文字也会随请求发送，不是只在本地使用。
- 默认情况下，Ziki 不将录音、实时识别片段或整理前原文写入磁盘；近期上下文仅暂存在内存，整理后的最终文本在本机 Application Support 中保存 30 天。
- 历史不包含目标 App、窗口、PID、粘贴状态或复制状态，也不会同步到云端。
- 用户主动开启本地诊断后，最近 7 天的 WAV 音频、识别与整理文本、整理上下文与模型版本会保存在本机；API Key 不会写入。
- 第三方服务的数据保留与训练政策由各自条款决定。

## 分发状态

打开 `outputs/Ziki-0.5.0-macOS-arm64.dmg`，将 Ziki 拖入 **Applications**。之后可以从 Dock、Spotlight、Launchpad、Finder 或菜单栏打开；再次点击 Dock 图标会恢复设置窗口。

当前项目选择零成本分发，`package-distribution.sh` 默认使用 `Sotto Local Development` 固定本地签名，**尚未 notarize**。这能让维护者 Mac 在版本更新后保持同一应用身份，但其他 Mac 不会自动信任该证书，Gatekeeper 仍会提示未验证的开发者。

应用内更新依赖 Release 中严格命名的 `Ziki-<版本>-macOS-<架构>.zip`，并要求新旧应用具有相同的 designated requirement。发布时不可更换签名证书；GitHub Release 也必须保留资产的 SHA-256 digest，否则客户端会拒绝安装。

本机直接构建通常可以正常打开。如果 app 经浏览器或聊天工具下载，Gatekeeper 可能阻止首次启动。请先尝试右键 app 选择 **打开**；如仍被阻止，到“系统设置 → 隐私与安全性”对这一个 app 选择 **仍要打开**。不要全局关闭 Gatekeeper。

如果将来需要让普通用户双击即开、并让跨版本身份稳定，仍需 Apple Developer Program 账号，并完成：

- Developer ID Application 签名
- Hardened Runtime
- Apple notarization 和 stapling
- 在干净 Mac 上验证首次权限流程及更新后的权限保留

完整版依赖 Accessibility 监听全局 `fn` 并向其他 App 的当前键盘焦点发送粘贴，而 Mac App Store 强制启用 App Sandbox；因此当前推荐渠道是 Developer ID 签名并公证的独立 DMG，而不是 Mac App Store。若将来一定要上架，需要另做只复制到剪贴板的沙盒版。

## 常见问题

**菜单栏没有出现 Ziki**

从 Dock 或 Spotlight 再次打开 Ziki；正常情况下会恢复设置窗口，同时菜单栏图标也会重新出现。若两处都没有，请通过活动监视器确认进程是否仍在运行。

**识别成功但没有自动写入**

检查辅助功能权限，并确认 Thinking 消失时光标仍在希望输入的位置。Ziki 已把结果保留在剪贴板，可直接按 `⌘V` 重试。

**Fun-ASR 返回未授权**

确认账号区域、设置中的区域和 API Key 属于同一个 Model Studio endpoint。

**重建后权限失效**

ad-hoc 签名随可执行文件变化，macOS 可能把重建产物视为新的授权对象。本机开发请按“本地开发：固定签名”创建一次自签名证书，并改用 `./scripts/package-dev-app.sh`；公开预览版只有使用 Developer ID 才能从根本上稳定跨机器、跨版本身份。

**为什么 Keychain 每次都询问是否允许读取 API Key**

旧开发包的身份是随构建变化的 ad-hoc 代码哈希，而 Keychain 会按代码签名身份保护凭据。当前代码已把 API Key 收敛为启动时读取一次、进程内复用；再配合本机固定签名，正常情况下只会在首次建立信任或从旧签名迁移时确认一次。不要为了消除弹窗而允许所有 App 访问该项目。
