# Codex Quota Float GitHub 首发设计

日期：2026-07-13
状态：已批准
目标版本：v0.1.0

## 1. 目标

把当前已在本机验证通过的 Codex 额度悬浮球整理为一个可公开安装、可审查、可复现验证的 Windows 开源项目，并发布到 GitHub。

首发成功标准：

- 公开仓库为 `zsy1122334455-netizen/codex-quota-float`，默认分支为 `main`。
- 代码采用 MIT License，版权标识使用 GitHub 账号 `zsy1122334455-netizen`。
- 发布 `v0.1.0` GitHub Release，并提供源码压缩包。
- 新用户按 README 能完成依赖安装、悬浮球安装、更新和卸载。
- 不公开缓存、窗口位置、账号信息、凭证、本机绝对路径或第三方短视频截图。
- 自动化测试通过，适合 CI 的测试在 GitHub Actions 中保持绿色。

## 2. 范围与非目标

本阶段包含：

- 整理公开仓库结构与文档。
- 修复公开分发所需的依赖发现、更新重启和卸载体验。
- 添加许可证、第三方声明、忽略规则、统一测试入口和 Windows CI。
- 制作干净的项目截图与首个 GitHub Release。
- 初始化 Git、创建公开仓库、推送源码并验证远程结果。

本阶段不包含：

- 微信公众号文章、排版或发布。
- 移除 Win-CodexBar 依赖、直接调用未公开的 OpenAI 接口或读取 Codex 凭证。
- macOS、Linux 支持。
- 自动下载或静默安装 Win-CodexBar。
- 代码签名、Microsoft Store 或 Winget 分发。

## 3. 项目定位与公开表述

项目定位为“非官方 Windows Codex 额度桌面悬浮球”。仓库和 Release 必须明确：

- 本项目不是 OpenAI 官方产品，与 OpenAI 或 Win-CodexBar 作者不存在隶属关系。
- 数据来自本机已经安装和配置的 Win-CodexBar CLI，不是 OpenAI 官方公开额度 API。
- 剩余百分比由 CLI 返回的已用百分比换算；准确性和刷新速度受上游数据影响。
- 本项目不直接读取、复制或保存 Codex 登录凭证，也不包含自行上传额度数据的代码。
- 本地仅缓存套餐名、额度百分比、重置时间、更新时间和窗口位置。

## 4. 第三方依赖

唯一运行时外部依赖为 Win-CodexBar：

- 仓库：`https://github.com/Finesssee/Win-CodexBar`
- 许可证：MIT
- 推荐安装：`winget install Finesssee.Win-CodexBar`
- 本机已验证 CLI 版本：`0.41.3`
- 兼容条件：`codexbar-cli.exe usage -p codex --format json` 能返回 Codex 用量 JSON。

本项目不复制或重新分发 Win-CodexBar 二进制文件。`THIRD_PARTY_NOTICES.md` 只记录依赖、用途、仓库和许可证。

## 5. 公开版功能调整

### 5.1 CLI 自动发现

新增单一入口 `Resolve-CodexBarCliPath`，按以下顺序查找：

1. 环境变量 `CODEXBAR_CLI_PATH` 指向的有效文件。
2. 默认安装路径 `%LOCALAPPDATA%\Programs\CodexBar\codexbar-cli.exe`。
3. `PATH` 中可解析的 `codexbar-cli.exe`。

未找到依赖时，悬浮球继续运行并显示中文缺失提示；README 提供 Winget 安装命令。程序不自动下载安装第三方软件。

### 5.2 安全更新与重启

`install.ps1` 在更新时只终止命令行明确指向目标安装目录 `CodexQuotaFloat.ps1` 的旧实例，等待退出后复制文件，再启动新实例。它不得终止无关的 PowerShell 或源码测试进程。

安装器继续写入当前用户开机启动项：

`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexQuotaFloat`

### 5.3 卸载

新增 `uninstall.ps1`：

- 终止已安装的悬浮球实例。
- 删除开机启动项。
- 删除 `%APPDATA%\CodexQuotaFloat` 下的程序、缓存和位置设置。
- 不修改或卸载 Win-CodexBar。

### 5.4 现有体验保持不变

