Set-StrictMode -Version Latest

function Split-CommandLineTokens {
    param([Parameter(Mandatory)][string]$CommandLine)
    $tokens = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $insideQuotes = $false
    $tokenStarted = $false

    foreach ($character in $CommandLine.ToCharArray()) {
        if ($character -eq '"') {
            $insideQuotes = -not $insideQuotes
            $tokenStarted = $true
            continue
        }
        if (-not $insideQuotes -and [char]::IsWhiteSpace($character)) {
            if ($tokenStarted) {
                [void]$tokens.Add($current.ToString())
                [void]$current.Clear()
                $tokenStarted = $false
            }
            continue
        }
        [void]$current.Append($character)
        $tokenStarted = $true
    }
    if ($tokenStarted) { [void]$tokens.Add($current.ToString()) }
    return @($tokens)
}

function Test-ProcessCommandTargetsScript {
    param(
        [AllowNull()][string]$CommandLine,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($ScriptPath)
    $tokens = @(Split-CommandLineTokens -CommandLine $CommandLine)
    $commandParameterNames = @('Command', 'EncodedCommand', 'CommandWithArgs', 'EncodedArguments')
    for ($index = 1; $index -lt $tokens.Count; $index++) {
        $token = $tokens[$index]
        if ($token.Length -gt 1 -and ($token.StartsWith('-') -or $token.StartsWith('/'))) {
            $parameterName = $token.Substring(1)
            if ([string]::Equals($parameterName, 'ec', [StringComparison]::OrdinalIgnoreCase)) { return $false }
            foreach ($commandParameterName in $commandParameterNames) {
                if ($commandParameterName.StartsWith($parameterName, [StringComparison]::OrdinalIgnoreCase)) { return $false }
            }
        }
        if ($token -notin @('-File', '-f')) { continue }
        if ($index + 1 -ge $tokens.Count) { return $false }
        try {
            $candidatePath = [IO.Path]::GetFullPath($tokens[$index + 1])
        }
        catch {
            return $false
        }
        return [string]::Equals($candidatePath, $fullPath, [StringComparison]::OrdinalIgnoreCase)
    }
    return $false
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
