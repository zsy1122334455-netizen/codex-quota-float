$pidFile = Join-Path $env:USERPROFILE ".codex\quota-float-widget.pid"
if (Test-Path -LiteralPath $pidFile) {
  $pidValue = Get-Content -LiteralPath $pidFile -Raw
  $pidNumber = 0
  if ([int]::TryParse($pidValue.Trim(), [ref]$pidNumber)) {
    Stop-Process -Id $pidNumber -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -match '^pythonw?\.exe$' -and
    $_.CommandLine -like '*codex-quota-float*float_widget.py*'
  } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
