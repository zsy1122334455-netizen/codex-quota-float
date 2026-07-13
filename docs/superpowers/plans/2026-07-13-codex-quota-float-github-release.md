# Codex Quota Float GitHub Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a safe, installable, tested public `v0.1.0` release of Codex Quota Float at `zsy1122334455-netizen/codex-quota-float`.

**Architecture:** Keep the existing Windows PowerShell 5.1/WPF widget and parsing module, add a small lifecycle module shared by install and uninstall scripts, and make Win-CodexBar executable discovery a pure module responsibility. Public documentation, assets, a non-interactive test runner, and Windows CI wrap the existing application without changing its quota model or UI behavior.

**Tech Stack:** Windows PowerShell 5.1, WPF, Win32/CIM process inspection, Git, GitHub CLI, GitHub Actions on `windows-latest`.

## Global Constraints

- Repository: public `zsy1122334455-netizen/codex-quota-float`, default branch `main`.
- License: MIT, copyright holder `zsy1122334455-netizen`.
- Release: `v0.1.0` with `codex-quota-float-v0.1.0.zip` and matching `.sha256`.
- Platform: Windows with Windows PowerShell 5.1 and WPF; no macOS or Linux support in v0.1.0.
- Runtime dependency: Win-CodexBar from `https://github.com/Finesssee/Win-CodexBar`; do not redistribute its binaries.
- Compatibility contract: `codexbar-cli.exe usage -p codex --format json` returns Codex usage JSON; local verified version is 0.41.3.
- Product wording: non-official community tool; never claim an official OpenAI quota API or guaranteed real-time accuracy.
- Privacy: never commit cache JSON, settings, credentials, cookies, tokens, usernames, machine paths, or user-provided short-video screenshots.
- Existing UX remains: 60×60 collapsed ring, 250px Chinese expanded card, click toggle, drag, Topmost, saved location, 60-second refresh, stale cache indicator.
- Tests for installation lifecycle use a temporary target directory, unique Run value name, and `-NoLaunch`; they never touch the live widget registration or cache.

---

## File Responsibility Map

- `QuotaData.psm1`: quota parsing, display helpers, and Win-CodexBar CLI/app discovery.
- `CodexQuotaFloat.ps1`: WPF window, refresh loop, user interaction; consumes resolver functions from `QuotaData.psm1`.
- `Lifecycle.psm1`: exact installed-widget process matching and safe stop logic shared by install/uninstall.
- `install.ps1`: copy runtime files, safely replace the installed instance, register startup, launch the new instance.
- `uninstall.ps1`: stop the installed instance, remove startup registration, delete installed files/cache/settings.
- `tests/*.Tests.ps1`: focused unit/structure/lifecycle/public-release checks.
- `tests/run-tests.ps1`: one CI-safe entrypoint plus optional interactive UI checks.
- `.github/workflows/test.yml`: Windows PowerShell 5.1 CI.
- `README.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`: public usage, legal, privacy, dependency, and support information.
- `assets/*`: generated hero and tightly cropped real widget screenshots only.

---

### Task 1: Initialize a Safe Baseline and Isolated Worktree

**Files:**
- Verify: `.gitignore`
- Existing: `CodexQuotaFloat.ps1`, `QuotaData.psm1`, `install.ps1`, `run-hidden.vbs`, `README.md`
- Existing: `tests/*.ps1`
- Existing: `docs/superpowers/specs/2026-07-13-codex-quota-float-github-release-design.md`
- Existing: `docs/superpowers/plans/2026-07-13-codex-quota-float-github-release.md`

**Interfaces:**
- Consumes: approved release design and current passing source.
- Produces: local `main` baseline plus isolated `.worktrees/github-release` on `agent/github-release`.

- [ ] **Step 1: Initialize Git only inside the project directory**

从项目根目录运行：

```powershell
git init -b main
git config user.name "zsy1122334455-netizen"
git config user.email "zsy1122334455-netizen@users.noreply.github.com"
git rev-parse --show-toplevel
git config user.name
git config user.email
```

Expected: repository root is the current `CodexQuotaFloat` directory; repository-local email is the GitHub noreply address, so the existing Gmail address is not exposed in public commit metadata.

- [ ] **Step 2: Verify no remote or prior history exists**

```powershell
git remote -v
git log --oneline -1
```

Expected: no remotes; `git log` reports that the current branch has no commits. If either check shows existing state, stop rather than overwrite it.

- [ ] **Step 3: Add public-ignore and worktree protection rules**

Create `.gitignore` with:

```gitignore
.worktrees/
.superpowers/
last_usage.json
settings.json
*.log
*.tmp
dist/
.vscode/
.idea/
.DS_Store
Thumbs.db
design/
```

