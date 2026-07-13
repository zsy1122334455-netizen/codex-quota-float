Set-StrictMode -Version Latest

function Test-ProcessCommandTargetsScript {
    param(
        [AllowNull()][string]$CommandLine,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($ScriptPath)
    $pattern = '(?i)(?:^|\s)-File\s+(?:"' + [regex]::Escape($fullPath) + '"|' + [regex]::Escape($fullPath) + ')(?:\s|$)'
    return [bool]($CommandLine -match $pattern)
}

function Stop-CodexQuotaFloatInstance {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $stopped = New-Object System.Collections.Generic.List[int]
    $processes = Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('powershell.exe', 'pwsh.exe') }
    foreach ($process in $processes) {
        if (-not (Test-ProcessCommandTargetsScript -CommandLine $process.CommandLine -ScriptPath $ScriptPath)) { continue }
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        [void]$stopped.Add([int]$process.ProcessId)
    }
    return @($stopped)
}

Export-ModuleMember -Function Test-ProcessCommandTargetsScript, Stop-CodexQuotaFloatInstance
