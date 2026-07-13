param([switch]$ExpectRegistered)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'install.ps1'
$launcher = Join-Path $root 'run-hidden.vbs'

if (-not (Test-Path -LiteralPath $installer)) { throw 'FAIL: install.ps1 is not defined.' }
if (-not (Test-Path -LiteralPath $launcher)) { throw 'FAIL: run-hidden.vbs is not defined.' }

if ($ExpectRegistered) {
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $value = (Get-ItemProperty -Path $runPath -ErrorAction Stop).CodexQuotaFloat
    if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch 'run-hidden.vbs') {
        throw 'FAIL: CodexQuotaFloat auto-start registration is missing.'
    }
}

Write-Host 'PASS: installer files and requested registration state are valid.'