```powershell
New-Item -ItemType Directory -Path .worktrees -Force | Out-Null
git check-ignore -q .worktrees\probe
git check-ignore -q design
```

Expected: both commands exit 0.

- [ ] **Step 4: Verify the existing baseline before committing it**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\QuotaData.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\WidgetStructure.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Install.Tests.ps1
```

Expected: all three non-interactive existing tests PASS. The already-installed widget remains running; interactive mutex-sensitive tests run later in a controlled stop/restart window.

- [ ] **Step 5: Commit the safe baseline and approved documents**

```powershell
git add -- .gitignore CodexQuotaFloat.ps1 QuotaData.psm1 install.ps1 run-hidden.vbs README.md tests docs/superpowers
git diff --cached --check
git diff --cached --name-only
git commit -m "chore: import Codex Quota Float"
```

Expected: one root commit containing source, tests, `.gitignore`, spec, and plan; no file under `design/` is staged.

- [ ] **Step 6: Create and verify the isolated worktree**

```powershell
git check-ignore -q .worktrees\probe
git worktree add .worktrees\github-release -b agent/github-release
git -C .worktrees\github-release branch --show-current
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.worktrees\github-release\tests\QuotaData.Tests.ps1
```

Expected: branch is `agent/github-release` and the baseline test passes. All later implementation tasks run from the absolute `.worktrees\github-release` directory.

---

### Task 2: Add Testable Win-CodexBar Executable Discovery

**Files:**
- Modify: `QuotaData.psm1:123-210`
- Modify: `CodexQuotaFloat.ps1:12-16,240-250,299-304`
- Modify: `tests/QuotaData.Tests.ps1:164-171`
- Modify: `tests/WidgetStructure.Tests.ps1:73-85`

**Interfaces:**
- Consumes: `CODEXBAR_CLI_PATH`, `CODEXBAR_APP_PATH`, `LOCALAPPDATA`, and Windows `PATH`.
- Produces: `Resolve-CodexBarCliPath([string]$ConfiguredPath, [string]$LocalAppData) -> string|null` and `Resolve-CodexBarAppPath([string]$ConfiguredPath, [string]$LocalAppData) -> string|null`.

- [ ] **Step 1: Add failing discovery tests**

Append isolated temp-directory assertions to `tests/QuotaData.Tests.ps1`:

```powershell
foreach ($commandName in @('Resolve-CodexBarCliPath', 'Resolve-CodexBarAppPath')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "FAIL: $commandName is not defined."
    }
}

$resolverRoot = Join-Path $env:TEMP ('CodexQuotaFloat-resolver-' + [guid]::NewGuid().ToString('N'))
$defaultDirectory = Join-Path $resolverRoot 'Programs\CodexBar'
New-Item -ItemType Directory -Path $defaultDirectory -Force | Out-Null
try {
    $configuredCli = Join-Path $resolverRoot 'custom-codexbar-cli.exe'
    Set-Content -LiteralPath $configuredCli -Value ''
    Assert-Equal -Actual (Resolve-CodexBarCliPath -ConfiguredPath $configuredCli -LocalAppData $resolverRoot) -Expected $configuredCli -Name 'configured CLI path wins'

    $defaultCli = Join-Path $defaultDirectory 'codexbar-cli.exe'
    Set-Content -LiteralPath $defaultCli -Value ''
    Assert-Equal -Actual (Resolve-CodexBarCliPath -ConfiguredPath '' -LocalAppData $resolverRoot) -Expected $defaultCli -Name 'default CLI install path'

    $defaultApp = Join-Path $defaultDirectory 'codexbar.exe'
    Set-Content -LiteralPath $defaultApp -Value ''
    Assert-Equal -Actual (Resolve-CodexBarAppPath -ConfiguredPath '' -LocalAppData $resolverRoot) -Expected $defaultApp -Name 'default app install path'

    Remove-Item -LiteralPath $defaultCli,$defaultApp -Force
    Assert-Equal -Actual (Resolve-CodexBarCliPath -ConfiguredPath '' -LocalAppData $resolverRoot) -Expected $null -Name 'missing CLI returns null'
}
finally {
    Remove-Item -LiteralPath $resolverRoot -Recurse -Force -ErrorAction SilentlyContinue
}
```

Update `tests/WidgetStructure.Tests.ps1` to require the resolver calls and reject direct hard-coded assignment:

```powershell
if ($source -notmatch '\$cliPath\s*=\s*Resolve-CodexBarCliPath') {
    throw 'FAIL: widget must resolve the CodexBar CLI path.'
}
if ($source -notmatch '\$codexBarPath\s*=\s*Resolve-CodexBarAppPath') {
    throw 'FAIL: widget must resolve the CodexBar app path.'
}
```

- [ ] **Step 2: Run tests to verify failure**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\QuotaData.Tests.ps1
```

