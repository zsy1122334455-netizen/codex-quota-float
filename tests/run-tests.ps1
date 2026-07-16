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
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'CaptureWidget.ps1') -WeeklyFixture
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: interactive capture test failed.' }
}
Write-Host 'PASS: selected CodexQuotaFloat test suite completed.'
