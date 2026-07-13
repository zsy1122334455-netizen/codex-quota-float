$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'install.ps1'
$uninstaller = Join-Path $root 'uninstall.ps1'
$target = Join-Path $env:TEMP ('CodexQuotaFloat-install-' + [guid]::NewGuid().ToString('N'))
$runName = 'CodexQuotaFloatTest-' + [guid]::NewGuid().ToString('N')
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallLogId = [guid]::NewGuid().ToString('N')
$uninstallStdout = Join-Path $env:TEMP ('CodexQuotaFloat-uninstall-' + $uninstallLogId + '.out.log')
$uninstallStderr = Join-Path $env:TEMP ('CodexQuotaFloat-uninstall-' + $uninstallLogId + '.err.log')
$uninstallProcess = $null
$cleanupScript = $null

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
    $installedUninstaller = Join-Path $target 'uninstall.ps1'
    $uninstallProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"' + $installedUninstaller + '"'),
        '-TargetDirectory',
        ('"' + $target + '"'),
        '-RunValueName',
        $runName
    ) -WorkingDirectory $target -WindowStyle Hidden -RedirectStandardOutput $uninstallStdout -RedirectStandardError $uninstallStderr -PassThru
    $cleanupScript = Join-Path $env:TEMP ("CodexQuotaFloat-uninstall-cleanup-$($uninstallProcess.Id).ps1")
    if (-not $uninstallProcess.WaitForExit(10000)) { throw 'FAIL: installed uninstaller did not exit.' }
    $uninstallProcess.WaitForExit()
    $uninstallProcess.Refresh()
    for ($attempt = 0; $attempt -lt 100 -and (Test-Path -LiteralPath $target); $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    if (Test-Path -LiteralPath $target) {
        $details = Get-Content -LiteralPath $uninstallStderr -Raw -ErrorAction SilentlyContinue
        throw "FAIL: installed uninstaller left the target directory behind. $details"
    }
    if ($null -ne (Get-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue)) { throw 'FAIL: uninstall left the startup value behind.' }
    for ($attempt = 0; $attempt -lt 100 -and (Test-Path -LiteralPath $cleanupScript); $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    if (Test-Path -LiteralPath $cleanupScript) { throw 'FAIL: uninstall cleanup script did not remove itself.' }

    & $installer -TargetDirectory $target -RunValueName $runName -NoLaunch
    & $uninstaller -TargetDirectory $target -RunValueName $runName
    if (Test-Path -LiteralPath $target) { throw 'FAIL: source uninstaller did not synchronously remove the target directory.' }
    if ($null -ne (Get-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue)) { throw 'FAIL: source uninstaller left the startup value behind.' }
}
finally {
    if ($null -ne $uninstallProcess) {
        $uninstallProcess.Refresh()
        if (-not $uninstallProcess.HasExited) { Stop-Process -Id $uninstallProcess.Id -Force }
    }
    Remove-ItemProperty -Path $runPath -Name $runName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $uninstallStdout,$uninstallStderr -Force -ErrorAction SilentlyContinue
    if ($null -ne $cleanupScript) { Remove-Item -LiteralPath $cleanupScript -Force -ErrorAction SilentlyContinue }
}
Write-Host 'PASS: isolated install and uninstall lifecycle works.'
