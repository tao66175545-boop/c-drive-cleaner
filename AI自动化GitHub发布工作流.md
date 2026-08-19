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
Submit-UpdateCandidate.ps1 本地全量验证 + 源码指纹
        |
        v
candidate/vX.Y.Z-基线提交 分支 / Pull Request
        |
        v
Validate 工作流：脚本解析 + 安全自检
        |
        +-- 失败：自动阻断，AI 根据日志修复 PR
        |
        v
Codex 对话展示版本、PR、提交 SHA、源码指纹和验证结果
        |
        v
用户在 Codex 对话回复“同意”（唯一批准点）
        |
        v
Complete-ApprovedCandidate.ps1 校验批准未过期并自动合并
        |
        v
受保护 main（禁止绕过 PR 直接推送）
        |
        v
Publish Release 工作流
  - 只读构建任务读取 version.json
  - 确认 vX.Y.Z 尚未发布
  - 固定白名单打包
  - 生成 SHA256SUMS.txt 与 release.json
  - 最小写权限任务只下载已验证产物
  - 创建 tag 与 GitHub Release，上传全部资产
        |
        v
GitHub Releases / 客户端检查更新
```

## 仓库内已准备的自动化

| 文件 | 职责 |
| --- | --- |
| `.github/workflows/validate.yml` | 对 `main` 和 PR 做 PowerShell 解析、安全自检、计划契约测试、UI 烟测和发布包试构建。 |
| `.github/workflows/release.yml` | 当 `main` 验证成功时，由只读任务构建；写权限任务不执行仓库代码，只发布已验证产物。 |
| `.github/workflows/consistency.yml` | Release 完成后重新下载 ZIP，核验版本、SHA-256、发布清单和包内 `version.json`。 |
| `tools/New-ReleasePackage.ps1` | 仅从发布白名单构建 ZIP，并生成 SHA-256、发布清单。 |
| `tools/Submit-UpdateCandidate.ps1` | 检查远端漂移、执行本地验证、计算指纹并创建或更新候选 PR。 |
| `tools/Complete-ApprovedCandidate.ps1` | 在 Codex 获得明确同意后，绑定候选 SHA/指纹完成合并、监控和最终验收。 |
| `tools/Enable-GitHubWorkflowGuard.ps1` | 一次性保护 `main`，禁止直接推送并要求 PR 验证通过。 |
| `AGENTS.md` | 让后续 Codex 任务自动遵守“对话批准、批准后全自动”的发布协议。 |
| `source-policy.json` | 定义允许公开同步的文件与产品版本敏感路径。 |
| `source-manifest.json` | 记录版本、基线提交、文件 SHA-256/Git Blob 哈希和整体源码指纹。 |
| `version.json` | 唯一版本来源，格式为 SemVer，例如 `1.1.0`。 |
| `RELEASE_NOTES_v1.1.0.md` | 必需的本次发布说明。 |

发布包只允许包含启动文件、清理引擎、UI、使用文档、设计/升级说明和 `assets/`。扫描报告、截图、临时文件、测试结果、旧脚本和用户数据都不在白名单中。

## AI 自动工作方式

AI 每次完成变更时执行以下确定性动作：

1. 在分支中修改源代码和相应文档。
2. 将 `version.json` 提升到新的版本号，并新增同版本的 `RELEASE_NOTES_vX.Y.Z.md`。
3. 运行 `C-Drive-Cleaner.ps1 -SelfTest`、PowerShell 解析检查和 UI 冒烟测试。
4. 运行下面一条命令。脚本会拒绝远端漂移、漏升版本、缺发布说明或测试失败，并自动创建/更新同一候选 PR。

```powershell
.\tools\Submit-UpdateCandidate.ps1
```

5. Codex 等待 PR 验证通过，并在对话中展示 PR 号、版本、完整提交 SHA、源码指纹和变更摘要。
6. 用户在 Codex 对话回复“同意”；这是唯一人工批准动作，不需要打开 GitHub。
7. Codex 将批准绑定到刚才展示的 SHA 和指纹，运行以下收尾命令。若候选已发生变化，命令拒绝合并并要求重新批准。

```powershell
.\tools\Complete-ApprovedCandidate.ps1 `
  -PullRequest <PR号> `
  -ExpectedHeadSha <40位提交SHA> `
  -ExpectedFingerprint <64位源码指纹> `
  -UserApproved
