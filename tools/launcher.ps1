param(
 [Parameter(Mandatory=$true)][string]$ProjectRoot,
 [switch]$Check, [switch]$InstallPython, [switch]$InstallNode,
 [switch]$GenerateChecksums
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = [IO.Path]::GetFullPath($ProjectRoot)
$log = Join-Path $root 'logs\startup.log'
function Status([string]$msg) {
 Write-Host $msg
 try { Add-Content -LiteralPath $log -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format o),$msg) } catch { Write-Warning "Logging unavailable: $_" }
}
function Check-Hash {
 $manifest = Join-Path $root 'checksums.sha256'
 if (!(Test-Path -LiteralPath $manifest)) { Status 'No checksum manifest (optional).'; return }
 foreach ($line in (Get-Content -LiteralPath $manifest -Encoding UTF8)) {
  if (!$line.Trim() -or $line.StartsWith('#')) { continue }
  if ($line -notmatch '^([a-fA-F0-9]{64})\s+\*?(.+)$') { throw 'Malformed SHA256 manifest' }
  $expected = $Matches[1]; $rel = $Matches[2]
  if ([IO.Path]::IsPathRooted($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe SHA256 path' }
  $path = [IO.Path]::GetFullPath((Join-Path $root $rel))
  if (!$path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'SHA256 path escapes project' }
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing protected file: $rel" }
  if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { throw "SHA256 mismatch: $rel" }
  Status "SHA256 OK: $rel"
 }
}
function Make-Hash {
 $files = @('Mienayura.bat','tools/launcher.ps1')
 $lines = foreach ($rel in $files) {
  $path = Join-Path $root $rel
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $rel" }
  '{0}  {1}' -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(),$rel
 }
 [IO.File]::WriteAllLines((Join-Path $root 'checksums.sha256'),[string[]]$lines,(New-Object Text.UTF8Encoding($false)))
 Status 'Generated checksums.sha256'
}
function Test-Node {
 try {
  if (!(Get-Command node.exe -ErrorAction SilentlyContinue) -or !(Get-Command npm.cmd -ErrorAction SilentlyContinue)) { return $false }
  $v = & node.exe --version
  if ($LASTEXITCODE -ne 0 -or $v -notmatch '^v(\d+)\.') { return $false }
  if ([int]$Matches[1] -lt 20) { return $false }
  & npm.cmd --version *> $null
  return ($LASTEXITCODE -eq 0)
 } catch { return $false }
}
function Test-Python {
 foreach ($exe in @('py.exe','python.exe')) {
  if (!(Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
  try {
   if ($exe -eq 'py.exe') { & py.exe -3 -c 'import sys; assert sys.version_info >= (3,10)' 2>$null }
   else { & python.exe -c 'import sys; assert sys.version_info >= (3,10)' 2>$null }
   if ($LASTEXITCODE -eq 0) { return $true }
  } catch {}
 }
 return $false
}
function Install-Package([string]$id) {
 if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget unavailable' }
 & winget.exe install --id $id --exact --source winget --accept-package-agreements --accept-source-agreements
 if ($LASTEXITCODE -ne 0) { throw "winget failed: $id ($LASTEXITCODE)" }
 $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
}
function Check-Disk {
 $drive = [IO.Path]::GetPathRoot($root)
 $info = New-Object IO.DriveInfo($drive)
 if ($info.IsReady -and $info.AvailableFreeSpace -lt 1073741824) { throw 'Less than 1 GiB free space' }
}
function Check-Write {
 $probe = Join-Path $root ('.write-test-'+[guid]::NewGuid().ToString('N'))
 try { [IO.File]::WriteAllText($probe,'ok') } finally { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force } }
}
function Install-Dependencies {
 $lock = Join-Path $root 'package-lock.json'
 $modules = Join-Path $root 'node_modules'
 $stamp = Join-Path $modules '.mienayura-lock.sha256'
 $lockHash = if (Test-Path -LiteralPath $lock) { (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash } else { '' }
 $previousHash = ''
 if (Test-Path -LiteralPath $stamp -PathType Leaf) {
  $previousHash = [string](Get-Content -LiteralPath $stamp -Raw -ErrorAction SilentlyContinue)
  $previousHash = $previousHash.Trim()
 }
 $needs = !(Test-Path -LiteralPath $modules -PathType Container) -or !(Test-Path -LiteralPath $stamp -PathType Leaf) -or ($previousHash -ne $lockHash)
 if (!$needs) {
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & npm.cmd ls --depth=0 --all=false *> $null; $npmExitCode = $LASTEXITCODE }
  finally { $ErrorActionPreference = $oldPreference }
  $needs = ($npmExitCode -ne 0)
 }
 if (!$needs) { return }
 Check-Disk
 $backup = Join-Path $root ('node_modules.backup.'+[guid]::NewGuid().ToString('N'))
 if (Test-Path -LiteralPath $modules) { Move-Item -LiteralPath $modules -Destination $backup }
 $success = $false
 try {
  for ($attempt=1; $attempt -le 3; $attempt++) {
   Status "npm install attempt $attempt/3"
   # Windows PowerShell 5.1 promotes native stderr to errors under Stop.
   # Keep the native exit code authoritative and log both output streams.
   $oldPreference = $ErrorActionPreference
   $ErrorActionPreference = 'Continue'
   try {
    if (Test-Path -LiteralPath $lock) {
     & npm.cmd ci --no-audit --no-fund 2>&1 | Out-File -LiteralPath $log -Append -Encoding UTF8
    } else {
     & npm.cmd install --no-audit --no-fund 2>&1 | Out-File -LiteralPath $log -Append -Encoding UTF8
    }
    $npmExitCode = $LASTEXITCODE
   } finally {
    $ErrorActionPreference = $oldPreference
   }
   if ($npmExitCode -eq 0) { $success = $true; break }
   if ($attempt -lt 3) { Start-Sleep -Seconds (2*$attempt) }
  }
  if (!$success) { throw 'npm dependencies installation failed after 3 attempts' }
  # npm may legitimately create no node_modules when package.json has zero dependencies.
  if (!(Test-Path -LiteralPath $modules -PathType Container)) {
   New-Item -ItemType Directory -Path $modules -Force | Out-Null
  }
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & npm.cmd ls --depth=0 *> $null; $npmExitCode = $LASTEXITCODE }
  finally { $ErrorActionPreference = $oldPreference }
  if ($npmExitCode -ne 0) { throw 'npm dependency verification failed' }
  [IO.File]::WriteAllText($stamp,$lockHash)
  if (Test-Path -LiteralPath $backup) {
   try { Remove-Item -LiteralPath $backup -Recurse -Force } catch { Status ('Backup cleanup warning: '+$_.Exception.Message) }
  }
 } catch {
  if (Test-Path -LiteralPath $modules) { Remove-Item -LiteralPath $modules -Recurse -Force }
  if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $modules }
  throw
 }
}
try {
 if (!(Test-Path -LiteralPath $root -PathType Container)) { throw 'Project directory missing' }
 New-Item -ItemType Directory -Path (Join-Path $root 'logs') -Force | Out-Null
 Check-Write
 if ($GenerateChecksums) { Make-Hash; exit 0 }
 Check-Hash
 $node = Test-Node; $python = Test-Python
 if ($InstallNode -and !$node) { Install-Package 'OpenJS.NodeJS.LTS'; $node = Test-Node }
 if ($InstallPython -and !$python) { Install-Package 'Python.Python.3.12'; $python = Test-Python }
 if ($Check) { Status "CHECK Node=$node Python=$python"; exit 0 }
 if (!(Test-Path -LiteralPath (Join-Path $root 'package.json'))) { Status 'No package.json yet: application not initialized'; exit 0 }
 if (!$node) { throw 'Node.js >=20 or npm missing. Use -InstallNode' }
 $manifest = Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if (!$manifest.scripts -or !$manifest.scripts.start) { throw 'Missing npm start script' }
 Push-Location -LiteralPath $root
 try {
  Install-Dependencies
  & npm.cmd run start
  if ($LASTEXITCODE -ne 0) { throw "App failed: $LASTEXITCODE" }
 } finally { Pop-Location }
 exit 0
} catch {
 Status ('ERROR: '+$_.Exception.Message)
 exit 1
}
