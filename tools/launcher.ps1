param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [switch]$Check,
  [switch]$InstallPython,
  [switch]$InstallNode,
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
function Test-Integrity {
  $manifestPath = Join-Path $root 'checksums.sha256'
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Status 'No checksums.sha256: integrity verification skipped.'
    return
  }
  foreach ($line in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
    if (-not $line.Trim() -or $line.StartsWith('#')) { continue }
    if ($line -notmatch '^([a-fA-F0-9]{64})\s+\*?(.+)
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
function Find-Node {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $node -or -not $npm) { return $false }
  try {
    $version = (& node.exe --version 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v(\d+)\.') { return $false }
    if ([int]$Matches[1] -lt 20) { Write-Status "Node.js is outdated: $version"; return $false }
    & npm.cmd --version *> $null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}
function Require-Node {
  if (Find-Node) { Write-Status ('Node.js available: ' + (& node.exe --version)); return $true }
  Write-Status 'Node.js >=20 and npm.cmd are required.'
  if (-not $InstallNode) {
    Write-Status 'Run Mienayura.bat -InstallNode to install Node.js LTS with winget.'
    return $false
  }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Write-Status 'winget unavailable; install Node.js LTS from https://nodejs.org/'
    return $false
  }
  Write-Status 'Installing Node.js LTS from official winget package...'
  & winget.exe install --id OpenJS.NodeJS.LTS --exact --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Node installation failed: $LASTEXITCODE" }
  $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  if (-not (Find-Node)) { Write-Status 'Node installed but not available yet. Restart launcher.'; return $false }
  return $true
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
  Test-Integrity
  $python = Find-Python
  if ($InstallPython) { $python = Require-Python }
  $node = Find-Node
  if ($InstallNode) { $node = Require-Node }
  if ($Check) {
    Write-Status ('CHECK: root exists; Python={0}; Node={1}' -f [bool]$python, [bool]$node)
    exit 0
  }
  $package = Join-Path $root 'package.json'
  if (-not (Test-Path -LiteralPath $package)) {
    Write-Status 'Application not initialized: package.json is missing. Launcher check complete.'
    exit 0
  }
  if (-not $node) { throw 'Node.js/npm unavailable or outdated. Run Mienayura.bat -InstallNode' }
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
) { throw 'Malformed checksums.sha256 entry' }
    $expected = $Matches[1].ToUpperInvariant()
    $relative = $Matches[2].Trim()
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe checksum path' }
    $target = [IO.Path]::GetFullPath((Join-Path $root $relative))
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Checksum path escapes root' }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Missing integrity file: $relative" }
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "SHA256 mismatch: $relative" }
    Write-Status "SHA256 OK: $relative"
  }
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
function Find-Node {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $node -or -not $npm) { return $false }
  try {
    $version = (& node.exe --version 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v(\d+)\.') { return $false }
    if ([int]$Matches[1] -lt 20) { Write-Status "Node.js is outdated: $version"; return $false }
    & npm.cmd --version *> $null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}
function Require-Node {
  if (Find-Node) { Write-Status ('Node.js available: ' + (& node.exe --version)); return $true }
  Write-Status 'Node.js >=20 and npm.cmd are required.'
  if (-not $InstallNode) {
    Write-Status 'Run Mienayura.bat -InstallNode to install Node.js LTS with winget.'
    return $false
  }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Write-Status 'winget unavailable; install Node.js LTS from https://nodejs.org/'
    return $false
  }
  Write-Status 'Installing Node.js LTS from official winget package...'
  & winget.exe install --id OpenJS.NodeJS.LTS --exact --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Node installation failed: $LASTEXITCODE" }
  $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  if (-not (Find-Node)) { Write-Status 'Node installed but not available yet. Restart launcher.'; return $false }
  return $true
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
  $python = Find-Python
  if ($InstallPython) { $python = Require-Python }
  $node = Find-Node
  if ($InstallNode) { $node = Require-Node }
  if ($Check) {
    Write-Status ('CHECK: root exists; Python={0}; Node={1}' -f [bool]$python, [bool]$node)
    exit 0
  }
  $package = Join-Path $root 'package.json'
  if (-not (Test-Path -LiteralPath $package)) {
    Write-Status 'Application not initialized: package.json is missing. Launcher check complete.'
    exit 0
  }
  if (-not $node) { throw 'Node.js/npm unavailable or outdated. Run Mienayura.bat -InstallNode' }
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
