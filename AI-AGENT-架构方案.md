# C盘智能清理 AI Agent 架构方案

版本：实现稿 v1.4.0  
日期：2026-08-19  
目标：通过对话操作清理工具页面，同时保持现有稳定 ID、扫描计划、执行代理和用户最终确认安全链不变。P8-P13 已完成离线协议夹具验收，真实供应商参数待用户配置后做兼容性确认。

## 1. 结论

项目已经具备 Agent 的安全地基：脱敏扫描摘要、固定工具白名单、稳定 ID、可撤销勾选、提示注入拒绝和 UI 最终确认边界均已落地。下一阶段不应让模型直接操作 WinForms 控件，也不应给模型路径、PowerShell、文件系统或清理进程权限。

推荐增加一个独立的 **Agent Host**，负责模型 API、流式响应、会话与工具调用循环；主程序新增 **UI Action Broker**，只执行经过契约验证的页面动作。模型与清理执行代理之间不存在直接调用链。

```text
用户对话
  -> WinForms 智能助手页面
      -> 本地输入安全门
      -> Agent Host 子进程（模型 API、流式响应、会话状态）
          -> tool.request（严格 JSON Schema）
      -> UI Action Broker（白名单、状态校验、UI 线程执行）
          -> 页面导航 / 开始扫描 / 读取摘要 / 修改勾选 / 打开确认框
      -> Cleanup Plan Validator
      -> 原生确认框（用户本人确认）
      -> Execution Broker（模型永远不可直接访问）
```

## 2. 不变的安全边界

以下规则是 Agent 功能的硬约束，不允许由模型、提示词或供应商配置覆盖：

1. 扫描不会删除文件。
2. 清理只接受本次有效扫描计划中的稳定项目 ID。
3. 模型不能提交路径、命令、脚本、规则或自定义删除目标。
4. 模型不能调用 `ExecutionBroker`，也不能产生最终清理批准。
5. “执行清理”类对话最多只能生成计划并打开原生确认框。
6. 微信/QQ 图片和视频仍为 Review、默认不勾选、进入回收站，且不能与清空回收站同批执行。
7. API 不可用时，离线助手、扫描、选择和清理仍可独立工作。

## 3. 核心模块

### 3.1 Agent Host

独立子进程，不在 WinForms UI 线程内执行网络请求。职责：

- 调用用户配置的模型 API。
- 处理 SSE/流式文本、超时、取消、重试和速率限制。
- 维护短期会话和工具调用循环。
- 输出版本化 NDJSON 事件，不直接访问 WinForms 控件。
- 不加载清理规则路径，不引用 `ExecutionBroker`，不具备任意文件系统或 Shell 工具。

首版可使用 PowerShell 5.1 子进程和 `HttpClient`，沿用现有子进程/NDJSON模式；当流式解析、连接复用或测试指标触发迁移阈值时，再把该边界替换为聚焦的 C# Agent Host，而不是重写整个应用。

### 3.2 Provider Adapter

统一供应商差异，外部只暴露：

```text
CreateSession
SendTurn
CancelTurn
TestConnection
GetCapabilities
```

建议支持三种协议档位：

| 档位 | 能力 | Agent 行为 |
| --- | --- | --- |
| Responses-compatible | 流式、工具调用、call ID、结构化输出 | 完整 Agent 能力 |
| Chat Completions-compatible | messages、tools/tool_calls、SSE | 完整 Agent 能力 |
| Text-only | 只有文本生成 | 只读问答，不允许页面动作 |

不能把模型输出中的普通 JSON 文本当作工具调用。只有供应商协议明确返回的 tool/function call 才能进入工具验证链。

### 3.3 Agent Orchestrator

负责有限状态机和工具循环：

```text
Idle
  -> CallingModel
  -> AwaitingTool
  -> ExecutingTool
  -> CallingModel
  -> Completed

任意状态 -> Cancelled / Failed / NeedsCloudConsent / NeedsUserConfirmation
```

默认限制：单轮最多 6 次模型请求、8 次工具调用、1 个可变更 UI 状态的工具串行执行、60 秒总时限。超限后停止，并明确告诉用户当前状态。

### 3.4 UI Action Broker

模型工具请求不能直接操作控件。Broker 必须完成：

1. 工具名白名单检查。
2. 严格 JSON Schema 校验，拒绝额外字段。
3. 稳定 ID、扫描 ID、Manifest Hash 和计划时效校验。
4. 当前 UI/任务状态校验，例如扫描中不能再次扫描。
5. 使用 `BeginInvoke` 回到 UI 线程执行。
6. 返回结构化结果，不返回原始路径和日志正文。

### 3.5 Secret Store

API Key 采用 BYOK，不写入源码、配置 JSON、日志、命令行参数、崩溃报告或 GitHub。

首个公开版本使用 Windows DPAPI CurrentUser 加密后保存。Credential Manager 保留为未来可替换实现，不作为 v1.4.0 的运行依赖。

非敏感配置放在 `%LOCALAPPDATA%\CDriveCleaner\agent\provider.json`：

