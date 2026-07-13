$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Actual -ne $Expected) {
        throw "FAIL: $Name. Expected '$Expected', got '$Actual'."
    }
}

$modulePath = Join-Path $PSScriptRoot '..\QuotaData.psm1'
Import-Module $modulePath -Force

if (-not (Get-Command ConvertTo-QuotaViewModel -ErrorAction SilentlyContinue)) {
    throw 'FAIL: ConvertTo-QuotaViewModel is not defined.'
}

$fixture = @'
[
  {
    "provider": "codex",
    "usage": {
      "login_method": "ChatGPT Pro",
      "primary": {
        "used_percent": 34.0,
        "reset_description": "3h 14m"
      },
      "secondary": {
        "used_percent": 5.0,
        "reset_description": "6d 22h"
      },
      "updated_at": "2026-07-11T02:08:42Z"
    }
  }
]
'@

$model = ConvertTo-QuotaViewModel -CliJson $fixture
Assert-Equal -Actual $model.Plan -Expected 'ChatGPT Pro' -Name 'plan name'
Assert-Equal -Actual $model.PrimaryRemaining -Expected 66 -Name 'primary remaining percentage'
Assert-Equal -Actual $model.PrimaryReset -Expected '3h 14m' -Name 'primary reset time'
Assert-Equal -Actual $model.WeeklyRemaining -Expected 95 -Name 'weekly remaining percentage'
Assert-Equal -Actual $model.WeeklyReset -Expected '6d 22h' -Name 'weekly reset time'

$weeklyOnlyFixture = @'
[
  {
    "provider": "codex",
    "usage": {
      "login_method": "ChatGPT Pro",
      "primary": {
        "used_percent": 18.0,
        "reset_description": "6d 11h",
        "window_minutes": 10080
      },
      "secondary": {
        "used_percent": 0.0,
        "reset_description": ""
      },
      "extra_rate_windows": [
        {
          "id": "codex-spark-weekly",
          "window": {
            "used_percent": 0.0,
            "window_minutes": 10080
          }
        }
      ],
      "updated_at": "2026-07-13T10:37:35Z"
    }
  }
]
'@

$weeklyOnlyModel = ConvertTo-QuotaViewModel -CliJson $weeklyOnlyFixture
Assert-Equal -Actual $weeklyOnlyModel.HasPrimary -Expected $false -Name 'weekly-only payload has no 5-hour window'
Assert-Equal -Actual $weeklyOnlyModel.PrimaryRemaining -Expected $null -Name 'weekly-only payload does not invent 5-hour remaining'
Assert-Equal -Actual $weeklyOnlyModel.HasWeekly -Expected $true -Name 'weekly-only payload has a weekly window'
Assert-Equal -Actual $weeklyOnlyModel.WeeklyRemaining -Expected 82 -Name 'weekly-only payload maps 7-day window by duration'
Assert-Equal -Actual $weeklyOnlyModel.WeeklyReset -Expected '6d 11h' -Name 'weekly-only reset time'
Assert-Equal -Actual $weeklyOnlyModel.DisplayRemaining -Expected 82 -Name 'floating ball falls back to weekly remaining'

