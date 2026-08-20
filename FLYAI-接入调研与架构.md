# 飞猪 FlyAI 接入调研与架构

调研日期：2026-08-20

## 官方能力

- 官方网站：<https://flyai.open.fliggy.com/>
- 官方代码：<https://github.com/alibaba-flyai/flyai-skill>
- 官方安装包：`@fly-ai/flyai-cli`，要求 Node.js 18+，MIT License。
- 官方接入形态不是供桌面程序直接填写的通用 MCP Server URL，而是 FlyAI Skill 调用 `flyai-cli`，再由 CLI 访问 Fliggy MCP API。
- 当前公开能力集中在只读搜索：综合语义搜索、关键词搜索、机票、火车、酒店、景点及部分酒店套餐。
- 搜索结果为单行 JSON，可包含实时库存、价格、图片和跳转/预订链接。
- 2026-08-20 实测 `ai-search` 可返回完整中文行程。Node.js 24 在 Windows 上可能在结果输出后的 CLI 退出阶段触发 libuv 断言；适配器仅在 JSON 已完整校验且错误精确匹配该已知断言时接受结果，其余非零退出仍失败关闭。优先建议使用官方要求范围内的稳定 LTS Node.js 版本。

## 本项目方案

```text
用户旅行问题
  -> 本地旅行意图路由
  -> 本次会话隐私同意
  -> TravelHost 隔离进程
  -> 固定允许的 flyai ai-search / keyword-search
  -> 单行 JSON 校验与受限格式化
  -> 助手气泡展示建议及 HTTPS 详情链接
```

## 边界

- FlyAI 是可选能力，缺失时不影响扫描、清理或离线助手。
- 仅发送当前旅行问题，不发送扫描摘要、文件路径、用户名、日志、API Key 或清理计划。
- UI 不接收可执行命令；模型不能选择 CLI 路径、子命令或任意参数。
- 首期只开放 `ai-search` 和 `keyword-search`，不执行预订、支付、登录或旅客信息提交。
- 旅行结果不能调用清理工具；清理结果也不会进入旅行提供器上下文。
- 所有价格、余票、库存与退改规则以飞猪详情页实时信息为准。

## 后续演进

1. 增加 FlyAI 安装状态与隐私范围的独立设置页。
2. 将航班、酒店、火车、景点拆为严格 JSON Schema 工具，参数逐字段校验。
3. 使用内嵌 WebView 打开 HTTPS 详情页，但仍不自动提交订单。
4. 若官方未来提供稳定的标准 MCP Server 端点，再引入通用 MCP 客户端；在此之前不复制或猜测私有协议。
