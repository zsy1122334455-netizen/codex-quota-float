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

$testRoot = Join-Path $env:TEMP ('CodexQuotaFloat-lifecycle-' + [guid]::NewGuid().ToString('N'))
$targetScript = Join-Path $testRoot 'target.ps1'
$controlScript = Join-Path $testRoot 'control.ps1'
$targetProcess = $null
$controlProcess = $null
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Set-Content -LiteralPath $targetScript -Value 'Start-Sleep -Seconds 30'
    Set-Content -LiteralPath $controlScript -Value 'Start-Sleep -Seconds 30'
    $targetProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-File',('"' + $targetScript + '"')) -WindowStyle Hidden -PassThru
    $controlProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-File',('"' + $controlScript + '"')) -WindowStyle Hidden -PassThru

    $stopped = @(Stop-CodexQuotaFloatInstance -ScriptPath $targetScript)
    if (-not $targetProcess.WaitForExit(5000)) { throw 'FAIL: matching TEMP process was not stopped.' }
    $controlProcess.Refresh()
    if ($controlProcess.HasExited) { throw 'FAIL: non-matching TEMP control process was stopped.' }
    if ($targetProcess.Id -notin $stopped) { throw 'FAIL: stopped PID list omitted the matching TEMP process.' }
    if ($controlProcess.Id -in $stopped) { throw 'FAIL: stopped PID list included the TEMP control process.' }
}
finally {
    foreach ($process in @($targetProcess, $controlProcess)) {
        if ($null -eq $process) { continue }
        $process.Refresh()
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: lifecycle process matching and TEMP instance stopping are exact.'