Expected: FAIL because `Resolve-CodexBarCliPath` is not defined.

- [ ] **Step 3: Implement the resolver functions**

Add to `QuotaData.psm1` before `Export-ModuleMember`:

```powershell
function Resolve-CodexBarExecutablePath {
    param(
        [AllowNull()][AllowEmptyString()][string]$ConfiguredPath,
        [AllowNull()][AllowEmptyString()][string]$LocalAppData,
        [Parameter(Mandatory)][string]$FileName
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath) -and (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf)) {
        return [IO.Path]::GetFullPath($ConfiguredPath)
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalAppData)) {
        $defaultPath = Join-Path $LocalAppData (Join-Path 'Programs\CodexBar' $FileName)
        if (Test-Path -LiteralPath $defaultPath -PathType Leaf) { return [IO.Path]::GetFullPath($defaultPath) }
    }

    $command = Get-Command $FileName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { return [IO.Path]::GetFullPath($command.Source) }
    return $null
}

function Resolve-CodexBarCliPath {
    param(
        [AllowNull()][AllowEmptyString()][string]$ConfiguredPath = $env:CODEXBAR_CLI_PATH,
        [AllowNull()][AllowEmptyString()][string]$LocalAppData = $env:LOCALAPPDATA
    )
    Resolve-CodexBarExecutablePath -ConfiguredPath $ConfiguredPath -LocalAppData $LocalAppData -FileName 'codexbar-cli.exe'
}

function Resolve-CodexBarAppPath {
    param(
        [AllowNull()][AllowEmptyString()][string]$ConfiguredPath = $env:CODEXBAR_APP_PATH,
        [AllowNull()][AllowEmptyString()][string]$LocalAppData = $env:LOCALAPPDATA
    )
    Resolve-CodexBarExecutablePath -ConfiguredPath $ConfiguredPath -LocalAppData $LocalAppData -FileName 'codexbar.exe'
}
```

Add both public functions to `Export-ModuleMember`. In `CodexQuotaFloat.ps1`, replace lines 15-16 with:

```powershell
$cliPath = Resolve-CodexBarCliPath
$codexBarPath = Resolve-CodexBarAppPath
```

Keep the missing CLI branch null-safe:

```powershell
if ([string]::IsNullOrWhiteSpace($cliPath) -or -not (Test-Path -LiteralPath $cliPath)) {
```

Make the Open Details menu check null-safe in the same way.

- [ ] **Step 4: Run focused and regression tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\QuotaData.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\WidgetStructure.Tests.ps1
```

Expected: both PASS.

- [ ] **Step 5: Commit resolver changes**

```powershell
git add -- QuotaData.psm1 CodexQuotaFloat.ps1 tests/QuotaData.Tests.ps1 tests/WidgetStructure.Tests.ps1
git diff --cached --check
git commit -m "feat: discover Win-CodexBar executables"
```

---

### Task 3: Make Install, Update, and Uninstall Safe and Testable

**Files:**
- Create: `Lifecycle.psm1`
- Create: `uninstall.ps1`
- Create: `tests/Lifecycle.Tests.ps1`
- Modify: `install.ps1:1-20`
- Modify: `tests/Install.Tests.ps1:1-19`

**Interfaces:**
- Produces: `Test-ProcessCommandTargetsScript([string]$CommandLine,[string]$ScriptPath) -> bool` and `Stop-CodexQuotaFloatInstance([string]$ScriptPath) -> int[]`.
- Installer parameters: `-RegisterOnly`, `-TargetDirectory`, `-RunValueName`, `-NoLaunch`.
- Uninstaller parameters: `-TargetDirectory`, `-RunValueName`.

- [ ] **Step 1: Add failing lifecycle matching tests**

Create `tests/Lifecycle.Tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'Lifecycle.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) { throw 'FAIL: Lifecycle.psm1 is missing.' }
Import-Module $modulePath -Force

$target = 'C:\Users\Public\CodexQuotaFloat\CodexQuotaFloat.ps1'
$exact = 'powershell.exe -NoProfile -File "C:\Users\Public\CodexQuotaFloat\CodexQuotaFloat.ps1"'
$source = 'powershell.exe -NoProfile -File "C:\src\CodexQuotaFloat\CodexQuotaFloat.ps1"'
$mentionOnly = 'powershell.exe -Command "$x=''C:\Users\Public\CodexQuotaFloat\CodexQuotaFloat.ps1''"'