if (-not (Get-Command Get-QuotaColor -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Get-QuotaColor is not defined.'
}

Assert-Equal -Actual (Get-QuotaColor -Remaining 51) -Expected '#4169E1' -Name 'V2 healthy quota color'
Assert-Equal -Actual (Get-QuotaColor -Remaining 49) -Expected '#E4A11B' -Name 'warning quota color'
Assert-Equal -Actual (Get-QuotaColor -Remaining 9) -Expected '#F26B5E' -Name 'critical quota color'

if (-not (Get-Command Save-CachedQuotaViewModel -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Save-CachedQuotaViewModel is not defined.'
}
if (-not (Get-Command Get-CachedQuotaViewModel -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Get-CachedQuotaViewModel is not defined.'
}

$cachePath = Join-Path $env:TEMP 'CodexQuotaFloat-test-cache.json'
Remove-Item $cachePath -Force -ErrorAction SilentlyContinue
Save-CachedQuotaViewModel -Model $model -Path $cachePath
$cached = Get-CachedQuotaViewModel -Path $cachePath
Assert-Equal -Actual $cached.PrimaryRemaining -Expected 66 -Name 'cached primary remaining percentage'
Assert-Equal -Actual $cached.WeeklyRemaining -Expected 95 -Name 'cached weekly remaining percentage'
Remove-Item $cachePath -Force -ErrorAction SilentlyContinue

$legacyCachePath = Join-Path $env:TEMP 'CodexQuotaFloat-test-legacy-cache.json'
@{
    Plan = 'ChatGPT Pro'
    PrimaryRemaining = 0
    WeeklyRemaining = 42
} | ConvertTo-Json | Set-Content -Path $legacyCachePath -Encoding UTF8
$legacyCached = Get-CachedQuotaViewModel -Path $legacyCachePath
Assert-Equal -Actual $legacyCached -Expected $null -Name 'legacy positional cache is rejected'
Remove-Item $legacyCachePath -Force -ErrorAction SilentlyContinue

if (-not (Get-Command Get-QuotaText -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Get-QuotaText is not defined.'
}

$remainingCodePoints = @((Get-QuotaText -Key 'Remaining').ToCharArray() | ForEach-Object { [int][char]$_ }) -join ','
Assert-Equal -Actual $remainingCodePoints -Expected '21097,20313' -Name 'Chinese remaining label'

if (-not (Get-Command Get-VisibleWindowPosition -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Get-VisibleWindowPosition is not defined.'
}

$clamped = Get-VisibleWindowPosition -Left 1606.67 -Top 898.67 -Width 280 -Height 190 -WorkLeft 0 -WorkTop 0 -WorkRight 1706.67 -WorkBottom 1018.67
Assert-Equal -Actual ([math]::Round($clamped.Left, 2)) -Expected 1426.67 -Name 'expanded window right-edge clamp'
Assert-Equal -Actual ([math]::Round($clamped.Top, 2)) -Expected 828.67 -Name 'expanded window bottom-edge clamp'

$unchanged = Get-VisibleWindowPosition -Left 300 -Top 200 -Width 280 -Height 190 -WorkLeft 0 -WorkTop 0 -WorkRight 1706.67 -WorkBottom 1018.67
Assert-Equal -Actual $unchanged.Left -Expected 300 -Name 'visible window horizontal position'
Assert-Equal -Actual $unchanged.Top -Expected 200 -Name 'visible window vertical position'

if (-not (Get-Command Get-ExpandedWidgetHeight -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Get-ExpandedWidgetHeight is not defined.'
}
Assert-Equal -Actual (Get-ExpandedWidgetHeight -VisibleRowCount 1) -Expected 140 -Name 'single quota row uses compact expanded height'
Assert-Equal -Actual (Get-ExpandedWidgetHeight -VisibleRowCount 2) -Expected 210 -Name 'two quota rows use V2 expanded height'

if (-not (Get-Command Get-ProgressArcMetrics -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Get-ProgressArcMetrics is not defined.'
}
$arc = Get-ProgressArcMetrics -Percent 82 -Diameter 48 -StrokeThickness 4
Assert-Equal -Actual ([math]::Round($arc.StartX, 2)) -Expected 24 -Name 'ring start x'
Assert-Equal -Actual ([math]::Round($arc.StartY, 2)) -Expected 2 -Name 'ring start y'
Assert-Equal -Actual ([math]::Round($arc.EndX, 2)) -Expected 4.09 -Name '82 percent ring end x'
Assert-Equal -Actual ([math]::Round($arc.EndY, 2)) -Expected 14.63 -Name '82 percent ring end y'
Assert-Equal -Actual $arc.Radius -Expected 22 -Name 'ring radius'
Assert-Equal -Actual $arc.IsLargeArc -Expected $true -Name '82 percent uses a large arc'
$halfArc = Get-ProgressArcMetrics -Percent 50 -Diameter 48 -StrokeThickness 4
Assert-Equal -Actual ([math]::Round($halfArc.EndX, 2)) -Expected 24 -Name '50 percent ring end x'
Assert-Equal -Actual ([math]::Round($halfArc.EndY, 2)) -Expected 46 -Name '50 percent ring end y'
Assert-Equal -Actual $halfArc.IsLargeArc -Expected $false -Name '50 percent does not use a large arc'
$zeroArc = Get-ProgressArcMetrics -Percent 0 -Diameter 48 -StrokeThickness 4
Assert-Equal -Actual ([math]::Round($zeroArc.EndY, 2)) -Expected 2 -Name 'zero percent ring ends at the start point'
$fullArc = Get-ProgressArcMetrics -Percent 100 -Diameter 48 -StrokeThickness 4
Assert-Equal -Actual $fullArc.IsLargeArc -Expected $true -Name '100 percent metrics use the full-ring path branch'

if (-not (Get-Command Format-QuotaResetText -ErrorAction SilentlyContinue)) {
    throw 'FAIL: Format-QuotaResetText is not defined.'
}
$expectedCompactReset = -join (@(54,22825,49,48,23567,26102,21518,37325,32622) | ForEach-Object { [char]$_ })
Assert-Equal -Actual (Format-QuotaResetText -Raw '6d 10h') -Expected $expectedCompactReset -Name 'compact Chinese reset text'
Assert-Equal -Actual (Format-QuotaResetText -Raw '') -Expected '--' -Name 'empty reset text fallback'

foreach ($commandName in @('Resolve-CodexBarCliPath', 'Resolve-CodexBarAppPath')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "FAIL: $commandName is not defined."
    }
}

$resolverRoot = Join-Path $env:TEMP ('CodexQuotaFloat-resolver-' + [guid]::NewGuid().ToString('N'))
$defaultDirectory = Join-Path $resolverRoot 'Programs\CodexBar'
New-Item -ItemType Directory -Path $defaultDirectory -Force | Out-Null
try {
    $configuredCli = Join-Path $resolverRoot 'custom-codexbar-cli.exe'
    Set-Content -LiteralPath $configuredCli -Value ''
    Assert-Equal -Actual (Resolve-CodexBarCliPath -ConfiguredPath $configuredCli -LocalAppData $resolverRoot) -Expected $configuredCli -Name 'configured CLI path wins'

    $defaultCli = Join-Path $defaultDirectory 'codexbar-cli.exe'
    Set-Content -LiteralPath $defaultCli -Value ''
    Assert-Equal -Actual (Resolve-CodexBarCliPath -ConfiguredPath '' -LocalAppData $resolverRoot) -Expected $defaultCli -Name 'default CLI install path'

    $defaultApp = Join-Path $defaultDirectory 'codexbar.exe'
    Set-Content -LiteralPath $defaultApp -Value ''
    Assert-Equal -Actual (Resolve-CodexBarAppPath -ConfiguredPath '' -LocalAppData $resolverRoot) -Expected $defaultApp -Name 'default app install path'

    Remove-Item -LiteralPath $defaultCli,$defaultApp -Force
    Assert-Equal -Actual (Resolve-CodexBarCliPath -ConfiguredPath '' -LocalAppData $resolverRoot) -Expected $null -Name 'missing CLI returns null'
}
finally {
    Remove-Item -LiteralPath $resolverRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: usage parsing and remaining percentage conversion.'
