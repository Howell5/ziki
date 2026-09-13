# Ziki Cloud：测试、原生调试与成本控制

状态：实施依据；实际证据只维护在 [执行计划](cloud-mvp-plan.md)。

## 测试选择

每次测试回答一个尚未证明的问题。按“源码/依赖版本 + 环境 + 输入/用例集”记录证据；相关条件未变就复用，不因改了文档而重新编译。

| 改动 | 开发内循环 | 阶段门槛 | 不必每次运行 |
|---|---|---|---|
| 文档 | 链接、术语、矛盾与 diff 检查 | 文档评审 | 编译、API、支付 |
| 客户端策略 | 所属 harness、增量编译 | 受影响原生模块回归 | 官网和支付 |
| 认证 | 令牌/越权/撤销失败用例 | staging 真实登录，BYOK 隔离 | 全部模型样本 |
| 额度/迁移 | 本地 D1 边界、并发、幂等 | 重复/过期/跨账期综合回归 | 麦克风、截图 |
| 模型适配 | 固定响应、流和故障 fixture | 少量授权真实样本、成本延迟 | 每轮真实付费调用 |
| 支付 | 本地签名/状态 fixture | Stripe 测试模式真实回调与账务核验 | UI 修改时重测全年续费 |
| 网页 UI | 类型、受影响页面/组件 | 双语代表尺寸、关键流程 | 所有页面×尺寸×状态组合 |
| 录音/权限/插入 | 原生 Debug App 定向复现 | 真机 Fn、音量恢复、焦点插入 | 云支付 |
| 签名/更新/交付 | 包结构、版本、签名 | 完整 Release 包与安装更新冒烟 | 每次保存代码制作 DMG |

支付、权限、额度和迁移不能仅凭 mock 或界面验收。全链路在阶段门槛和最终交付运行，不在每次小改后运行。

## 现有测试入口

现有两个 executable harness 没有通用 `--filter` 参数，不编造 `swift test --filter` 命令。
复用稳定构建目录，避免每轮全量编译：

```sh
swift run --scratch-path /tmp/ziki-cloud-baseline.k1IyuZ ZikiCoreTestHarness
swift run --scratch-path /tmp/ziki-cloud-baseline.k1IyuZ ZikiAppTestHarness
```

该路径是本机已验证的临时缓存；清理后新建并更新记录。Core 改动覆盖依赖它的 App harness；AppCore 修改先跑 App harness。
仅当实际耗时需要时再增加测试过滤能力，不为 104 个廉价测试预建复杂调度。
官网：在 `website/` 运行 `npm run build && npm run check && npm test`，产物未变不重复 build。
现有 `tests/browser-smoke.mjs` 只覆盖官网，不冒充账号/支付测试。

## macOS 原生开发内循环

继续 Swift/AppKit/SwiftUI，可在 Xcode 打开现有 Swift Package，结合断点、LLDB、Console；确有性能问题再用 Instruments。
无需为使用 IDE 重建项目结构，原生调试也不能替代后端或浏览器测试。

`scripts/package-app.sh` 保持 Release；`scripts/package-dev-app.sh` 提供独立 Debug App：

- 增量编译后装配完整 `.app`，包含正确 Info.plist、资源和 entitlement。
- 稳定开发路径与签名；开发变体隔离设置、历史、Cloud 环境和 Keychain，关闭生产自动更新；不改正式版持久身份。
- 首次开发变体仍正常申请权限，不绕过 macOS 安全，也不承诺永远不再提示。
- 不用裸二进制或 `swift run Ziki` 测麦克风，不覆盖 `/Applications/Ziki.app` 做日常调试。
- 不静默复制个人 Key/历史。录音和实时音量测试放在明确测试窗口，使用非敏感样本并确认恢复。

开发包输出 `outputs/Ziki-Dev.app`，默认增量缓存 `.build-dev`，可通过 `ZIKI_BUILD_SCRATCH_PATH` 复用已有缓存。
Bundle ID / defaults suite 为 `com.willhong.sotto.dev`；数据目录 `Sotto-Dev`，Keychain service `com.sotto.voice.credentials.dev`。
旧开发包重打包前保留带时间戳的备份；不嵌入 updater。首次使用仍需独立授权。

## 后端本地验证

在 `cloud/` 执行 `npm ci`，随后 `npm run types && npm run check && npm test`。
账号模板修改另运行 `npm run test:page-script`，在 Node 编译内联浏览器脚本，防止模板内语法错误绕过 TypeScript 检查；不在 Worker 开放运行时 eval。
`npm run migrate:local` 只修改本地 D1；重复运行应无待迁移项。`npm run build` **仅 dry-run**，不发布。
测试在 Workers/Miniflare + D1 运行，身份为本地数据库 fixture，不访问真实登录/模型/Stripe。
账号函数的测试通过不代表公开路由已上线；`AUTH_ENABLED` 默认关闭，允许隔离环境单独验证登录，语音/支付仍有硬关闭保护。
认证配置与迁移由 Better Auth 管理，测试检查 schema drift，不能为了修测试跳过 schema 校验。
依赖锁定说明和下一阶段配置门槛见 `cloud/README.md`。

## Token、API 与测试预算

- 每阶段只加载相关文档和模块，先读执行计划，不反复通读仓库和完整日志。
- 一处维护进度，决策记理由与失效条件；不生成多份同义 PRD/报告。
- 真实模型或 Stripe 请求仅在接口/配置变化或阶段验收时运行，日常用脱敏 fixture；fixture 通过不等于模型质量通过。
- 新的付费模型测试先明确样本数、时长、重试和授权预算；达到上限报告，不自动扩大费用。
- 不把用户录音存为回归样本。使用合成材料或用户明确授权的固定样本。
- 主要视觉改动默认英文桌面 + 中文手机；窄屏/反向语言先做 DOM 检查，失败才加截图；业务状态必须覆盖而非只截图。
- 返回结果、耗时、失败摘要，不每轮重复全部 PASS；完整日志保留在工具/CI 记录。
- 当前没有用户指定数字型 token 预算，不擅自设值。用阶段边界、按需检索和证据复用控制消耗，不减少高风险覆盖。

## 证据与停止条件

格式：源码版本/差异 → 环境 → 用例集 → 结果 → 未覆盖项 → 下一步。
本地测试、真实供应商、Stripe 测试、main、Cloudflare 部署、macOS Release 分别报告。
失败只在条件改变或有新假设可验证时重试；权限不足不绕过，转做安全本地工作。
阶段达标即停止该轮验证，除非相关代码/依赖/环境改变或发现新风险，不重做已经证明的事实。