if (-not (Test-ProcessCommandTargetsScript -CommandLine $exact -ScriptPath $target)) { throw 'FAIL: exact installed script was not matched.' }
if (Test-ProcessCommandTargetsScript -CommandLine $source -ScriptPath $target) { throw 'FAIL: source widget was incorrectly matched.' }
if (Test-ProcessCommandTargetsScript -CommandLine $mentionOnly -ScriptPath $target) { throw 'FAIL: a plain path mention was incorrectly matched.' }

Write-Host 'PASS: lifecycle process matching is exact.'
```

- [ ] **Step 2: Run the test to verify failure**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Lifecycle.Tests.ps1
```

Expected: FAIL because `Lifecycle.psm1` is missing.

- [ ] **Step 3: Implement exact process matching and stopping**

Create `Lifecycle.psm1`:

```powershell
Set-StrictMode -Version Latest

function Test-ProcessCommandTargetsScript {
    param(
        [AllowNull()][string]$CommandLine,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($ScriptPath)
    $pattern = '(?i)(?:^|\s)-File\s+(?:"' + [regex]::Escape($fullPath) + '"|' + [regex]::Escape($fullPath) + ')(?:\s|$)'
    return [bool]($CommandLine -match $pattern)
}

function Stop-CodexQuotaFloatInstance {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $stopped = New-Object System.Collections.Generic.List[int]
    $processes = Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('powershell.exe', 'pwsh.exe') }
    foreach ($process in $processes) {
        if (-not (Test-ProcessCommandTargetsScript -CommandLine $process.CommandLine -ScriptPath $ScriptPath)) { continue }
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        [void]$stopped.Add([int]$process.ProcessId)
    }
    return @($stopped)
}

Export-ModuleMember -Function Test-ProcessCommandTargetsScript, Stop-CodexQuotaFloatInstance
```

- [ ] **Step 4: Run lifecycle test to verify pass**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Lifecycle.Tests.ps1
```

Expected: PASS.

- [ ] **Step 5: Add failing isolated install/uninstall tests**

Replace `tests/Install.Tests.ps1` with a test that uses a GUID target and Run value:

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $env:TEMP ('CodexQuotaFloat-install-' + [guid]::NewGuid().ToString('N'))
$runName = 'CodexQuotaFloatTest-' + [guid]::NewGuid().ToString('N')
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
try {
    & (Join-Path $root 'install.ps1') -TargetDirectory $target -RunValueName $runName -NoLaunch
    foreach ($file in @('CodexQuotaFloat.ps1','QuotaData.psm1','Lifecycle.psm1','run-hidden.vbs','install.ps1','uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $target $file))) { throw "FAIL: installer did not copy $file." }
    }
    $value = (Get-ItemProperty -Path $runPath -Name $runName -ErrorAction Stop).$runName
    if ($value -notmatch [regex]::Escape((Join-Path $target 'run-hidden.vbs'))) { throw 'FAIL: isolated startup value is incorrect.' }

    Set-Content -LiteralPath (Join-Path $target 'last_usage.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $target 'settings.json') -Value '{}'
    & (Join-Path $root 'uninstall.ps1') -TargetDirectory $target -RunValueName $runName
    if (Test-Path -LiteralPath $target) { throw 'FAIL: uninstall left the target directory behind.' }
    if ($null -ne (Get-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue)) { throw 'FAIL: uninstall left the startup value behind.' }
}
finally {
    Remove-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'PASS: isolated install and uninstall lifecycle works.'
```

- [ ] **Step 6: Run install test to verify failure**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Install.Tests.ps1
```

Expected: FAIL because the current installer does not accept isolation parameters and `uninstall.ps1` is missing.

- [ ] **Step 7: Implement the installer contract**

Rewrite `install.ps1` with these exact behaviors:

```powershell
param(
    [switch]$RegisterOnly,
    [string]$TargetDirectory = (Join-Path $env:APPDATA 'CodexQuotaFloat'),
    [string]$RunValueName = 'CodexQuotaFloat',
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
$sourceDirectory = $PSScriptRoot
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$targetScript = Join-Path $TargetDirectory 'CodexQuotaFloat.ps1'

Import-Module (Join-Path $sourceDirectory 'Lifecycle.psm1') -Force

if (-not $RegisterOnly) {
    [void](Stop-CodexQuotaFloatInstance -ScriptPath $targetScript)
    New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    foreach ($file in @('CodexQuotaFloat.ps1','QuotaData.psm1','Lifecycle.psm1','run-hidden.vbs','install.ps1','uninstall.ps1')) {
        Copy-Item -LiteralPath (Join-Path $sourceDirectory $file) -Destination (Join-Path $TargetDirectory $file) -Force
    }
}

$launcher = Join-Path $TargetDirectory 'run-hidden.vbs'
if (-not (Test-Path -LiteralPath $launcher)) { throw "Launcher not found: $launcher" }
Set-ItemProperty -Path $runPath -Name $RunValueName -Value ('wscript.exe "' + $launcher + '"')

if (-not $RegisterOnly -and -not $NoLaunch) {
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $launcher + '"')
}
Write-Host 'CodexQuotaFloat installation completed.'
```

- [ ] **Step 8: Implement uninstall without touching Win-CodexBar**

Create `uninstall.ps1`:

```powershell
param(
    [string]$TargetDirectory = (Join-Path $env:APPDATA 'CodexQuotaFloat'),
    [string]$RunValueName = 'CodexQuotaFloat'
)
$ErrorActionPreference = 'Stop'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$modulePath = Join-Path $PSScriptRoot 'Lifecycle.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) { $modulePath = Join-Path $TargetDirectory 'Lifecycle.psm1' }
Import-Module $modulePath -Force

