# Ziki 工作约定

- 有浏览器操作时，优先使用 ego-browser。
- 用户要求实现或修复后，默认完成测试、提交代码、推送并整合到 main、打包发布 GitHub Release，以及替换并重新打开本机 `/Applications/Ziki.app`。不要仅停在本地修改后等待用户再次要求交付。
- 这是用户于 2026-09-12 明确更新的交付授权，取代此前“本机更新只由用户操作”的约定，仅适用于 Sotto。
- 用户明确要求只调研、先讨论、暂不提交／发布／安装时，遵循该次限制；遇到真实权限、签名或验证阻塞时说明原因，不绕过安全检查。
- 发布沿用 `Sotto Local Development` 固定签名，保持 Bundle ID 与 designated requirement。验证版本、提交号、签名、DMG／ZIP 及 GitHub 资产摘要；替换前保留可恢复的旧版备份，正常退出应用后安装，不中断正在进行的录音。
- 产品已更名为 Ziki；不再生成旧名应用或兼容发布包。`com.willhong.sotto`、Keychain service 和旧 Application Support 路径仅作为既有身份与数据存储保留，不做无关的数据迁移。