```json
{
  "schemaVersion": 1,
  "providerId": "custom-openai-compatible",
  "protocol": "chat-completions",
  "baseUrl": "https://api.example.com/v1",
  "model": "model-name",
  "stream": true,
  "timeoutSeconds": 60,
  "credentialTarget": "CDriveCleaner/Agent/custom-openai-compatible"
}
```

默认只允许 HTTPS；`http://127.0.0.1` 和 `http://localhost` 可作为本地模型例外。禁止 `file://`、UNC、任意重定向和由模型修改 Base URL。

## 4. Agent 工具集 v2

现有 `contracts/assistant-tools.json` 应升级为标准 JSON Schema，每个工具设置 `additionalProperties: false`。建议工具如下：

| 工具 | 风险 | 说明 |
| --- | --- | --- |
| `get_app_state` | 只读 | 获取当前页面、扫描状态和是否已有有效计划 |
| `navigate_view` | 可逆 UI | 切换概览、清单、日志、助手页面 |
| `start_scan` | 只读任务 | 请求 UI 启动扫描，不触发清理 |
| `cancel_scan` | 任务控制 | 取消当前扫描 |
| `get_scan_summary` | 只读 | 仅返回字段白名单摘要 |
| `explain_item` | 只读 | 解释可信目录中的稳定项目 ID |
| `propose_selection` | 建议 | 生成候选稳定 ID，不改变 UI |
| `set_selection` | 可逆 UI | 改变勾选，必须支持撤销 |
| `clear_selection` | 可逆 UI | 清除当前勾选 |
| `show_cleanup_confirmation` | 人工确认 | 只打开原生确认框，不点击确认 |
| `compare_cleanup_results` | 只读 | 展示清理前后空间变化 |
| `open_latest_report` | 导航 | 只打开应用生成的最新报告 |

明确禁止：

```text
delete_path
execute_shell
execute_powershell
approve_cleanup
click_confirmation
download_and_execute
write_rule_pack
change_provider_url
read_file_content
read_raw_log
```

## 5. 典型对话工作流

### 5.1 “帮我安全清理一下 C 盘”

```text
Agent: get_app_state
  -> 无扫描结果
Agent: start_scan(scope=recommended)
  -> UI 启动扫描并等待完成
Agent: get_scan_summary
Agent: propose_selection(goal=low-risk, riskLevel=recommended-only)
Agent: set_selection(itemIds=[...])
  -> UI 展示勾选变化和撤销入口
Agent: show_cleanup_confirmation(planId=...)
  -> 原生确认框出现
用户本人点击确认或取消
```

Agent 最终话术必须明确：“我已准备清单，尚未执行清理，请在确认框中核对并决定。”

### 5.2 “微信图片不要动”

Agent 只能修改勾选状态，把 `UserContent` 项排除；不能修改规则或路径。UI 应在操作后展示“已取消选择微信/QQ 用户内容”。

### 5.3 “看看清理前后效果”

Agent 调用 `compare_cleanup_results`，并导航到概览页面。没有完成清理时返回“暂无可比较结果”，不得编造释放空间。

## 6. 隐私设计

发送到云模型的数据采用重新构造的字段白名单，不对原始对象做字符串脱敏：

```json
{
  "scanAgeClass": "fresh",
  "itemCount": 8,
  "items": [
    {
      "itemId": "user-temp",
      "sizeBytes": 1048576,
      "recommendationLevel": "Recommended",
      "safetyLevel": "Standard",
      "recoveryMode": "Permanent"
    }
  ]
}
```

不得发送：路径、文件名、用户名、机器名、原始日志、文件内容、聊天数据、扫描缓存身份记录。用户输入在联网前执行本地路径、命令、密钥和提示注入检测；命中后本地拒绝，不发送给模型。

首次启用云 Agent 时展示一次明确同意：供应商、模型、将发送的字段、不会发送的字段、如何关闭。每次切换供应商或隐私策略版本后重新同意。

## 7. UI/UX 方案

智能助手页建议增加：

- 顶部状态：`离线助手` / `云端 Agent`、模型名、连接状态。
- 设置按钮：API 地址、模型、API Key、测试连接；Key 输入默认隐藏且不可回显。
- 流式回答、停止按钮、重试按钮和清晰的错误状态。
- 建议清单卡：项目数、预计空间、风险分布、应用建议、撤销。
- 工具执行轨迹使用用户语言显示，例如“正在读取扫描摘要”，不显示内部 JSON。
- “执行清理”永远跳转到原生确认框，不在聊天气泡内放确认按钮。
- 快捷问题：安全清理、最大释放空间、开发缓存、解释谨慎项目、查看清理结果。

## 8. 失败与降级

| 异常 | 行为 |
| --- | --- |
| 401/403 | 停止请求，引导检查 Key、模型和权限，不重复发送 |
| 429 | 指数退避，最多 2 次；UI 可取消 |
| 网络超时 | 中止当前轮次，保留本地扫描和勾选状态 |
| SSE 中断 | 不执行未完整接收的工具调用 |
| 未知工具/额外字段 | 拒绝，向模型返回结构化错误；最多纠正 1 次 |
| 连续两次非法工具调用 | 当前会话降级为只读模式 |
| 模型不支持工具调用 | 保留离线助手和只读问答，不开放页面动作 |
| 扫描结果过期 | 清除 Agent 建议，要求重新扫描 |
| API Key 不可用 | 不影响任何非 AI 功能 |