- 60×60 悬浮球显示剩余额度。
- 点击展开中文精简卡片，再次点击收起。
- 失去焦点不自动消失。
- 可拖动、置顶、保存位置、右键刷新和退出。
- 每 60 秒刷新；失败时保留缓存并用橙色状态点提示。

## 6. 仓库结构

```text
codex-quota-float/
├─ .github/workflows/test.yml
├─ assets/
│  ├─ hero.png
│  ├─ widget-compact.png
│  └─ widget-expanded.png
├─ docs/superpowers/specs/
│  └─ 2026-07-13-codex-quota-float-github-release-design.md
├─ tests/
│  ├─ run-tests.ps1
│  └─ *.Tests.ps1
├─ .gitignore
├─ CodexQuotaFloat.ps1
├─ QuotaData.psm1
├─ install.ps1
├─ uninstall.ps1
├─ run-hidden.vbs
├─ LICENSE
├─ README.md
└─ THIRD_PARTY_NOTICES.md
```

README 以简体中文为主，包含简短英文摘要；内容覆盖功能、效果图、系统要求、依赖安装、安装、更新、卸载、隐私、数据来源、故障排查和非官方声明。

## 7. 图片策略

- 使用自行生成的主视觉和程序实机截图。
- 不上传用户提供的抖音截图或其中的创作者内容。
- 实时数据截图只展示悬浮球自身，不带个人账户信息。
- 测试夹具产生的双额度截图若使用，必须标注“演示数据”。
- GitHub README 优先使用紧凑的收起态和展开态截图，不把低分辨率截图放大成主视觉。

## 8. 测试与 CI

`tests/run-tests.ps1` 提供统一入口：

- 默认运行语法、数据解析、结构和安装注册测试。
- `-Interactive` 才运行窗口点击和截图测试。

GitHub Actions 使用 `windows-latest` 和 Windows PowerShell 5.1，只运行无需交互桌面的测试。发布前本机额外运行点击与三种界面状态截图验证。

安装器和卸载器测试必须使用临时安装目录、独立的测试启动项名称和禁用自动启动参数；测试不得停止当前正式悬浮球，也不得删除真实缓存或正式开机启动项。

必须覆盖：

- CLI 三种发现路径和缺失状态。
- 安装器只终止目标安装实例。
- 更新后新实例实际运行新文件。
- 卸载移除启动项、程序目录与本地缓存。
- 原有额度换算、圆环边界、中文重置文案、尺寸和点击切换回归。

## 9. GitHub 发布流程

1. 用户重新完成 `gh auth login -h github.com`，目标账号为 `zsy1122334455-netizen`。
2. 在当前 `CodexQuotaFloat` 目录初始化 Git，默认分支为 `main`。
3. 只暂存公开清单内的文件，运行秘密与本机路径扫描。
4. 运行全部自动测试和本机交互验收。
5. 创建首个提交：`Release Codex Quota Float v0.1.0`。
6. 创建公开仓库 `zsy1122334455-netizen/codex-quota-float` 并推送 `main`。
7. 确认 GitHub Actions 成功、README 图片和链接正常。
8. 创建未签名的普通 Git 标签 `v0.1.0` 与 GitHub Release。Release 附带 `codex-quota-float-v0.1.0.zip` 和对应 `.sha256`；安装包只包含运行文件、README、LICENSE 与第三方声明，GitHub 自动生成的 Source code 归档保留完整仓库源码。

如果同名仓库已存在、账号不是预期账号、远程仓库非空或 CI 失败，则停止发布并先处理冲突，不覆盖远程历史。

## 10. 验收标准

- `git status` 干净，远程 `main` 与本地提交一致。
- 仓库可公开访问，LICENSE 被 GitHub 识别为 MIT。
- README 中的安装、依赖、图片和免责声明均可正常显示。
- GitHub Actions 通过；本机交互测试通过。
- Release `v0.1.0` 可访问，资产 SHA-256 与本地一致。
- 仓库历史与 Release 中不存在 Token、Cookie、缓存 JSON、本机用户名或绝对路径。
- 发布后本机已安装悬浮球仍能启动并显示与 CLI 一致的额度。
