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
