# Codex 额度悬浮球

Windows 桌面小组件：默认显示 5 小时额度剩余百分比，点击展开后显示本周剩余和重置时间。

## 使用方式

- 左键单击悬浮球：展开或收起。
- 左键拖动：移动到任意屏幕位置。
- 右键：立即刷新、开机启动、打开完整统计、退出。
- 数据每 60 秒刷新一次；网络异常时保留上次成功数据，并显示“数据暂未更新”。

## 数据与隐私

组件通过已安装的 Win-CodexBar 命令读取额度 JSON，不直接读取、复制、显示或保存 Codex 登录凭证。

## 安装与更新

运行 `install.ps1` 会将程序安装到 `%APPDATA%\CodexQuotaFloat`、启动组件，并添加当前用户的 Windows 开机启动项。

## 卸载

退出悬浮球后，删除 `%APPDATA%\CodexQuotaFloat`，并移除注册表项：

`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexQuotaFloat`
