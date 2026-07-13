$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'install.ps1'
$uninstaller = Join-Path $root 'uninstall.ps1'
$target = Join-Path $env:TEMP ('CodexQuotaFloat-install-' + [guid]::NewGuid().ToString('N'))
$runName = 'CodexQuotaFloatTest-' + [guid]::NewGuid().ToString('N')
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

# Preflight the isolation contract before invoking the installer. PowerShell leaves
# unknown script parameters in $args, which would let the legacy installer touch
# the live APPDATA target despite this test passing TEMP arguments.
$installerParameters = (Get-Command -Name $installer -ErrorAction Stop).Parameters.Keys
foreach ($requiredParameter in @('TargetDirectory', 'RunValueName', 'NoLaunch')) {
    if ($requiredParameter -notin $installerParameters) {
        throw "FAIL: installer is missing isolation parameter -$requiredParameter."
    }
}
if (-not (Test-Path -LiteralPath $uninstaller)) { throw 'FAIL: uninstall.ps1 is missing.' }

try {
    & $installer -TargetDirectory $target -RunValueName $runName -NoLaunch
    foreach ($file in @('CodexQuotaFloat.ps1','QuotaData.psm1','Lifecycle.psm1','run-hidden.vbs','install.ps1','uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $target $file))) { throw "FAIL: installer did not copy $file." }
    }
    $value = (Get-ItemProperty -Path $runPath -Name $runName -ErrorAction Stop).$runName
    if ($value -notmatch [regex]::Escape((Join-Path $target 'run-hidden.vbs'))) { throw 'FAIL: isolated startup value is incorrect.' }

    Set-Content -LiteralPath (Join-Path $target 'last_usage.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $target 'settings.json') -Value '{}'
    & $uninstaller -TargetDirectory $target -RunValueName $runName
    if (Test-Path -LiteralPath $target) { throw 'FAIL: uninstall left the target directory behind.' }
    if ($null -ne (Get-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue)) { throw 'FAIL: uninstall left the startup value behind.' }
}
finally {
    Remove-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'PASS: isolated install and uninstall lifecycle works.'
