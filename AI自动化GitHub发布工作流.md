# AI 自动化 GitHub 发布工作流

## 目标与边界

目标是让常规版本更新无需人工打包、计算校验和、创建标签、上传 Release 附件或填写下载地址。AI 可以创建候选代码与发布意图，但不能绕开测试、分支保护和发布安全检查。

这个流程发布的是工具安装包，不改变清理器的安全模型：扫描不删除、用户自行勾选，微信/QQ 媒体仍为默认不选的谨慎项。

## 挑战后的结论

不能采用“AI 直接用个人 Token 推送 main，然后立即发布”的方式。它有四个不可接受的问题：

1. 代码、版本号、Release 说明和 ZIP 校验和由不同步骤人工维护，容易不同步。
2. AI 的错误变更会直接出现在公开 Release，难以撤回下载的历史包。
3. Personal Access Token 长期放在本地自动化环境中，泄露范围过大。
4. 标签已经存在时重跑会覆盖或混淆发布版本。

应以 Git 仓库中的 `version.json` 与 `RELEASE_NOTES_vX.Y.Z.md` 作为唯一发布意图，使用 GitHub Actions 统一构建发布物。发布资产、SHA-256 和 `release.json` 均由同一次 CI 构建生成。

## 自动化架构

```text
AI/开发者产生变更
        |
        v
release-candidate 分支 / Pull Request
        |
        v
Validate 工作流：脚本解析 + 安全自检
        |
        +-- 失败：自动阻断，AI 根据日志修复 PR
        |
        v
受保护 main（自动合并仅限低风险规则通过的 PR）
        |
        v
Publish Release 工作流
  - 读取 version.json
  - 确认 vX.Y.Z 尚未发布
  - 固定白名单打包
  - 生成 SHA256SUMS.txt 与 release.json
  - 创建 tag 与 GitHub Release，上传全部资产
        |
        v
GitHub Releases / 客户端检查更新
```

## 仓库内已准备的自动化

| 文件 | 职责 |
| --- | --- |
| `.github/workflows/validate.yml` | 对 `main` 和 PR 做 PowerShell 解析及清理安全自检。 |
| `.github/workflows/release.yml` | 当 `main` 的验证工作流成功时，自动发布尚未存在的版本号。 |
| `tools/New-ReleasePackage.ps1` | 仅从发布白名单构建 ZIP，并生成 SHA-256、发布清单。 |
| `version.json` | 唯一版本来源，格式为 SemVer，例如 `1.1.0`。 |
| `RELEASE_NOTES_v1.1.0.md` | 必需的本次发布说明。 |

发布包只允许包含启动文件、清理引擎、UI、使用文档、设计/升级说明和 `assets/`。扫描报告、截图、临时文件、测试结果、旧脚本和用户数据都不在白名单中。

## AI 自动工作方式

AI 每次完成一个可发布的变更时，应执行以下确定性动作：

1. 在分支中修改源代码和相应文档。
2. 将 `version.json` 提升到新的版本号，并新增同版本的 `RELEASE_NOTES_vX.Y.Z.md`。
3. 运行 `C-Drive-Cleaner.ps1 -SelfTest`、PowerShell 解析检查和 UI 冒烟测试。
4. 创建 Pull Request；验证失败时只修复当前 PR，不创建 Release。
5. PR 合入 `main` 后不再打包或手动上传。Actions 自动完成发布。

对于只改文档、截图或发布说明的提交，不应提高 `version.json`，因此工作流会发现同名 tag 已存在并安全跳过发布。

## 权限与完全自动化的配置

在 GitHub 仓库的 `Settings -> Actions -> General` 中设置工作流权限为 **Read and write permissions**，并允许 GitHub Actions 创建和批准 pull request（仅在启用自动合并时需要）。`release.yml` 使用临时的 `GITHUB_TOKEN`，不需要将个人 Token 写入代码或脚本。

在 `Settings -> Branches` 为 `main` 创建规则：

1. 要求 `Validate C Drive Cleaner` 通过。
2. 要求线性历史，禁止强制推送。
3. 只允许 GitHub App 或指定发布机器人自动合并。
4. 对涉及下列文件的 PR 强制人工审批：`C-Drive-Cleaner.ps1`、`C-Drive-Cleaner-UI.ps1`、`C盘清理.bat`、`.github/workflows/**`、`tools/**`。

这意味着低风险的文档、资源和已验证 UI 文案可自动合并并自动发布；涉及删除逻辑、启动入口、CI 权限或打包逻辑的变化必须保留一次人工确认。对于面向用户删除文件的工具，这是必要的发布闸门，不能由 AI 完全取消。

## 版本发布规则

1. `version.json` 中的版本必须匹配 `X.Y.Z` 或带预发布后缀的 SemVer。
2. 必须有同版本 `RELEASE_NOTES_vX.Y.Z.md`，否则发布失败。
3. `vX.Y.Z` 已存在时绝不覆盖、删除或替换 Release。
4. 发布失败时只重跑同一次 Actions；不重新上传手工 ZIP。
5. 修复已发布版本必须使用新版本号，例如 `1.0.1`，不能改写 `v1.0.0`。

## 后续升级到无人值守客户端更新

GitHub Release 自动化解决“发布到 GitHub”，不等于可以静默替换用户机器上的文件。客户端自动更新仍需在 `OTA-在线升级方案.md` 的边界内增加：签名的 `release.json`、代码签名、独立更新器、版本目录和回滚。完成前，客户端只能提示用户下载新版，不能静默覆盖。
