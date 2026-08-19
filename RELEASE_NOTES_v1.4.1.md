# C盘智能清理 v1.4.1

## 修复

- 修复 Windows PowerShell 5.1 在部分现代 TLS 网关上调用模型接口时出现 `GetResult` / “发送请求时出错”的问题。
- Agent 网络层改用 Windows 自带 `curl.exe` 的 TLS 实现，同时保留证书验证和禁止自动重定向。
- API Key 通过子进程标准输入传递，不进入命令行、日志或请求 JSON 临时文件。
- 云端错误改为可操作的分类提示，区分鉴权、接口路径、限流、上游服务、DNS、连接、TLS、证书、超时和协议格式问题。
- API Key 拒绝换行字符，防止传输配置注入。

## 验证

- 已使用 OpenAI Responses 兼容网关验证模型列表、严格 Tool Calling、完整 AgentHost 请求和真实回答。
- 已确认部分供应商的“流式 + 工具调用”组合不稳定；该供应商可关闭流式响应并保留完整 Tool Calling。
- 新增安全传输回归测试，禁止关闭证书验证或把 Key 放入进程参数。
