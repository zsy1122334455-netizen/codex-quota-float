$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Import-Module (Join-Path $PSScriptRoot 'QuotaData.psm1') -Force

$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\CodexQuotaFloat', [ref]$mutexCreated)
if (-not $mutexCreated) { exit 0 }

$appDirectory = Join-Path $env:APPDATA 'CodexQuotaFloat'
$settingsPath = Join-Path $appDirectory 'settings.json'
$cachePath = Join-Path $appDirectory 'last_usage.json'
$cliPath = Resolve-CodexBarCliPath
$codexBarPath = Resolve-CodexBarAppPath

New-Item -ItemType Directory -Path $appDirectory -Force | Out-Null

function Format-PlanName {
    param([string]$Plan)
    if ($Plan -match 'Pro') { return 'PRO' }
    if ($Plan -match 'Plus') { return 'PLUS' }
    if ($Plan -match 'Business') { return 'BUSINESS' }
    return 'CODEX'
}

function Get-Settings {
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    try { return Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Save-Settings {
    $settings = [pscustomobject]@{ Left = $window.Left; Top = $window.Top }
    $settings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

function New-TextBlock {
    param(
        [double]$Size,
        [string]$Color,
        [string]$Weight = 'Normal',
        [string]$Family = 'Microsoft YaHei UI'
    )
    $text = New-Object System.Windows.Controls.TextBlock
    $text.FontFamily = New-Object System.Windows.Media.FontFamily($Family)
    $text.FontSize = $Size
    $text.FontWeight = [System.Windows.FontWeights]::$Weight
    $text.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    return $text
}

function New-ProgressRing {
    param(
        [Parameter(Mandatory)][int]$Remaining,
        [Parameter(Mandatory)][string]$DisplayText,
        [Parameter(Mandatory)][string]$Color
    )

    $diameter = 48.0
    $strokeThickness = 4.0
    $ring = New-Object System.Windows.Controls.Grid
    $ring.Width = $diameter
    $ring.Height = $diameter

    $track = New-Object System.Windows.Shapes.Ellipse
    $track.Width = $diameter
    $track.Height = $diameter
    $track.StrokeThickness = $strokeThickness
    $track.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#DDE6F7')
    [void]$ring.Children.Add($track)

    if ($Remaining -ge 100) {
        $fullRing = New-Object System.Windows.Shapes.Ellipse
        $fullRing.Width = $diameter
        $fullRing.Height = $diameter
        $fullRing.StrokeThickness = $strokeThickness
        $fullRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
        [void]$ring.Children.Add($fullRing)
    }
    elseif ($Remaining -gt 0) {
        $metrics = Get-ProgressArcMetrics -Percent $Remaining -Diameter $diameter -StrokeThickness $strokeThickness
        $figure = New-Object System.Windows.Media.PathFigure
        $figure.StartPoint = New-Object System.Windows.Point($metrics.StartX, $metrics.StartY)

        $arc = New-Object System.Windows.Media.ArcSegment
        $arc.Point = New-Object System.Windows.Point($metrics.EndX, $metrics.EndY)
        $arc.Size = New-Object System.Windows.Size($metrics.Radius, $metrics.Radius)
        $arc.IsLargeArc = $metrics.IsLargeArc
        $arc.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
        [void]$figure.Segments.Add($arc)

        $geometry = New-Object System.Windows.Media.PathGeometry
        [void]$geometry.Figures.Add($figure)
        $progress = New-Object System.Windows.Shapes.Path
        $progress.Data = $geometry
        $progress.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
        $progress.StrokeThickness = $strokeThickness
        $progress.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
        $progress.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
        [void]$ring.Children.Add($progress)
    }

    $percent = New-TextBlock -Size 16 -Color '#243A5A' -Weight 'SemiBold' -Family 'Bahnschrift, Segoe UI'
    $percent.Text = $DisplayText
    $percent.HorizontalAlignment = 'Center'
    $percent.VerticalAlignment = 'Center'
    [void]$ring.Children.Add($percent)
    return $ring
}

function Add-Row {
    param(
        [System.Windows.Controls.Panel]$Container,
        [string]$Label,
        [int]$Remaining,
        [string]$Reset
    )
    $color = Get-QuotaColor -Remaining $Remaining
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Margin = New-Object System.Windows.Thickness(0, 7, 0, 0)

    $title = New-TextBlock -Size 11.5 -Color '#243A5A' -Weight 'SemiBold'
    $title.Text = $Label
    [void]$row.Children.Add($title)

    $numbers = New-Object System.Windows.Controls.StackPanel
    $numbers.Orientation = 'Horizontal'
    $percent = New-TextBlock -Size 30 -Color $color -Weight 'SemiBold' -Family 'Bahnschrift, Segoe UI'
    $percent.Text = "$Remaining%"
    [void]$numbers.Children.Add($percent)
    [void]$row.Children.Add($numbers)

    $track = New-Object System.Windows.Controls.Border
    $track.Width = 202
    $track.Height = 5
    $track.CornerRadius = New-Object System.Windows.CornerRadius(3)
    $track.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#DDE6F7')
    $fill = New-Object System.Windows.Controls.Border
    $fill.Width = [math]::Max(2, [math]::Min(202, 2.02 * $Remaining))
    $fill.Height = 5
    $fill.HorizontalAlignment = 'Left'
    $fill.CornerRadius = New-Object System.Windows.CornerRadius(3)
    $fill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $track.Child = $fill
    [void]$row.Children.Add($track)

    $resetText = New-TextBlock -Size 10.5 -Color '#6F7C91'
    $resetText.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
    $resetText.Text = Format-QuotaResetText -Raw $Reset
    [void]$row.Children.Add($resetText)
    [void]$Container.Children.Add($row)
}

function Render-Widget {
    $root.Children.Clear()
    $remaining = if ($null -eq $script:model) { 0 } else { [int]$script:model.DisplayRemaining }
    $color = Get-QuotaColor -Remaining $remaining

    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F5F8FAFC')
    $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFFFFFFF')
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.SnapsToDevicePixels = $true
    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#334A68')
    $shadow.BlurRadius = 18; $shadow.ShadowDepth = 4; $shadow.Opacity = 0.16
    $card.Effect = $shadow

    if (-not $script:expanded) {
        $window.Width = 60; $window.Height = 60
        $targetLeft = $window.Left
        $targetTop = $window.Top
        if ($null -ne $script:compactPosition) {
            $targetLeft = $script:compactPosition.Left
            $targetTop = $script:compactPosition.Top
        }
        $position = Get-VisibleWindowPosition -Left $targetLeft -Top $targetTop -Width 60 -Height 60 -WorkLeft $workArea.Left -WorkTop $workArea.Top -WorkRight $workArea.Right -WorkBottom $workArea.Bottom
        $window.Left = $position.Left; $window.Top = $position.Top
        $script:compactPosition = $null
        $card.CornerRadius = New-Object System.Windows.CornerRadius(30)
        $displayText = if ($null -eq $script:model) { '--' } else { "$remaining%" }
        $ring = New-ProgressRing -Remaining $remaining -DisplayText $displayText -Color $color
        $ring.HorizontalAlignment = 'Center'
        $ring.VerticalAlignment = 'Center'
        $card.Child = $ring
    }
    else {
        if ($null -eq $script:compactPosition) {
            $script:compactPosition = [pscustomobject]@{ Left = $window.Left; Top = $window.Top }
        }
        $visibleRowCount = 0
        if ($null -ne $script:model) {
            if ($script:model.HasPrimary) { $visibleRowCount++ }
            if ($script:model.HasWeekly) { $visibleRowCount++ }
        }
        $expandedHeight = Get-ExpandedWidgetHeight -VisibleRowCount $visibleRowCount
        $window.Width = 250; $window.Height = $expandedHeight
        $position = Get-VisibleWindowPosition -Left $script:compactPosition.Left -Top $script:compactPosition.Top -Width 250 -Height $expandedHeight -WorkLeft $workArea.Left -WorkTop $workArea.Top -WorkRight $workArea.Right -WorkBottom $workArea.Bottom
        $window.Left = $position.Left; $window.Top = $position.Top
        $card.CornerRadius = New-Object System.Windows.CornerRadius(20)
        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = New-Object System.Windows.Thickness(20, 14, 20, 12)

        $headerRow = New-Object System.Windows.Controls.Grid
        $header = New-TextBlock -Size 10.5 -Color '#243A5A' -Weight 'SemiBold' -Family 'Bahnschrift, Segoe UI'
        $planName = if ($null -eq $script:model) { 'CODEX' } else { Format-PlanName -Plan $script:model.Plan }
        $header.Text = if ($null -eq $script:model) { 'CODEX' } else { 'CODEX ' + [char]0x00B7 + ' ' + $planName }
        $header.VerticalAlignment = 'Center'
        [void]$headerRow.Children.Add($header)

        $statusColor = if ($script:stale) { '#E4A11B' } else { '#4FC28B' }
        $statusDot = New-Object System.Windows.Shapes.Ellipse
        $statusDot.Width = 8; $statusDot.Height = 8
        $statusDot.HorizontalAlignment = 'Right'
        $statusDot.VerticalAlignment = 'Center'
        $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($statusColor)
        $statusDot.ToolTip = if ($script:stale) { Get-QuotaText -Key 'Stale' } else { Get-QuotaText -Key 'Updated' }
        [void]$headerRow.Children.Add($statusDot)
        [void]$stack.Children.Add($headerRow)
        if ($null -eq $script:model) {
            $message = New-TextBlock -Size 12 -Color '#6F7C91'
            $message.Margin = New-Object System.Windows.Thickness(0, 22, 0, 0)
            $message.Text = Get-QuotaText -Key 'CliMissing'
            [void]$stack.Children.Add($message)
        }
        else {
            if ($script:model.HasPrimary) {
                Add-Row -Container $stack -Label (Get-QuotaText -Key 'Primary') -Remaining $script:model.PrimaryRemaining -Reset $script:model.PrimaryReset
            }
            if ($script:model.HasWeekly) {
                Add-Row -Container $stack -Label (Get-QuotaText -Key 'Weekly') -Remaining $script:model.WeeklyRemaining -Reset $script:model.WeeklyReset
            }
        }
        $card.Child = $stack
    }
    [void]$root.Children.Add($card)
}

function Start-QuotaRefresh {
    if ($null -ne $script:refreshJob) { return }
    if ([string]::IsNullOrWhiteSpace($cliPath) -or -not (Test-Path -LiteralPath $cliPath)) {
        $script:stale = $true
        Render-Widget
        return
    }
    $script:refreshJob = Start-Job -ArgumentList $cliPath -ScriptBlock {
        param($Path)
        & $Path usage -p codex --format json 2>$null
    }
}

function Complete-QuotaRefresh {
    if ($null -eq $script:refreshJob -or $script:refreshJob.State -notin @('Completed','Failed','Stopped')) { return }
    try {
        if ($script:refreshJob.State -ne 'Completed') { throw 'CLI refresh failed.' }
        $raw = (Receive-Job -Job $script:refreshJob -ErrorAction Stop) -join [Environment]::NewLine
        $script:model = ConvertTo-QuotaViewModel -CliJson $raw
        Save-CachedQuotaViewModel -Model $script:model -Path $cachePath
        $script:stale = $false
    }
    catch {
        $script:stale = $true
        if ($null -eq $script:model) { $script:model = Get-CachedQuotaViewModel -Path $cachePath }
    }
    finally {
        Remove-Job -Job $script:refreshJob -Force -ErrorAction SilentlyContinue
        $script:refreshJob = $null
        $script:lastRefresh = [DateTime]::UtcNow
        Render-Widget
    }
}

$settings = Get-Settings
$workArea = [System.Windows.SystemParameters]::WorkArea
$window = New-Object System.Windows.Window
$window.WindowStyle = 'None'
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ResizeMode = 'NoResize'
$window.UseLayoutRounding = $true
$window.SnapsToDevicePixels = $true
$window.Left = if ($null -ne $settings) { [double]$settings.Left } else { $workArea.Right - 100 }
$window.Top = if ($null -ne $settings) { [double]$settings.Top } else { $workArea.Bottom - 120 }

$root = New-Object System.Windows.Controls.Grid
$window.Content = $root
$script:model = Get-CachedQuotaViewModel -Path $cachePath
$script:stale = $null -ne $script:model
$script:expanded = $false
$script:compactPosition = $null
$script:refreshJob = $null
$script:lastRefresh = [DateTime]::MinValue
$script:mouseDown = $null
$script:moved = $false

$menu = New-Object System.Windows.Controls.ContextMenu
foreach ($item in @(
    @{ Text = Get-QuotaText -Key 'Refresh'; Action = { Start-QuotaRefresh } },
    @{ Text = Get-QuotaText -Key 'StartAtLogin'; Action = { & (Join-Path $PSScriptRoot 'install.ps1') -RegisterOnly } },
    @{ Text = Get-QuotaText -Key 'OpenDetails'; Action = { if (-not [string]::IsNullOrWhiteSpace($codexBarPath) -and (Test-Path -LiteralPath $codexBarPath)) { Start-Process $codexBarPath } } },
    @{ Text = Get-QuotaText -Key 'Exit'; Action = { $window.Close() } }
)) {
    $menuItem = New-Object System.Windows.Controls.MenuItem
    $menuItem.Header = $item.Text
    $menuItem.Add_Click($item.Action)
    [void]$menu.Items.Add($menuItem)
}
$window.ContextMenu = $menu

$window.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    $script:mouseDown = $eventArgs.GetPosition($window)
    $script:moved = $false
})
$window.Add_MouseMove({
    param($sender, $eventArgs)
    if ($null -eq $script:mouseDown -or $eventArgs.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
    $point = $eventArgs.GetPosition($window)
    if ([math]::Abs($point.X - $script:mouseDown.X) -gt 4 -or [math]::Abs($point.Y - $script:mouseDown.Y) -gt 4) {
        $script:moved = $true
        try { $window.DragMove() } catch { }
    }
})
$window.Add_MouseLeftButtonUp({
    if (-not $script:moved) {
        $script:expanded = -not $script:expanded
        Render-Widget
    }
    $script:mouseDown = $null
})
$window.Add_LocationChanged({ Save-Settings })
$window.Add_Closed({
    Save-Settings
    if ($null -ne $script:refreshJob) { Stop-Job -Job $script:refreshJob -ErrorAction SilentlyContinue; Remove-Job -Job $script:refreshJob -Force -ErrorAction SilentlyContinue }
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    Complete-QuotaRefresh
    if ($null -eq $script:refreshJob -and ([DateTime]::UtcNow - $script:lastRefresh).TotalSeconds -ge 60) { Start-QuotaRefresh }
})

Render-Widget
Start-QuotaRefresh
$timer.Start()
[void]$window.ShowDialog()