[void](Stop-CodexQuotaFloatInstance -ScriptPath (Join-Path $TargetDirectory 'CodexQuotaFloat.ps1'))
Remove-ItemProperty -Path $runPath -Name $RunValueName -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $TargetDirectory) {
    $fullTarget = [IO.Path]::GetFullPath($TargetDirectory)
    $appDataPrefix = [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\') + '\'
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not ($fullTarget.StartsWith($appDataPrefix, [StringComparison]::OrdinalIgnoreCase) -or $fullTarget.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to remove a target outside APPDATA or TEMP: $fullTarget"
    }
    Remove-Item -LiteralPath $fullTarget -Recurse -Force
}
Write-Host 'CodexQuotaFloat uninstall completed.'
```

- [ ] **Step 9: Run lifecycle regression tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Lifecycle.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Install.Tests.ps1
```

Expected: both PASS; live `CodexQuotaFloat` Run value and `%APPDATA%\CodexQuotaFloat` remain unchanged.

- [ ] **Step 10: Commit lifecycle changes**

```powershell
git add -- Lifecycle.psm1 install.ps1 uninstall.ps1 tests/Lifecycle.Tests.ps1 tests/Install.Tests.ps1
git diff --cached --check
git commit -m "feat: add safe install lifecycle"
```

---

### Task 4: Add Public Metadata, Documentation, and Safe Assets

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `tests/PublicRelease.Tests.ps1`
- Rewrite: `README.md`
- Create: `assets/hero.png`
- Create: `assets/widget-compact.png`
- Create: `assets/widget-expanded.png`
- Keep ignored locally: `design/`

**Interfaces:**
- Consumes: approved legal/privacy wording and existing generated/actual screenshots.
- Produces: GitHub-renderable public project page with no third-party short-video assets.

- [ ] **Step 1: Add a failing public-release contract test**

Create `tests/PublicRelease.Tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($file in @('.gitignore','LICENSE','THIRD_PARTY_NOTICES.md','README.md','assets\hero.png','assets\widget-compact.png','assets\widget-expanded.png')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "FAIL: public file is missing: $file" }
}
$readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'), [Text.Encoding]::UTF8)
foreach ($required in @('非官方','Win-CodexBar','winget install Finesssee.Win-CodexBar','CODEXBAR_CLI_PATH','安装','更新','卸载','隐私','故障排查')) {
    if ($readme -notmatch [regex]::Escape($required)) { throw "FAIL: README is missing '$required'." }
}
$license = [IO.File]::ReadAllText((Join-Path $root 'LICENSE'), [Text.Encoding]::UTF8)
if ($license -notmatch 'MIT License' -or $license -notmatch '2026 zsy1122334455-netizen') { throw 'FAIL: MIT license identity is incorrect.' }
$notice = [IO.File]::ReadAllText((Join-Path $root 'THIRD_PARTY_NOTICES.md'), [Text.Encoding]::UTF8)
if ($notice -notmatch 'Finesssee/Win-CodexBar' -or $notice -notmatch 'MIT') { throw 'FAIL: third-party notice is incomplete.' }
Write-Host 'PASS: public release metadata is complete.'
```

- [ ] **Step 2: Run test to verify failure**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\PublicRelease.Tests.ps1
```

Expected: FAIL because LICENSE, notices, and public assets are not present.

- [ ] **Step 3: Verify `.gitignore` remains complete**

It must contain exactly these public safety entries:

```gitignore
.worktrees/
.superpowers/
last_usage.json
settings.json
*.log
*.tmp
dist/
.vscode/
.idea/
.DS_Store
Thumbs.db
design/
```

- [ ] **Step 4: Add the MIT license and third-party notice**

`LICENSE` uses the standard MIT text beginning with:

```text
MIT License

Copyright (c) 2026 zsy1122334455-netizen
```

`THIRD_PARTY_NOTICES.md` states that Win-CodexBar is an external MIT-licensed dependency at `https://github.com/Finesssee/Win-CodexBar`, is invoked through its installed CLI, and is not bundled or redistributed.

- [ ] **Step 5: Rewrite README with complete public sections**

Use this exact heading order:

```markdown
# Codex Quota Float

> 非官方 Windows Codex 额度桌面悬浮球。An unofficial Windows desktop quota widget for Codex.

![Codex Quota Float](assets/hero.png)

## 功能
## 界面
## 系统要求
## 安装 Win-CodexBar
## 安装悬浮球
## 使用
## 更新
## 卸载
## 数据来源与隐私
## 故障排查
## 开发与测试
## 第三方项目与免责声明
## License
```

The installation commands are:

```powershell
winget install Finesssee.Win-CodexBar
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Document `CODEXBAR_CLI_PATH` as the override for non-default installations, state that cached data lives under `%APPDATA%\CodexQuotaFloat`, and describe update as re-running `install.ps1`. Uninstall command is `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`.

- [ ] **Step 6: Copy only approved images into `assets`**

Create `assets` and copy:

```powershell
New-Item -ItemType Directory -Path .\assets -Force | Out-Null
Copy-Item .\design\codex-quota-float-ui-v2.png .\assets\hero.png -Force
Copy-Item .\design\codex-quota-float-ui-v2-compact-actual.png .\assets\widget-compact.png -Force
Copy-Item .\design\codex-quota-float-ui-v2-actual.png .\assets\widget-expanded.png -Force
```

Verify the three targets visually. Do not copy the user-provided TikTok screenshots or the fixture-only two-row screenshot. Keep the local `design` directory intact and ignored; only `assets/` is staged publicly.

- [ ] **Step 7: Run public metadata test**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\PublicRelease.Tests.ps1
```

Expected: PASS.

- [ ] **Step 8: Scan staged public files before commit**

```powershell
git add -- .gitignore LICENSE THIRD_PARTY_NOTICES.md README.md assets tests/PublicRelease.Tests.ps1
git diff --cached --check
git diff --cached --name-only
```

Expected: only the declared public files; no `design/`, cache, settings, or screenshots from the user.

- [ ] **Step 9: Commit public metadata**

```powershell
git commit -m "docs: prepare public project"
```

---

### Task 5: Add One Test Entry Point and Windows CI

**Files:**
- Create: `tests/run-tests.ps1`
- Create: `.github/workflows/test.yml`
- Modify: `tests/PublicRelease.Tests.ps1`

**Interfaces:**
- Produces: `tests/run-tests.ps1 [-Interactive]` with exit code 0 only when every selected test passes.
- CI consumes the default non-interactive mode.

- [ ] **Step 1: Extend the public-release test to require runner and workflow**

Add `tests\run-tests.ps1` and `.github\workflows\test.yml` to the required file list. Assert workflow contains `windows-latest` and `tests\run-tests.ps1`.

- [ ] **Step 2: Run the public-release test to verify failure**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\PublicRelease.Tests.ps1
```

Expected: FAIL because the runner/workflow files do not exist.

- [ ] **Step 3: Create the test runner**

Create `tests/run-tests.ps1`:

```powershell
param([switch]$Interactive)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$parseFiles = @('CodexQuotaFloat.ps1','QuotaData.psm1','Lifecycle.psm1','install.ps1','uninstall.ps1')
foreach ($relativePath in $parseFiles) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relativePath), [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "FAIL: syntax errors in $relativePath`n$($errors | Out-String)" }
}
foreach ($test in @('QuotaData.Tests.ps1','WidgetStructure.Tests.ps1','Lifecycle.Tests.ps1','Install.Tests.ps1','PublicRelease.Tests.ps1')) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "FAIL: $test exited with $LASTEXITCODE." }
}
if ($Interactive) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'WidgetClick.Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: interactive click test failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'CaptureWidget.ps1') -TwoRowFixture
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: interactive capture test failed.' }
}
Write-Host 'PASS: selected CodexQuotaFloat test suite completed.'
```

- [ ] **Step 4: Create Windows CI workflow**

Create `.github/workflows/test.yml`:

```yaml
name: tests

