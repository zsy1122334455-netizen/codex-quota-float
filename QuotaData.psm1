Set-StrictMode -Version Latest

function Get-OptionalPropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-RemainingPercent {
    param($Window)

    $usedPercent = Get-OptionalPropertyValue -InputObject $Window -Name 'used_percent'
    if ($null -eq $usedPercent) { return $null }
    return [math]::Round([math]::Max(0, [math]::Min(100, 100 - [double]$usedPercent)))
}

function ConvertTo-QuotaViewModel {
    param([Parameter(Mandatory)][string]$CliJson)

    $items = @($CliJson | ConvertFrom-Json)
    $item = $items | Where-Object { $_.provider -eq 'codex' } | Select-Object -First 1
    if ($null -eq $item -or $null -eq $item.usage) {
        throw 'Codex usage data was not found in the CLI response.'
    }

    $usage = $item.usage
    $primaryWindow = Get-OptionalPropertyValue -InputObject $usage -Name 'primary'
    $secondaryWindow = Get-OptionalPropertyValue -InputObject $usage -Name 'secondary'
    if ($null -eq $primaryWindow -and $null -eq $secondaryWindow) {
        throw 'Codex usage response is missing a required quota window.'
    }

    $sessionWindow = $null
    $weeklyWindow = $null
    $hasWindowMetadata = $false
    foreach ($window in @($primaryWindow, $secondaryWindow)) {
        if ($null -eq $window) { continue }
        $windowMinutes = Get-OptionalPropertyValue -InputObject $window -Name 'window_minutes'
        if ($null -eq $windowMinutes) { continue }
        $hasWindowMetadata = $true
        $minutes = [double]$windowMinutes
        if ($minutes -ge 240 -and $minutes -le 360 -and $null -eq $sessionWindow) {
            $sessionWindow = $window
        }
        elseif ($minutes -ge 9000 -and $minutes -le 11000 -and $null -eq $weeklyWindow) {
            $weeklyWindow = $window
        }
    }

    # Older CodexBar responses did not include window_minutes. Preserve their
    # positional meaning only when no duration metadata exists at all.
    if (-not $hasWindowMetadata) {
        $sessionWindow = $primaryWindow
        $weeklyWindow = $secondaryWindow
    }

    $primaryRemaining = Get-RemainingPercent -Window $sessionWindow
    $weeklyRemaining = Get-RemainingPercent -Window $weeklyWindow
    if ($null -eq $primaryRemaining -and $null -eq $weeklyRemaining) {
        throw 'Codex usage response did not include a recognized quota window.'
    }

    $primaryReset = Get-OptionalPropertyValue -InputObject $sessionWindow -Name 'reset_description'
    $weeklyReset = Get-OptionalPropertyValue -InputObject $weeklyWindow -Name 'reset_description'
    $displayRemaining = if ($null -ne $primaryRemaining) { $primaryRemaining } else { $weeklyRemaining }

    [pscustomobject]@{
        SchemaVersion    = 2
        Plan             = [string](Get-OptionalPropertyValue -InputObject $usage -Name 'login_method')
        HasPrimary       = $null -ne $primaryRemaining
        PrimaryRemaining = $primaryRemaining
        PrimaryReset     = [string]$primaryReset
        HasWeekly        = $null -ne $weeklyRemaining
        WeeklyRemaining  = $weeklyRemaining
        WeeklyReset      = [string]$weeklyReset
        DisplayRemaining = $displayRemaining
        UpdatedAt        = [string](Get-OptionalPropertyValue -InputObject $usage -Name 'updated_at')
    }
}

function Get-QuotaColor {
    param([Parameter(Mandatory)][int]$Remaining)

    if ($Remaining -lt 10) { return '#F26B5E' }
    if ($Remaining -lt 50) { return '#E4A11B' }
    return '#4169E1'
}

