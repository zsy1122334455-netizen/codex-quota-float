$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WidgetInteractionProbe {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    public static bool ClickVisibleWindow(uint targetPid) {
        bool clicked = false;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r;
            if (pid == targetPid && IsWindowVisible(h) && GetWindowRect(h, out r)) {
                int width = r.Right - r.Left;
                int height = r.Bottom - r.Top;
                if (width >= 60 && width <= 90 && height >= 60 && height <= 90) {
                    SetForegroundWindow(h);
                    SetCursorPos((r.Left + r.Right) / 2, (r.Top + r.Bottom) / 2);
                    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
                    System.Threading.Thread.Sleep(80);
                    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
                    clicked = true;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return clicked;
    }

    public static bool ClickExpandedWindow(uint targetPid) {
        bool clicked = false;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r;
            if (pid == targetPid && IsWindowVisible(h) && GetWindowRect(h, out r)) {
                int width = r.Right - r.Left;
                int height = r.Bottom - r.Top;
                if (width >= 200 && width <= 400 && height >= 100 && height <= 350) {
                    SetForegroundWindow(h);
                    SetCursorPos((r.Left + r.Right) / 2, (r.Top + r.Bottom) / 2);
                    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
                    System.Threading.Thread.Sleep(80);
                    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
                    clicked = true;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return clicked;
    }

    public static int GetVisibleWidgetWidth(uint targetPid) {
        int result = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r;
            if (pid == targetPid && IsWindowVisible(h) && GetWindowRect(h, out r)) {
                int width = r.Right - r.Left;
                int height = r.Bottom - r.Top;
                if (width >= 60 && width <= 400 && height >= 60 && height <= 300) {
                    result = width;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'CodexQuotaFloat.ps1'
$stdout = Join-Path $env:TEMP 'CodexQuotaFloat-click-test.out.log'
$stderr = Join-Path $env:TEMP 'CodexQuotaFloat-click-test.err.log'
Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
$process = $null

try {
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$scriptPath) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $clicked = $false
    for ($i = 0; $i -lt 30 -and -not $clicked; $i++) {
        Start-Sleep -Milliseconds 100
        $process.Refresh()
        if ($process.HasExited) { break }
        $clicked = [WidgetInteractionProbe]::ClickVisibleWindow([uint32]$process.Id)
    }
    if (-not $clicked) { throw 'FAIL: widget window was not visible for clicking.' }
    $observedWidths = New-Object System.Collections.Generic.List[int]
    for ($sample = 0; $sample -lt 20; $sample++) {
        [void]$observedWidths.Add([WidgetInteractionProbe]::GetVisibleWidgetWidth([uint32]$process.Id))
        Start-Sleep -Milliseconds 50
    }
    $process.Refresh()
    if ($process.HasExited) {
        $details = Get-Content -Raw -LiteralPath $stderr -ErrorAction SilentlyContinue
        throw "FAIL: widget exited after click. $details"
    }
    $expandedWidth = [WidgetInteractionProbe]::GetVisibleWidgetWidth([uint32]$process.Id)
    if ($expandedWidth -ne 250) { throw "FAIL: widget did not expand to 250 DIP after click. Width was $expandedWidth. Samples: $($observedWidths -join ',')." }

    if (-not [WidgetInteractionProbe]::ClickExpandedWindow([uint32]$process.Id)) {
        throw 'FAIL: expanded widget was not visible for the collapse click.'
    }
    Start-Sleep -Milliseconds 500
    $collapsedWidth = [WidgetInteractionProbe]::GetVisibleWidgetWidth([uint32]$process.Id)
    if ($collapsedWidth -ne 60) { throw "FAIL: second click did not collapse widget to 60 DIP. Width was $collapsedWidth." }
    Write-Output 'PASS: widget toggles 60 -> 250 -> 60 and remains running.'
}
finally {
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}
