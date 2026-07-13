param([switch]$RegisterOnly)

$ErrorActionPreference = 'Stop'
$sourceDirectory = $PSScriptRoot
$targetDirectory = Join-Path $env:APPDATA 'CodexQuotaFloat'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
foreach ($file in @('CodexQuotaFloat.ps1', 'QuotaData.psm1', 'run-hidden.vbs', 'install.ps1')) {
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $file) -Destination (Join-Path $targetDirectory $file) -Force
}

$launcher = Join-Path $targetDirectory 'run-hidden.vbs'
Set-ItemProperty -Path $runPath -Name 'CodexQuotaFloat' -Value ('wscript.exe "' + $launcher + '"')

if (-not $RegisterOnly) {
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $launcher + '"')
}

Write-Host 'CodexQuotaFloat installation completed.'
