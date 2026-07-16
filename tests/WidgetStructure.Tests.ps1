$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexQuotaFloat.ps1'
$source = Get-Content -LiteralPath $scriptPath -Raw
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'QuotaData.psm1'
$moduleSource = Get-Content -LiteralPath $modulePath -Raw

if ($source -match '\$root\.Child\s*=') {
    throw 'FAIL: the WPF Grid root must use its Children collection, not Child.'
}

if ($source -notmatch '\$root\.Children\.Add\(\$card\)') {
    throw 'FAIL: the WPF Grid root must add the card through Children.Add.'
}

if ($source -match '\[System\.Windows\.Controls\.Panel\]\$Host') {
    throw 'FAIL: Add-Row must not bind a parameter named Host because $Host is read-only.'
}

if ($source -notmatch 'Get-VisibleWindowPosition') {
    throw 'FAIL: expanded widget must clamp its position to the visible work area.'
}

if ($source -notmatch '\$script:model\.DisplayRemaining') {
    throw 'FAIL: the floating ball must use weekly quota remaining.'
}

if ($source -match 'HasPrimary|PrimaryRemaining|Get-QuotaText\s+-Key\s+''Primary''') {
    throw 'FAIL: the weekly-only widget must not render a 5-hour quota row.'
}

if ($source -notmatch 'if \(\$script:model\.HasWeekly\)') {
    throw 'FAIL: the expanded widget must render the weekly row only when it exists.'
}

if ($source -notmatch '\$window\.Add_MouseLeftButtonUp' -or $source -notmatch '\$script:expanded\s*=\s*-not\s+\$script:expanded') {
    throw 'FAIL: a click must toggle the weekly quota card between compact and expanded states.'
}

if ($source -notmatch '\$window\.Width\s*=\s*250;\s*\$window\.Height\s*=\s*\$expandedHeight') {
    throw 'FAIL: the expanded weekly quota card must apply its 250-pixel width and calculated height.'
}

if ($source -notmatch '\$window\.Width\s*=\s*60;\s*\$window\.Height\s*=\s*60') {
    throw 'FAIL: V2 compact window must be 60 x 60.'
}

if ($source -notmatch '\$window\.Width\s*=\s*250') {
    throw 'FAIL: V2 expanded card must be 250 pixels wide.'
}

if ($source -notmatch 'Get-ProgressArcMetrics') {
    throw 'FAIL: V2 collapsed widget must render a quota progress arc.'
}

if ($source -notmatch 'System\.Windows\.Shapes\.Ellipse') {
    throw 'FAIL: V2 widget must use ellipse shapes for the ring track and freshness dot.'
}

if ($source -match "Get-QuotaText\s+-Key\s+'Remaining'") {
    throw 'FAIL: V2 compact orb must not show the old remaining caption.'
}

if ($source -notmatch 'Format-QuotaResetText') {
    throw 'FAIL: V2 card must use compact reset text.'
}

foreach ($token in @('#4169E1', '#DDE6F7', '#4FC28B', 'Bahnschrift', 'Microsoft YaHei UI')) {
    if (($source + $moduleSource) -notmatch [regex]::Escape($token)) {
        throw "FAIL: V2 visual token '$token' is missing."
    }
}

if ($source -match '\$status\s*=\s*New-TextBlock') {
    throw 'FAIL: V2 card must encode freshness in the header dot, not a bottom status line.'
}

$deactivatedHandler = [regex]::Match($source, '(?s)\$window\.Add_Deactivated\(\{(?<body>.*?)\}\)')
if ($deactivatedHandler.Success -and $deactivatedHandler.Groups['body'].Value -match '\$script:expanded') {
    throw 'FAIL: deactivation must not collapse or expand the weekly quota card.'
}

if ($source -notmatch '\$cliPath\s*=\s*Resolve-CodexBarCliPath') {
    throw 'FAIL: widget must resolve the CodexBar CLI path.'
}
if ($source -notmatch '\$codexBarPath\s*=\s*Resolve-CodexBarAppPath') {
    throw 'FAIL: widget must resolve the CodexBar app path.'
}

foreach ($interactionPattern in @(
    '\$window\.Topmost\s*=\s*\$true',
    'CodexQuotaFloatNative',
    'SetWindowPos',
    'Test-WidgetTopmost',
    'Restore-WidgetTopmost',
    '\$window\.Add_SourceInitialized',
    '\$window\.Add_Deactivated',
    '\$window\.Add_MouseMove',
    '\$window\.DragMove\(\)',
    '\$window\.ContextMenu\s*=\s*\$menu',
    '\$window\.Add_LocationChanged',
    'TotalSeconds\s+-ge\s+5',
    'TotalSeconds\s+-ge\s+60',
    'usage -p codex --format json'
)) {
    if ($source -notmatch $interactionPattern) {
        throw "FAIL: preserved interaction/refresh hook '$interactionPattern' is missing."
    }
}

if ($source -notmatch '\$window\.UseLayoutRounding\s*=\s*\$true' -or $source -notmatch '\$window\.SnapsToDevicePixels\s*=\s*\$true') {
    throw 'FAIL: V2 window must enable layout rounding and device-pixel snapping.'
}

Write-Host 'PASS: root Grid uses the WPF Children collection.'
