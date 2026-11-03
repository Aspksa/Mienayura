$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bat = Join-Path $repo 'Mienayura.bat'
$launcher = Join-Path $repo 'tools\launcher.ps1'
function Assert([bool]$ok,[string]$message) { if (!$ok) { throw "FAIL: $message" }; Write-Host "PASS: $message" }
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($launcher,[ref]$tokens,[ref]$errors) | Out-Null
Assert ($errors.Count -eq 0) ('PowerShell parser: '+($errors | Out-String))
$source = Get-Content -LiteralPath $launcher -Raw -Encoding UTF8
Assert ($source.Contains('function Install-Dependencies')) 'Dependency repair exists'
Assert ($source.Contains('for ($attempt=1; $attempt -le 3; $attempt++)')) 'Retries bounded'
Assert ($source.Contains('function Check-Disk')) 'Disk check exists'
Assert ($source.Contains('function Check-Write')) 'Write permissions checked'
Assert ($source.Contains('Get-FileHash')) 'SHA256 checks'
Assert ($source.Contains('function Make-Hash')) 'SHA256 generation'
Assert ($source.Contains('npm may legitimately create no node_modules')) 'Zero-dependency app supported'
Assert ((Get-Content -LiteralPath $bat -Raw).Contains('%~dp0')) 'BAT path anchored to itself'
Assert ((Get-Content -LiteralPath $bat -Raw).Contains('%MIENAYURA_ROOT%.')) 'BAT avoids trailing backslash in quoted native argument'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Миена тест (скобки) & кавычки пробелы '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp 'tools') -Force | Out-Null
try {
 Copy-Item -LiteralPath $launcher -Destination (Join-Path $temp 'tools\launcher.ps1')
 Copy-Item -LiteralPath $bat -Destination (Join-Path $temp 'Mienayura.bat')
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $temp 'tools\launcher.ps1') -ProjectRoot $temp -GenerateChecksums
 Assert ($LASTEXITCODE -eq 0) 'Generate SHA256 manifest with Unicode/special path'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $temp 'tools\launcher.ps1') -ProjectRoot $temp -Check
 Assert ($LASTEXITCODE -eq 0) 'Verify SHA256 and environment'
 Add-Content -LiteralPath (Join-Path $temp 'Mienayura.bat') -Value 'rem tampered'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $temp 'tools\launcher.ps1') -ProjectRoot $temp -Check
 Assert ($LASTEXITCODE -ne 0) 'Reject modified protected file'
 Copy-Item -LiteralPath $bat -Destination (Join-Path $temp 'Mienayura.bat') -Force
 & (Join-Path $temp 'Mienayura.bat') -Check
 Assert ($LASTEXITCODE -eq 0) 'BAT launches from Cyrillic, spaces, parentheses and ampersand'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host 'All tests passed.'
