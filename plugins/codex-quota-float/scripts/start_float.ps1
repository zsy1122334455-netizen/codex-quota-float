$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $pluginRoot "scripts\stop_float.ps1")
$pythonw = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\pythonw.exe"
if (-not (Test-Path -LiteralPath $pythonw)) {
  $pythonw = "pythonw"
}
$scriptArgs = @((Join-Path $pluginRoot "scripts\float_widget.py"))
Start-Process -FilePath $pythonw `
  -ArgumentList $scriptArgs `
  -WorkingDirectory $pluginRoot `
  -WindowStyle Hidden
