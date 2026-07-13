# Codex Quota Float

一个常驻桌面的 Codex 额度悬浮窗。它通过 Codex 官方 `account/rateLimits/read` 方法读取剩余百分比和重置时间，让额度状态不再藏在多层菜单后面。

![Codex Quota Float 展开状态](docs/images/widget-expanded.png)

> 当前为 Windows 预览版。额度读取依赖 Codex 的实验性接口，未来 Codex 更新可能需要同步适配。

## 功能

- 64 px 置顶额度环，尽量少占桌面空间。
- 单击展开摘要，双击打开详情，拖动可移动位置。
- 后台约每 60 秒无感刷新，不主动弹出窗口。
- 显示官方返回的额度周期、剩余百分比和重置时间。
- 区分 Codex 通用额度与官方单独返回的模型额度桶。
- 实时读取失败时可显示上次官方缓存，并明确标记为缓存。

## 安装

```powershell
codex plugin marketplace add zsy1122334455-netizen/codex-quota-float
codex plugin add codex-quota-float@codex-quota-float
```

安装后在 Codex 中说“打开 Codex 额度悬浮窗”，或在插件目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_float.ps1
```

停止悬浮窗：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop_float.ps1
```

## 交互

| 操作 | 结果 |
| --- | --- |
| 单击 | 在紧凑圆环和摘要视图之间切换 |
| 双击 | 打开完整额度详情 |
| 拖动 | 移动悬浮窗并记住位置 |
| 右键 | 刷新、打开网页面板或退出 |

## 关于模型额度

Codex 的模型选择列表不等于额度列表。插件只展示官方接口明确返回的额度桶：`codex` 视为通用共享额度，额外桶视为独立计量额度。它不会因为模型出现在选择器中，就推测该模型拥有独立百分比，也不会暗示用户当前正在使用某个模型。

## 隐私

- 不读取 `~/.codex/auth.json`。
- 不读取任务数据库、任务标题、提示词、对话内容或本地 Token 活动。
- 身份验证由当前 Codex 会话和 app-server 处理。
- 可选网页面板只监听 `127.0.0.1`，不能绑定到局域网地址。
- 本地只保存官方额度缓存、悬浮窗位置、进程号和错误日志。

完整说明见 [PRIVACY.md](PRIVACY.md)。

## 环境

- Windows 10 或 Windows 11。
- 已安装并登录 Codex。
- Python 3.11+，且包含 Tkinter。
- Node.js 用于插件 MCP 服务。

## 本地验证

```powershell
python -m compileall -q plugins\codex-quota-float\scripts
node --check plugins\codex-quota-float\mcp\server.mjs
python plugins\codex-quota-float\scripts\collect_status.py --pretty
```

## 限制

- 当前仅实现 Windows 桌面悬浮窗。
- `account/rateLimits/read` 属于 Codex 实验性能力，不承诺长期兼容。
- 官方没有返回独立额度桶的模型，不会出现在详情列表里。
- 项目与 OpenAI 无隶属关系，“Codex”是 OpenAI 的产品名称。

## 许可证

[MIT](LICENSE)