```

8. 收尾脚本自动 squash 合并、删除候选分支，等待 Validate、Publish Release、Verify Published Release，并最终核对远端 `main` 指纹与 Release。Codex 将结果直接回复到当前对话。

首次部署本机制时使用 `-Bootstrap`；之后禁止再使用该参数：

```powershell
.\tools\Submit-UpdateCandidate.ps1 -Bootstrap
```

对于只改文档、截图或发布说明的提交，不应提高 `version.json`，因此工作流会发现同名 tag 已存在并安全跳过发布。

## 一次性仓库保护配置

首次基础设施 PR 合并后，在本地运行一次：

```powershell
.\tools\Enable-GitHubWorkflowGuard.ps1 -Apply
```

它要求所有变更通过 PR，`powershell-validation` 成功后才允许合并，同时禁止管理员绕过、强推和删除 `main`。AI 不能自行批准：只有用户在 Codex 对话明确回复“同意”后，Codex 才能调用批准收尾器完成 GitHub 操作。

## 对话批准的有效性

批准不是对未来任意版本的长期授权，只对对话中刚刚展示的一组候选标识有效：

1. PR 编号。
2. 版本号。
3. PR 完整 head commit SHA。
4. `source-manifest.json` 源码指纹。

`继续`、询问状态、同意其他方案都不算发布批准。用户回复“同意”后，Codex 会立即重新读取 GitHub；只要提交 SHA、指纹或验证状态变化，旧批准自动失效。批准后若只是网络或 Actions 瞬时失败，可自动重试；若必须修改任何候选内容，则重新生成摘要并再次等待“同意”。

GitHub Actions 默认只读。只有 `release.yml` 的最终发布任务显式申请 `contents: write`；该任务不检出或执行仓库代码。所有 Actions 使用临时 `GITHUB_TOKEN`，个人 Token 不写入项目。

## 一致性判定

本地与 GitHub 一致不是只比较版本号，而是同时满足：

1. `version.json` 版本相同。
2. `source-manifest.json` 的整体指纹相同。
3. 远端 Git Blob 与清单逐文件一致，远端被旁路修改会在下次提交前阻断。
4. 新版本的 Release tag、ZIP 名称、`release.json`、SHA-256 和 ZIP 内版本全部一致。

候选 PR 创建后，本地已经保留与候选分支完全相同的源码清单。PR 合并后，远端 `main` 的内容指纹与本地自动一致；若 PR 未合并，可继续修改并再次执行同一命令更新原 PR。

## 版本发布规则

1. `version.json` 中的版本必须匹配 `X.Y.Z` 或带预发布后缀的 SemVer。
2. 必须有同版本 `RELEASE_NOTES_vX.Y.Z.md`，否则发布失败。
3. `vX.Y.Z` 已存在时绝不覆盖、删除或替换 Release。
4. 发布失败时只重跑同一次 Actions；不重新上传手工 ZIP。
5. 修复已发布版本必须使用新版本号，例如 `1.0.1`，不能改写 `v1.0.0`。

## 后续升级到无人值守客户端更新

GitHub Release 自动化解决“发布到 GitHub”，不等于可以静默替换用户机器上的文件。客户端自动更新仍需在 `OTA-在线升级方案.md` 的边界内增加：签名的 `release.json`、代码签名、独立更新器、版本目录和回滚。完成前，客户端只能提示用户下载新版，不能静默覆盖。
