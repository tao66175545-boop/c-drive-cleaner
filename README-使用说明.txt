C 盘清理工具

一、使用方式
1. 解压整个文件夹，不要只拿其中一个文件。
2. 双击“C盘清理.bat”。
3. 在图形界面点击“开始扫描”。扫描默认不删除任何文件。
4. 扫描完成后进入“清理清单”，查看每项的占用、建议与影响说明，自行勾选需要处理的项目。
5. 确认汇总的数量和预计释放空间后，点击“执行所选项”。

二、文件说明
- C-Drive-Cleaner.ps1：主程序，负责扫描、诊断、安全清理和报告。
- C-Drive-Cleaner-UI.ps1：WinForms 图形界面外壳。
- assets\logo-animated.svg：上传的曙光云 Logo 动画源文件。
- assets\logo-animated-sprite.png：由 SVG 浏览器时间轴预渲染的 135 帧 Logo（60fps、2.22 秒），用于 WinForms 平滑播放。
- assets\cleaning-sprite-source.png：清理小助手的 8 帧透明序列图，界面启动时自动裁剪加载。
- C盘清理.bat：双击启动入口。

三、安全边界
- 空间大户、重复目录、微信/QQ 根目录、休眠文件、页面文件只诊断，不自动删除。
- 微信/QQ 图片与视频附件会作为独立的“谨慎选择”项目显示，默认不勾选；仅覆盖应用的指定图片/视频附件目录，不处理聊天数据库、FileRecv 或整个账号目录。
- 清理模式只处理主程序清单中的缓存和临时文件。
- 图形界面只会执行用户在本次扫描清单中勾选的固定项目 ID；不接受文件路径输入，未知或过期项目 ID 会被拒绝。
- 清理计划有效期为 30 分钟；清理规则、计划快照或微信/QQ 用户内容发生变化时会要求重新扫描。
- 清理前图形界面会再次确认。
- 主程序包含保护路径检查，并跳过 junction/symlink 重解析点。
- 需要管理员权限的系统项目会在非管理员模式下跳过。
- 点击“执行所选项”并确认后，右上角清理小助手会播放序列帧；清理完成后恢复静止状态。
- 左侧 Logo 默认显示完整品牌图，鼠标移入或点击时按源文件的 2.22 秒速率播放一次；结束后恢复与动画最后一帧一致的静止状态。
- HTML 报告保存在 %LOCALAPPDATA%\CDriveCleaner\reports，不写入程序目录。

四、环境要求
- Windows PowerShell 5.1
- Windows Forms（Windows 系统通常自带）
- 建议使用 Windows 10/11

五、命令行安全自检
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -SelfTest
