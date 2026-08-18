# C盘智能清理

Windows C 盘扫描与清理工具。它先分析，再由用户逐项选择是否清理，并保留清理前后的空间对比和 HTML 诊断报告。

## 下载与运行

从 [Releases](https://github.com/tao66175545-boop/c-drive-cleaner/releases) 下载最新的 `C.zip`，解压后双击 `C盘清理.bat`。

运行环境：Windows 10/11、Windows PowerShell 5.1、Windows Forms。

## 使用流程

1. 点击“开始扫描”。扫描不会删除文件。
2. 在“清理清单”查看候选项的大小、建议和影响说明。
3. 手动勾选需要处理的项目。
4. 确认预计释放空间后点击“执行所选项”。
5. 在概览页或 HTML 报告中查看结果。

## 安全边界

- 空间大户、重复目录、聊天数据库、文件接收目录、休眠文件和页面文件只诊断，不自动删除。
- 微信/QQ 的图片与视频附件单列为“谨慎选择”，默认不勾选；不处理聊天数据库、`FileRecv` 或整个账号目录。
- 清理器拒绝盘根、Windows、用户主目录和脚本目录等保护路径，并跳过 junction/symlink 重解析点。
- 清理清单只传递固定项目 ID，不接受用户输入的删除路径。

## 项目结构

```text
C盘清理.bat              双击启动入口
C-Drive-Cleaner-UI.ps1   WinForms 图形界面
C-Drive-Cleaner.ps1      扫描、清理、安全闸和报告引擎
assets/                  Logo 与动效资源
OTA-在线升级方案.md      GitHub Releases 在线升级架构
```

## 验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -SelfTest
```

## 版本与更新

当前稳定版本为 `v1.0.0`。项目已准备版本清单和在线升级架构；自动更新将在代码签名、独立更新器和回滚机制完成后启用。

## 许可证

当前尚未指定开源许可证。公开仓库默认不向第三方授予复用授权。发布前请由仓库所有者选择 MIT、Apache-2.0 或其他适合的许可证。
