param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'design\codex-quota-float-ui-v2-actual.png'),
    [string]$CompactOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'design\codex-quota-float-ui-v2-compact-actual.png'),
    [switch]$WeeklyFixture
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WidgetVisualProbe {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
    [DllImport("gdi32.dll", SetLastError=true)] public static extern bool BitBlt(IntPtr destination, int destinationX, int destinationY, int width, int height, IntPtr source, int sourceX, int sourceY, uint operation);

    public static IntPtr Find(uint targetPid, int minimumWidth) {
        IntPtr result = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; RECT rect;
            GetWindowThreadProcessId(h, out pid);
            if (pid == targetPid && IsWindowVisible(h) && GetWindowRect(h, out rect) && rect.Right - rect.Left >= minimumWidth) {
                result = h;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static RECT Rect(IntPtr hWnd) {
        RECT rect;
        GetWindowRect(hWnd, out rect);
        return rect;
    }

    public static void Click(IntPtr hWnd) {
        RECT rect = Rect(hWnd);
        SetForegroundWindow(hWnd);
        SetCursorPos((rect.Left + rect.Right) / 2, (rect.Top + rect.Bottom) / 2);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
}
'@

function Save-LayeredWindowCapture {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$ExpectedWidth,
        [Parameter(Mandatory)][int]$ExpectedHeight
    )

    $rect = [WidgetVisualProbe]::Rect($Handle)
    $logicalWidth = $rect.Right - $rect.Left
    $logicalHeight = $rect.Bottom - $rect.Top
    if ($logicalWidth -ne $ExpectedWidth -or $logicalHeight -ne $ExpectedHeight) {
        throw "Unexpected widget size ${logicalWidth}x${logicalHeight}; expected ${ExpectedWidth}x${ExpectedHeight}."
    }

    $dpiScale = [WidgetVisualProbe]::GetDpiForWindow($Handle) / 96.0
    $physicalLeft = [int][math]::Round($rect.Left * $dpiScale)
    $physicalTop = [int][math]::Round($rect.Top * $dpiScale)
    $physicalWidth = [int][math]::Round($logicalWidth * $dpiScale)
    $physicalHeight = [int][math]::Round($logicalHeight * $dpiScale)
    $padding = [int][math]::Round(18 * $dpiScale)
    $bitmapWidth = [int]($physicalWidth + (2 * $padding))
    $bitmapHeight = [int]($physicalHeight + (2 * $padding))
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $bitmapWidth,$bitmapHeight
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $screenGraphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $destinationHdc = [IntPtr]::Zero
    $sourceHdc = [IntPtr]::Zero
    try {
        $destinationHdc = $graphics.GetHdc()
        $sourceHdc = $screenGraphics.GetHdc()
        $captureLayeredWindows = [uint32]0x40CC0020
        $captured = [WidgetVisualProbe]::BitBlt($destinationHdc, 0, 0, $bitmapWidth, $bitmapHeight, $sourceHdc, $physicalLeft - $padding, $physicalTop - $padding, $captureLayeredWindows)
        if (-not $captured) { throw 'BitBlt failed to capture the layered WPF window.' }
    }
    finally {
        if ($destinationHdc -ne [IntPtr]::Zero) { $graphics.ReleaseHdc($destinationHdc) }
        if ($sourceHdc -ne [IntPtr]::Zero) { $screenGraphics.ReleaseHdc($sourceHdc) }
        $screenGraphics.Dispose()
    }

    try {
        $directory = Split-Path -Parent $Path
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    return [pscustomobject]@{ LogicalWidth = $logicalWidth; LogicalHeight = $logicalHeight; DpiScale = $dpiScale; Path = $Path }
}

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'CodexQuotaFloat.ps1'
$stdout = Join-Path $env:TEMP 'CodexQuotaFloat-capture.out.log'
$stderr = Join-Path $env:TEMP 'CodexQuotaFloat-capture.err.log'
$process = $null
$fixtureRoot = $null
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$childAppData = $originalAppData

try {
    if ($WeeklyFixture) {
        $fixtureRoot = Join-Path $env:TEMP ("CodexQuotaFloat-capture-" + [guid]::NewGuid().ToString('N'))
        $childAppData = Join-Path $fixtureRoot 'AppData'
        $childLocalAppData = Join-Path $fixtureRoot 'LocalAppData'
        $fixtureAppDirectory = Join-Path $childAppData 'CodexQuotaFloat'
        New-Item -ItemType Directory -Path $fixtureAppDirectory,$childLocalAppData -Force | Out-Null
        [pscustomobject]@{
            SchemaVersion = 3
            Plan = 'ChatGPT Pro'
            HasWeekly = $true
            WeeklyRemaining = 81
            WeeklyReset = '6d 9h'
            DisplayRemaining = 81
            UpdatedAt = '2026-07-13T10:00:00Z'
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixtureAppDirectory 'last_usage.json') -Encoding UTF8
        $env:APPDATA = $childAppData
        $env:LOCALAPPDATA = $childLocalAppData
    }

    $captureStartedAt = [DateTime]::UtcNow
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$scriptPath) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $compactHandle = [IntPtr]::Zero
    for ($i = 0; $i -lt 40 -and $compactHandle -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $compactHandle = [WidgetVisualProbe]::Find([uint32]$process.Id, 60)
    }
    if ($compactHandle -eq [IntPtr]::Zero) { throw 'Compact widget window was not found.' }
    $compactCapture = Save-LayeredWindowCapture -Handle $compactHandle -Path $CompactOutputPath -ExpectedWidth 60 -ExpectedHeight 60

    [WidgetVisualProbe]::Click($compactHandle)
    $expandedHandle = [IntPtr]::Zero
    for ($i = 0; $i -lt 30 -and $expandedHandle -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $expandedHandle = [WidgetVisualProbe]::Find([uint32]$process.Id, 200)
    }
    if ($expandedHandle -eq [IntPtr]::Zero) {
        $details = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        throw "Expanded widget window was not found. $details"
    }

    $cachePath = Join-Path $childAppData 'CodexQuotaFloat\last_usage.json'
    if (-not $WeeklyFixture) {
        for ($i = 0; $i -lt 100; $i++) {
            if ((Test-Path -LiteralPath $cachePath) -and (Get-Item -LiteralPath $cachePath).LastWriteTimeUtc -ge $captureStartedAt) { break }
            Start-Sleep -Milliseconds 100
        }
    }
    Start-Sleep -Milliseconds 250

    $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
    $visibleRows = [int][bool]$cache.HasWeekly
    $expectedHeight = if ($visibleRows -le 1) { 140 } else { 210 }
    $expandedCapture = Save-LayeredWindowCapture -Handle $expandedHandle -Path $OutputPath -ExpectedWidth 250 -ExpectedHeight $expectedHeight
    Write-Output "PASS: captured compact $($compactCapture.LogicalWidth)x$($compactCapture.LogicalHeight) and expanded $($expandedCapture.LogicalWidth)x$($expandedCapture.LogicalHeight) DIP at $($expandedCapture.DpiScale)x."
}
finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
    if ($null -ne $fixtureRoot) {
        $resolvedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if ($resolvedFixtureRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