on:
  push:
  pull_request:

jobs:
  windows-powershell:
    runs-on: windows-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4
      - name: Run non-interactive tests
        shell: powershell
        run: .\tests\run-tests.ps1
```

- [ ] **Step 5: Run default and interactive suites**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
Import-Module .\Lifecycle.psm1 -Force
$installedScript = Join-Path $env:APPDATA 'CodexQuotaFloat\CodexQuotaFloat.ps1'
[void](Stop-CodexQuotaFloatInstance -ScriptPath $installedScript)
try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Interactive
    if ($LASTEXITCODE -ne 0) { throw 'Interactive suite failed.' }
}
finally {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
}
```

Expected: both PASS; interactive run produces current compact and expanded screenshots.

- [ ] **Step 6: Commit tests and CI**

```powershell
git add -- tests/run-tests.ps1 tests/PublicRelease.Tests.ps1 .github/workflows/test.yml
git diff --cached --check
git commit -m "ci: test Windows release"
```

---

### Task 6: Perform Final Local Release Verification and Packaging

**Files:**
- Runtime files from previous tasks.
- Create locally but ignore: `dist/codex-quota-float-v0.1.0.zip`
- Create locally but ignore: `dist/codex-quota-float-v0.1.0.zip.sha256`
- Create locally but do not commit: `dist/release-notes.md`

