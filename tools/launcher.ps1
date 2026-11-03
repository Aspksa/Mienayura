param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [switch]$Check,
  [switch]$InstallPython,
  [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = [IO.Path]::GetFullPath($ProjectRoot)
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir 'startup.log'
function Write-Status([string]$message) {
  Write-Host $message
  Add-Content -LiteralPath $log -Value ('[{0}] {1}' -f (Get-Date -Format o), $message) -Encoding UTF8
}
function Find-Python {
  $candidates = @(
    @{Exe='py.exe'; Args=@('-3.12','-c','import sys; print(sys.version_info[:2])')},
    @{Exe='py.exe'; Args=@('-3','-c','import sys; print(sys.version_info[:2])')},
    @{Exe='python.exe'; Args=@('-c','import sys; print(sys.version_info[:2])')}
  )
  foreach ($candidate in $candidates) {
    if (-not (Get-Command $candidate.Exe -ErrorAction SilentlyContinue)) { continue }
    try {
      $output = & $candidate.Exe @($candidate.Args) 2>$null
      if ($LASTEXITCODE -eq 0 -and $output) { return $candidate.Exe }
    } catch { }
  }
  return $null
}
function Require-Python {
  $found = Find-Python
  if ($found) { Write-Status "Python available: $found"; return $true }
  Write-Status 'Python is missing.'
  if (-not $InstallPython) {
    Write-Status 'To install Python automatically, run Mienayura.bat -InstallPython'
    return $false
  }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Write-Status 'winget is unavailable. Install Python from https://www.python.org/downloads/windows/'
    return $false
  }
  Write-Status 'Installing Python 3.12 using Windows Package Manager...'
  & winget.exe install --id Python.Python.3.12 --exact --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Python installation failed with code $LASTEXITCODE" }
  $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  $found = Find-Python
  if (-not $found) { Write-Status 'Python installed; reopen terminal if command is not available yet.'; return $false }
  Write-Status "Python installed: $found"
  return $true
}
try {
  Write-Status "Root: $root"
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Project folder missing' }
  $python = Require-Python
  if ($Check) {
    Write-Status ('CHECK: root exists; Python={0}' -f $python)
    exit $(if ($python) {0} else {3})
  }
  $package = Join-Path $root 'package.json'
  if (-not (Test-Path -LiteralPath $package)) {
    Write-Status 'Application not initialized: package.json is missing. Launcher check complete.'
    exit 0
  }
  if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Node.js is missing: https://nodejs.org/' }
  if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'npm.cmd is missing' }
  $manifest = Get-Content -LiteralPath $package -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $manifest.scripts -or -not $manifest.scripts.start) { throw 'package.json has no scripts.start' }
  Push-Location -LiteralPath $root
  try {
    if (-not (Test-Path -LiteralPath (Join-Path $root 'node_modules'))) {
      Write-Status 'Installing Node dependencies...'
      if (Test-Path -LiteralPath (Join-Path $root 'package-lock.json')) { & npm.cmd ci 2>&1 | Out-File -LiteralPath $log -Append -Encoding UTF8 }
      else { & npm.cmd install 2>&1 | Out-File -LiteralPath $log -Append -Encoding UTF8 }
      if ($LASTEXITCODE -ne 0) { throw "npm install failed: $LASTEXITCODE" }
    }
    Write-Status 'Starting application...'
    & npm.cmd run start
    if ($LASTEXITCODE -ne 0) { throw "Application exited with code $LASTEXITCODE" }
  } finally { Pop-Location }
  exit 0
} catch {
  Write-Status ('ERROR: ' + $_.Exception.Message)
  exit 1
}
