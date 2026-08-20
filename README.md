# C盘智能清理

Windows C 盘扫描与清理工具。它先分析，再由用户逐项选择是否清理，并保留清理前后的空间对比和 HTML 诊断报告。

## 下载与运行

从 [Releases](https://github.com/tao66175545-boop/c-drive-cleaner/releases) 下载最新版本的 `C-Drive-Cleaner-vX.Y.Z.zip`，解压后双击 `C盘清理.bat`。

运行环境：Windows 10/11、Windows PowerShell 5.1、Windows Forms。

## 使用流程

1. 点击“开始扫描”。扫描不会删除文件。
2. 在“清理清单”查看候选项的大小、建议和影响说明。
3. 手动勾选需要处理的项目。
4. 确认预计释放空间后点击“执行所选项”。
5. 在概览页或 HTML 报告中查看结果。

“开始扫描”默认使用快速清理扫描并跳过全用户目录空间剖析。在 NTFS USN Journal 可读时，首次扫描建立不含路径的增量索引，后续只重新扫描发生变化的固定项目；普通权限无法读取 Journal 时会自动使用快速文件系统扫描，不影响功能正确性，也不会自动弹出 UAC。

HTML 报告保存在 `%LOCALAPPDATA%\CDriveCleaner\reports`，不会写入程序安装目录。

## 安全边界

- 空间大户、重复目录、聊天数据库、文件接收目录、休眠文件和页面文件只诊断，不自动删除。
- 微信/QQ 的图片与视频附件单列为“谨慎选择”，默认不勾选；执行后移入系统回收站，清空回收站前可恢复，且不能与“清空回收站”同批执行。不处理聊天数据库、`FileRecv` 或整个账号目录。
- 清理器拒绝盘根、Windows、用户主目录和脚本目录等保护路径，并跳过 junction/symlink 重解析点。
- 清理清单只传递固定项目 ID，不接受用户输入的删除路径。
- 清理计划包含规则哈希、扫描时间和大小快照；规则或用户内容发生变化时会要求重新扫描。
- 清理必须来自本次扫描生成的选择计划，命令行直接 `-Clean` 会失败关闭；程序不会自动请求管理员权限。
- 清理操作日志保存在 `%LOCALAPPDATA%\CDriveCleaner\journals`，仅记录稳定 ID、结果和释放量，不写入原始文件路径或文件内容。
- 增量索引保存在 `%LOCALAPPDATA%\CDriveCleaner\scan-index-v1.json`，只记录 NTFS 文件引用号、稳定项目 ID、大小、Journal 游标和完整性哈希；微信/QQ 用户内容不进入索引，清理阶段不信任缓存结果。

## 项目结构

```text
C盘清理.bat              双击启动入口
C-Drive-Cleaner-UI.ps1   WinForms 图形界面
C-Drive-Cleaner.ps1      扫描、清理、安全闸和报告引擎
version.json             当前安装版本与更新通道
assets/                  Logo 与动效资源
OTA-在线升级方案.md      GitHub Releases 在线升级架构
rules/                   版本化清理与诊断规则目录
core/                    规则加载与结构化事件契约
contracts/               智能助手等跨模块权限契约
ARCHITECTURE.md           目标架构、量化指标和演进 LOOP
migration-decision.json   .NET 迁移指标、触发条件与回滚路径
AgentHost.ps1             隔离的单次模型调用进程
agent-roadmap.json        AI Agent P8-P13 验收状态
```

## 架构演进

项目采用契约优先的渐进式迁移，不直接推翻已验证的删除安全链。每轮架构改造按 `OBSERVE -> CHALLENGE -> SELECT -> IMPLEMENT -> VERIFY -> MEASURE -> DECIDE` 执行，并使用以下命令检查当前阶段是否满足退出条件：

```powershell
.\tools\Invoke-ArchitectureLoop.ps1 -FullValidation
```

智能助手是可选解释与编排层。离线知识核心可解释清理项、恢复策略和建议风险，并能生成确定性的低风险建议；基础扫描和清理在 AI 关闭、离线或模型不可用时仍应完整工作。云模型只能在用户明确同意后读取字段白名单生成的脱敏摘要，不接收原始路径、用户名、日志或文件内容；AI 不拥有任意路径、命令执行或最终删除确认能力。

界面中的“智能助手”采用左右对话气泡：挥手的曙光云 IP 在左侧回复，用户在右侧发送消息，并在每次启动时从 6 套本地通用头像中随机选择一套。它可以回答项目含义、生成低风险建议并应用为可撤销的勾选。包含路径、PowerShell/命令行、绕过规则或替代用户确认的请求会被拒绝；应用建议不会自动开始清理。

### 可选云端 Agent

默认状态是 `LOCAL · SAFE MODE`，不会发起模型网络请求。需要云端对话时，在“智能助手”页点击“配置”，填写 HTTPS API 基础地址、精确模型名、接口协议和自己的 API Key，并确认数据范围。

- 支持 OpenAI Responses、Chat Completions 兼容接口；纯文本接口只提供问答，不操作页面。
- 对部分兼容网关重复拼接的工具参数进行结构化归一化；仅接受重复空对象或相同对象，冲突参数会安全拒绝。
- API Key 使用 Windows DPAPI CurrentUser 加密保存在 `%LOCALAPPDATA%\CDriveCleaner\agent`，不会回显，也不会进入项目、日志、命令行或发布包。
- 云端会收到用户输入的问题和字段白名单扫描摘要；不会收到原始路径、用户名、机器名、文件内容或运行日志。
- Agent 可切换页面、启动/取消扫描和调整勾选，但单轮最多 6 次模型请求、8 次工具调用。
- Agent 请求清理时只会进入与顶部按钮相同的原生确认流程，不能替用户点击确认。
- 在配置页点击“禁用并移除凭据”可删除配置和加密 Key，立即恢复离线助手。

## 验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -SelfTest
```

## 提交更新

功能或版本修改完成后运行：

```powershell
.\tools\Submit-UpdateCandidate.ps1
```

脚本会执行完整验证、检查本地/远端漂移、生成源码指纹并创建候选 PR。Codex 等待验证通过后会在对话中给出候选摘要；维护者只需在 Codex 对话回复“同意”，Codex 随后自动合并、监控 GitHub Actions 并完成发布一致性验收，不需要再打开 GitHub 操作。详细规则见 [AI自动化GitHub发布工作流.md](AI自动化GitHub发布工作流.md)。

## 版本与更新

当前稳定版本由 [Releases](https://github.com/tao66175545-boop/c-drive-cleaner/releases/latest) 提供。发布包与 `release.json` 由 GitHub Actions 同一次构建生成；客户端自动更新将在代码签名、独立更新器和回滚机制完成后启用。

## 许可证

当前尚未指定开源许可证。公开仓库默认不向第三方授予复用授权。发布前请由仓库所有者选择 MIT、Apache-2.0 或其他适合的许可证。
