$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($file in @('.gitignore','LICENSE','THIRD_PARTY_NOTICES.md','README.md','assets\hero.png','assets\widget-compact.png','assets\widget-expanded.png','tests\run-tests.ps1','.github\workflows\test.yml')) {
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
$workflow = [IO.File]::ReadAllText((Join-Path $root '.github\workflows\test.yml'), [Text.Encoding]::UTF8)
if ($workflow -notmatch 'windows-latest' -or $workflow -notlike '*run-tests.ps1*') { throw 'FAIL: Windows CI workflow is incomplete.' }
Write-Host 'PASS: public release metadata is complete.'