function Save-CachedQuotaViewModel {
    param(
        [Parameter(Mandatory)]$Model,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $Model | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8
}

function Get-CachedQuotaViewModel {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $model = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $schemaVersion = Get-OptionalPropertyValue -InputObject $model -Name 'SchemaVersion'
    if ($schemaVersion -ne 2) { return $null }
    return $model
}

function ConvertFrom-CodePoints {
    param([Parameter(Mandatory)][int[]]$CodePoints)
    return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

function Get-QuotaText {
    param([Parameter(Mandatory)][ValidateSet('Remaining','Primary','Weekly','ResetSuffix','Updated','Stale','Refresh','StartAtLogin','OpenDetails','Exit','LoginExpired','CliMissing')][string]$Key)

    switch ($Key) {
        'Remaining'    { return ConvertFrom-CodePoints @(21097,20313) }
        'Primary'      { return ConvertFrom-CodePoints @(53,32,23567,26102,21097,20313) }
        'Weekly'       { return ConvertFrom-CodePoints @(26412,21608,21097,20313) }
        'ResetSuffix'  { return ConvertFrom-CodePoints @(21518,37325,32622) }
        'Updated'      { return ConvertFrom-CodePoints @(21018,21018,26356,26032) }
        'Stale'        { return ConvertFrom-CodePoints @(25968,25454,26242,26410,26356,26032) }
        'Refresh'      { return ConvertFrom-CodePoints @(31435,21363,21047,26032) }
        'StartAtLogin' { return ConvertFrom-CodePoints @(24320,26426,21551,21160) }
        'OpenDetails'  { return ConvertFrom-CodePoints @(25171,24320,23436,25972,32479,35745) }
        'Exit'         { return ConvertFrom-CodePoints @(36864,20986) }
        'LoginExpired' { return ConvertFrom-CodePoints @(67,111,100,101,120,32,30331,24405,24405,24050,22833,25928,65292,35831,37325,26032,30331,24405) }
        'CliMissing'   { return ConvertFrom-CodePoints @(26410,25214,21040,67,111,100,101,120,66,97,114,32,24037,20855) }
    }
}

function Get-VisibleWindowPosition {
    param(
        [Parameter(Mandatory)][double]$Left,
        [Parameter(Mandatory)][double]$Top,
        [Parameter(Mandatory)][double]$Width,
        [Parameter(Mandatory)][double]$Height,
        [Parameter(Mandatory)][double]$WorkLeft,
        [Parameter(Mandatory)][double]$WorkTop,
        [Parameter(Mandatory)][double]$WorkRight,
        [Parameter(Mandatory)][double]$WorkBottom
    )

    $maximumLeft = [math]::Max($WorkLeft, $WorkRight - $Width)
    $maximumTop = [math]::Max($WorkTop, $WorkBottom - $Height)
    [pscustomobject]@{
        Left = [math]::Max($WorkLeft, [math]::Min($Left, $maximumLeft))
        Top  = [math]::Max($WorkTop, [math]::Min($Top, $maximumTop))
    }
}

function Get-ExpandedWidgetHeight {
    param([Parameter(Mandatory)][ValidateRange(0, 3)][int]$VisibleRowCount)

    if ($VisibleRowCount -le 1) { return 140 }
    return 210
}

function Get-ProgressArcMetrics {
    param(
        [Parameter(Mandatory)][double]$Percent,
        [Parameter(Mandatory)][double]$Diameter,
        [Parameter(Mandatory)][double]$StrokeThickness
    )

    $value = [math]::Max(0, [math]::Min(99.999, $Percent))
    $radius = ($Diameter - $StrokeThickness) / 2
    $center = $Diameter / 2
    $endRadians = (-90 + ($value * 3.6)) * [math]::PI / 180
    [pscustomobject]@{
        StartX    = $center
        StartY    = $center - $radius
        EndX      = $center + ($radius * [math]::Cos($endRadians))
        EndY      = $center + ($radius * [math]::Sin($endRadians))
        Radius    = $radius
        IsLargeArc = $value -gt 50
    }
}

function Format-QuotaResetText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '--' }
    $days = 0; $hours = 0; $minutes = 0
    if ($Raw -match '(\d+)d') { $days = [int]$matches[1] }
    if ($Raw -match '(\d+)h') { $hours = [int]$matches[1] }
    if ($Raw -match '(\d+)m') { $minutes = [int]$matches[1] }

    $dayLabel = ConvertFrom-CodePoints @(22825)
    $hourLabel = ConvertFrom-CodePoints @(23567,26102)
    $minuteLabel = ConvertFrom-CodePoints @(20998)
    $parts = New-Object System.Collections.Generic.List[string]
    if ($days -gt 0) { [void]$parts.Add("$days$dayLabel") }
    if ($hours -gt 0) { [void]$parts.Add("$hours$hourLabel") }
    if ($minutes -gt 0) { [void]$parts.Add("$minutes$minuteLabel") }
    if ($parts.Count -eq 0) { return $Raw }
    return (($parts -join '') + (Get-QuotaText -Key 'ResetSuffix'))
}

Export-ModuleMember -Function ConvertTo-QuotaViewModel, Get-QuotaColor, Save-CachedQuotaViewModel, Get-CachedQuotaViewModel, Get-QuotaText, Get-VisibleWindowPosition, Get-ExpandedWidgetHeight, Get-ProgressArcMetrics, Format-QuotaResetText
