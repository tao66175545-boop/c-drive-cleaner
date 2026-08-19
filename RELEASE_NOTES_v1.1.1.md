# C盘智能清理 v1.1.1

发布日期：2026-08-19

## 发布修复

- Release ZIP 改用稳定的 ASCII 文件名 `C-Drive-Cleaner-v1.1.1.zip`。
- 修复 GitHub 清洗中文附件名后，`release.json` 中下载 URL 与实际 Release 资产不一致的问题。
- SHA-256、文件大小和下载地址仍由同一次 GitHub Actions 构建自动生成。

## 同时包含

- v2 清理计划：稳定目标 ID、扫描编号、规则哈希、有效期和大小快照。
- 微信/QQ 用户内容发生变化时安全中止并要求重新扫描。
- 报告迁移到 `%LOCALAPPDATA%\CDriveCleaner\reports`。
- UI 正确区分完成、失败和安全中止。
- 最小权限的两阶段 GitHub 发布流水线。
