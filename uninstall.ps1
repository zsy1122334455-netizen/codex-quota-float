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