**Interfaces:**
- Consumes: clean committed repository and all tests.
- Produces: verified installable archive and checksum for GitHub Release.

- [ ] **Step 1: Run secret and machine-path scans**

```powershell
git grep -n -I -E '(api[_-]?key|password|secret|bearer|cookie|C:\\Users\\[^\\[:space:]]+|xwechat|last_usage\.json|settings\.json)' -- . ':(exclude).gitignore' ':(exclude)docs/superpowers/**'
```

Expected: only intentional documentation/test mentions of cache filenames; no values, credentials, personal absolute paths, or user screenshots. Inspect every match manually.

- [ ] **Step 2: Run full local verification**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Interactive
git status --short
```

Expected: PASS and a clean worktree.

- [ ] **Step 3: Install the committed version and verify live data**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
$cli = (Resolve-Path "$env:LOCALAPPDATA\Programs\CodexBar\codexbar-cli.exe").Path
$raw = & $cli usage -p codex --format json
Import-Module .\QuotaData.psm1 -Force
$live = ConvertTo-QuotaViewModel -CliJson ($raw -join [Environment]::NewLine)
$cachePath = "$env:APPDATA\CodexQuotaFloat\last_usage.json"
$deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 500
    $cache = if (Test-Path -LiteralPath $cachePath) { Get-Content $cachePath -Raw | ConvertFrom-Json } else { $null }
} until (($null -ne $cache -and $live.DisplayRemaining -eq $cache.DisplayRemaining) -or (Get-Date) -gt $deadline)
if ($null -eq $cache -or $live.DisplayRemaining -ne $cache.DisplayRemaining) { throw 'Installed cache does not match live CLI quota.' }
```

Expected: installed widget restarts, remains running, and cached remaining percentage matches live CLI output.

- [ ] **Step 4: Build deterministic install bundle**

```powershell
Remove-Item .\dist -Recurse -Force -ErrorAction SilentlyContinue
$stage = Join-Path $env:TEMP 'codex-quota-float-v0.1.0'
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stage,.\dist -Force | Out-Null
foreach ($file in @('CodexQuotaFloat.ps1','QuotaData.psm1','Lifecycle.psm1','install.ps1','uninstall.ps1','run-hidden.vbs','README.md','LICENSE','THIRD_PARTY_NOTICES.md')) {
    Copy-Item -LiteralPath $file -Destination (Join-Path $stage $file)
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath .\dist\codex-quota-float-v0.1.0.zip -CompressionLevel Optimal
$hash = (Get-FileHash .\dist\codex-quota-float-v0.1.0.zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content .\dist\codex-quota-float-v0.1.0.zip.sha256 -Value "$hash  codex-quota-float-v0.1.0.zip" -Encoding ASCII
```

Expected: archive contains exactly nine declared release files and its recomputed SHA-256 equals the sidecar value.

- [ ] **Step 5: Write exact release notes**

Create `dist/release-notes.md` with:

```markdown
## Codex Quota Float v0.1.0

首个公开预览版：为 Windows 上的 Codex 用户提供 60px 桌面额度悬浮球。

### 功能

- 剩余额度圆环与中文精简卡片
- 点击展开/收起、拖动定位、窗口置顶
- 5 小时与本周窗口按可用数据展示
- 每 60 秒刷新，失败时保留缓存并提示数据陈旧
- 自动发现 Win-CodexBar CLI、开机启动、安全更新与卸载

### 安装前要求

先安装并配置 Win-CodexBar：`winget install Finesssee.Win-CodexBar`。

这是非官方社区工具，不隶属于 OpenAI 或 Win-CodexBar。额度准确性与刷新速度受上游数据影响。
```

