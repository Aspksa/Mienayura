$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bat = Join-Path $repo 'Mienayura.bat'
$launcher = Join-Path $repo 'tools\launcher.ps1'
function Assert([bool]$condition, [string]$message) {
  if (-not $condition) { throw "FAIL: $message" }
  Write-Host "PASS: $message"
}
Assert (Test-Path -LiteralPath $bat) 'BAT exists'
Assert (Test-Path -LiteralPath $launcher) 'PowerShell launcher exists'
$batText = Get-Content -LiteralPath $bat -Raw
$source = Get-Content -LiteralPath $launcher -Raw -Encoding UTF8
Assert ($batText.Contains('%~dp0')) 'BAT uses own directory'
Assert ($batText.Contains('"%MIENAYURA_ROOT%tools\launcher.ps1"')) 'Quoted script path'
Assert ($source.Contains('Push-Location -LiteralPath $root')) 'Literal Unicode-safe working directory'
Assert ($source.Contains('winget.exe install --id Python.Python.3.12')) 'Python installer uses trusted winget package'
Assert ($source.Contains('OpenJS.NodeJS.LTS')) 'Node LTS installed via official winget package'
Assert ($source.Contains('function Find-Node')) 'Node version and npm checks'
Assert ($source.Contains('if ($InstallNode)')) 'Node installation opt-in switch'
Assert ($source.Contains('if ($InstallPython)')) 'Python installation opt-in switch'
Assert ($source.Contains('npm.cmd')) 'PowerShell execution-policy-safe npm invocation'
Assert ($source.Contains('startup.log')) 'Diagnostic log configured'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Mienayura тест путь ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
  $copy = Join-Path $temp 'tools'
  New-Item -ItemType Directory -Path $copy | Out-Null
  Copy-Item -LiteralPath $launcher -Destination (Join-Path $copy 'launcher.ps1')
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copy 'launcher.ps1') -ProjectRoot $temp
  Assert ($LASTEXITCODE -eq 0) 'Launch from Cyrillic path without app succeeds'
  Assert (Test-Path -LiteralPath (Join-Path $temp 'logs\startup.log')) 'Log created in Cyrillic path'
  $log = Get-Content -LiteralPath (Join-Path $temp 'logs\startup.log') -Raw -Encoding UTF8
  Assert ($log.Contains('package.json')) 'Missing app is reported, not silently launched'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host 'All launcher smoke tests passed.'