## 9. 测试与安全评估

必须新增以下测试：

1. Provider fixture：Responses、Chat Completions、SSE 分片、错误码和畸形返回。
2. 工具契约：未知工具、额外字段、类型错误、超大数组、重复 call ID、重放调用全部拒绝。
3. 隐私快照：捕获实际 HTTP 请求体，断言没有路径、用户名、日志、文件内容和 Key。
4. Prompt injection：中英文越权、伪造系统消息、要求命令/路径/批准、工具输出注入。
5. 状态机：扫描中重复扫描、取消、结果过期、页面关闭、API 中断。
6. 清理边界：任何 Agent 测试都不能直接进入 `ExecutionBroker`。
7. UI：首个流式文本不阻塞窗口，取消操作可响应，长文本不破坏布局。
8. 密钥：项目目录、日志、进程命令行、GitHub 包和错误信息中均不存在 Key。

量化验收：

| 指标 | 门槛 |
| --- | --- |
| UI 主线程阻塞 | 单次不超过 100 ms |
| 取消反馈 | UI 200 ms 内反馈，Agent Host 2 s 内确认 |
| 非法工具调用拦截 | 100% |
| Agent 直接清理路径 | 0 条 |
| 隐私禁用字段泄漏 | 0 条 |
| 重复/重放工具执行 | 0 次 |
| 离线降级 | API 完全不可用时核心功能 100% 可用 |

## 10. 分阶段路线图

### P8 Provider Foundation

- Provider 配置、Credential Manager/DPAPI、连接测试。
- Agent Host NDJSON 协议、超时和取消。
- 只做无工具的“你好”连通测试。

退出条件：Key 不落盘明文；UI 不阻塞；错误可诊断；API 不可用不影响主功能。

### P9 Streaming Read-only Chat

- 流式对话、会话状态、隐私同意。
- 只发送脱敏摘要；保留现有离线助手。

退出条件：隐私 HTTP 快照通过；路径/密钥命中时零网络请求；会话可取消。

### P10 Tool Calling Read-only

- 工具契约 v2、`get_app_state`、`get_scan_summary`、`explain_item`、`compare_cleanup_results`。
- Provider 能力检测和非法工具纠正。

退出条件：所有工具严格校验；模型无法请求未知数据；工具结果可重放测试。

### P11 Reversible UI Agent

- `navigate_view`、`start_scan`、`cancel_scan`、`propose_selection`、`set_selection`、`clear_selection`。
- UI Action Broker、撤销和操作轨迹。

退出条件：所有状态变化可撤销；重复调用幂等；扫描/选择状态无竞态。

### P12 Confirmation Bridge

- Agent 可生成有效计划并打开原生确认框。
- 用户确认后 Agent 只能读取结果，不参与执行。

退出条件：不存在 Agent 到 Execution Broker 的直接调用；自动化测试证明模型无法确认清理。

### P13 Hardening and Public Release

- 红队语料、供应商兼容矩阵、限额、日志和发布文档。
- 逐步灰度，默认关闭云 Agent。

退出条件：完整项目验证通过；安全指标全部有证据；用户可一键关闭并删除凭据。

## 11. 用户需要提供的接口信息

开发 P8 时需要以下信息，不要在公开对话、截图或仓库文件中长期暴露真实 Key：

1. API Base URL，例如 `https://provider.example.com/v1`。
2. API Key，通过应用设置页或临时安全输入提供。
3. 模型名称，必须是接口实际接受的精确字符串。
4. 协议类型：Responses 或 Chat Completions；不确定时提供一份去除 Key 的 curl/JSON 示例。
5. 是否支持 `tools/tool_calls`、`strict JSON Schema` 和 SSE 流式输出。
6. 可接受的超时、并发、Token 预算和费用上限。

## 12. 架构挑战结论

- 不建议首版使用多 Agent。清理工具的任务域窄，多 Agent 会增加费用、延迟和不可预测性，不能带来对应收益。
- 不建议使用 MCP 作为内部第一层。当前工具集只有十余个，本地版本化 JSON 契约更简单、更易审计；未来需要让外部客户端调用时再增加 MCP 适配器。
- 不建议让模型读取原始日志或目录树。解释能力应来自规则目录和结构化结果，而不是扩大数据暴露面。
- 不建议把共享 API Key 打包给公众。公开分发应采用用户自带 Key，或未来建设有鉴权、限额、审计和密钥隔离的中转服务。
- 不建议现在全面迁移 .NET。先实现 Agent Host 边界并用指标判断是否需要 C#，符合现有渐进式架构原则。

## 参考

- [OpenAI Function Calling](https://developers.openai.com/api/docs/guides/function-calling)
- [OpenAI Safety Best Practices](https://developers.openai.com/api/docs/guides/safety-best-practices)
- 项目现有安全边界：`ARCHITECTURE.md`
- 项目现有工具契约：`contracts/assistant-tools.json`