- [ ] **Step 6: Final local commit check**

```powershell
git status --short
git log --oneline --decorate -5
```

Expected: clean worktree because `dist/` is ignored; commits exist for design, resolver, lifecycle, public docs, and CI.

---

### Task 7: Authenticate, Create GitHub Repository, Push, and Publish v0.1.0

**Files:**
- Git remote state.
- Git tag: `v0.1.0`.
- GitHub repository and Release assets.

**Interfaces:**
- Consumes: authenticated `gh`, clean `main`, passing tests, release archive/checksum/notes.
- Produces: public repository URL and GitHub Release URL.

- [ ] **Step 0: Fast-forward the verified feature branch into local main**

Run from the original project directory, not from inside the worktree:

```powershell
$mainPath = (git rev-parse --show-toplevel).Trim()
$worktreePath = Join-Path $mainPath '.worktrees\github-release'
git -C $mainPath status --short
git -C $mainPath merge --ff-only agent/github-release
git -C $mainPath branch --show-current
```

Expected: original checkout remains on `main`, fast-forward succeeds, and `main` now points to the fully reviewed release commit. Keep the worktree until Release assets are uploaded.

- [ ] **Step 1: Verify authentication and exact account**

```powershell
gh auth status -h github.com
gh api user --jq .login
```

Expected: authenticated login is exactly `zsy1122334455-netizen`. If the token is invalid, pause and ask the user to run `gh auth login -h github.com`; do not create or push anything until this passes.

- [ ] **Step 2: Prove the target repository does not already exist**

```powershell
gh repo view zsy1122334455-netizen/codex-quota-float --json nameWithOwner,isPrivate,defaultBranchRef
```

Expected: not found. If it exists, stop and inspect it rather than overwriting history.

- [ ] **Step 3: Create the public repository and push main**

```powershell
gh repo create zsy1122334455-netizen/codex-quota-float --public --source $mainPath --remote origin --push --description "Unofficial Windows Codex quota floating widget"
git -C $mainPath remote -v
git -C $mainPath ls-remote --heads origin main
```

Expected: `origin` points to `https://github.com/zsy1122334455-netizen/codex-quota-float.git`; remote `main` resolves to the local HEAD commit.

- [ ] **Step 4: Wait for GitHub Actions**

```powershell
$run = gh run list --repo zsy1122334455-netizen/codex-quota-float --workflow test.yml --limit 1 --json databaseId,status,conclusion | ConvertFrom-Json
gh run watch $run.databaseId --repo zsy1122334455-netizen/codex-quota-float --exit-status
```

Expected: workflow conclusion `success`. If it fails, inspect logs, fix locally with a test-first change, commit, push, and wait again before releasing.

- [ ] **Step 5: Create and push v0.1.0 tag**

```powershell
git -C $mainPath tag -a v0.1.0 -m "Codex Quota Float v0.1.0"
git -C $mainPath push origin v0.1.0
```

Expected: remote annotated tag points at the verified `main` commit.

- [ ] **Step 6: Create GitHub Release with verified assets**

```powershell
gh release create v0.1.0 (Join-Path $worktreePath 'dist\codex-quota-float-v0.1.0.zip') (Join-Path $worktreePath 'dist\codex-quota-float-v0.1.0.zip.sha256') --repo zsy1122334455-netizen/codex-quota-float --title "Codex Quota Float v0.1.0" --notes-file (Join-Path $worktreePath 'dist\release-notes.md')
```

Expected: public Release contains both custom assets and GitHub source archives.

- [ ] **Step 7: Verify remote repository and Release**

```powershell
gh repo view zsy1122334455-netizen/codex-quota-float --json url,isPrivate,defaultBranchRef,licenseInfo
gh release view v0.1.0 --repo zsy1122334455-netizen/codex-quota-float --json url,tagName,isDraft,isPrerelease,assets
git -C $mainPath status --short
```

Expected: public repository, default branch `main`, MIT detected, non-draft/non-prerelease `v0.1.0`, both assets present, and clean local worktree.

- [ ] **Step 8: Remove the completed isolated worktree**

```powershell
git -C $mainPath worktree remove $worktreePath
git -C $mainPath branch -d agent/github-release
git -C $mainPath worktree list
```

Expected: only the original `main` checkout remains; the feature branch deletes because it is fully merged.

- [ ] **Step 9: Hand off URLs and defer WeChat work**

Return the repository URL, Release URL, workflow status, installed live quota verification, and any compatibility note. Do not start the WeChat article until the user requests the second phase.
