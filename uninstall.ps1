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

    $targetRoot = $fullTarget.TrimEnd('\')
    $targetPrefix = $targetRoot + '\'
    $scriptRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    $workingDirectory = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
    $scriptIsInsideTarget = [string]::Equals($scriptRoot, $targetRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $scriptRoot.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)
    $workingDirectoryIsInsideTarget = [string]::Equals($workingDirectory, $targetRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $workingDirectory.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)

    if ($scriptIsInsideTarget -or $workingDirectoryIsInsideTarget) {
        $cleanupPath = Join-Path $env:TEMP ("CodexQuotaFloat-uninstall-cleanup-$PID.ps1")
        $cleanupSource = @'
param([Parameter(Mandatory)][string]$TargetDirectory)
$ErrorActionPreference = 'Stop'
try {
    $fullTarget = [IO.Path]::GetFullPath($TargetDirectory)
    $appDataPrefix = [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\') + '\'
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not ($fullTarget.StartsWith($appDataPrefix, [StringComparison]::OrdinalIgnoreCase) -or $fullTarget.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to remove a target outside APPDATA or TEMP: $fullTarget"
    }
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        if (-not (Test-Path -LiteralPath $fullTarget)) { break }
        try {
            Remove-Item -LiteralPath $fullTarget -Recurse -Force -ErrorAction Stop
            break
        }
        catch {
            if ($attempt -eq 99) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
    if (Test-Path -LiteralPath $fullTarget) { throw "Failed to remove target: $fullTarget" }
}
finally {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
'@
        Set-Content -LiteralPath $cleanupPath -Value $cleanupSource -Encoding UTF8
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-WindowStyle',
            'Hidden',
            '-File',
            ('"' + $cleanupPath + '"'),
            '-TargetDirectory',
            ('"' + $fullTarget + '"')
        ) -WorkingDirectory $env:TEMP -WindowStyle Hidden | Out-Null
        Write-Host 'CodexQuotaFloat uninstall cleanup scheduled.'
        return
    }

    Remove-Item -LiteralPath $fullTarget -Recurse -Force
}
Write-Host 'CodexQuotaFloat uninstall completed.'
