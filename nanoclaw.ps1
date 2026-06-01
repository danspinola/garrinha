#Requires -Version 5.1
<#
.SYNOPSIS
  NanoClaw — end-to-end setup entry point for Windows.
  Equivalent of nanoclaw.sh for PowerShell.

  Runs bootstrap (Node + pnpm + native modules), then hands off to
  `pnpm run setup:auto` which handles the rest cross-platform.
#>
$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

$LogsDir = Join-Path $ProjectRoot 'logs'
$StepsDir = Join-Path $LogsDir 'setup-steps'
$ProgressLog = Join-Path $LogsDir 'setup.log'

# --- Log helpers ---
function Get-TsUtc { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Write-Header {
    $ts = Get-TsUtc
    $branch = try { & git branch --show-current 2>$null } catch { 'unknown' }
    $commit = try { & git rev-parse --short HEAD 2>$null } catch { 'unknown' }
    if (-not $branch) { $branch = 'unknown' }
    if (-not $commit) { $commit = 'unknown' }
    @"
## $ts · setup:auto started
  invocation: nanoclaw.ps1
  user: $env:USERNAME
  cwd: $ProjectRoot
  branch: $branch
  commit: $commit

"@ | Out-File -FilePath $ProgressLog -Encoding utf8
}

function Write-BootstrapEntry($status, $dur, $rawLog) {
    $ts = Get-TsUtc
    $rel = $rawLog.Replace($ProjectRoot + '\', '').Replace('\', '/')
    @"
=== [$ts] bootstrap [${dur}s] -> $status ===
  platform: windows
  raw: $rel

"@ | Out-File -Append -FilePath $ProgressLog -Encoding utf8
}

# --- Status line helpers ---
$UseColor = $Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION

function Write-Spinner($msg) {
    if ($UseColor) { Write-Host "`e[90m◒`e[0m  $msg..." -NoNewline }
    else { Write-Host "o  $msg..." -NoNewline }
}

function Write-SpinnerSuccess($msg, $dur) {
    if ($UseColor) {
        Write-Host "`r`e[2K`e[90m◇`e[0m  $msg `e[2m(${dur}s)`e[0m"
    } else {
        Write-Host "`r  $msg (${dur}s)"
    }
}

function Write-SpinnerFailure($msg, $dur) {
    if ($UseColor) {
        Write-Host "`r`e[2K`e[31m✗`e[0m  $msg `e[2m(${dur}s)`e[0m"
    } else {
        Write-Host "`r  FAILED: $msg (${dur}s)"
    }
}

# --- Fresh-run setup ---
if (Test-Path $StepsDir) { Remove-Item $StepsDir -Recurse -Force }
if (Test-Path $ProgressLog) { Remove-Item $ProgressLog -Force }
New-Item -ItemType Directory -Path $StepsDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
Write-Header

# --- Splash ---
$splashFile = Join-Path $ProjectRoot 'assets' 'setup-splash.txt'
if (Test-Path $splashFile) {
    Get-Content $splashFile | Write-Host
}

# --- Pre-flight: minimum RAM ---
$MinMemMB = 3700
try {
    $totalMem = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $memMB = [math]::Floor($totalMem / 1MB)
} catch {
    $memMB = 0
}

if ($memMB -gt 0 -and $memMB -lt $MinMemMB) {
    Write-Host ''
    if ($UseColor) {
        Write-Host "  `e[31mWarning: this machine likely cannot run NanoClaw.`e[0m"
        Write-Host "  `e[2mNanoClaw recommends a 4 GB+ RAM machine.`e[0m"
        Write-Host "  `e[2m  - Detected RAM: $memMB MB`e[0m"
    } else {
        Write-Host '  Warning: this machine likely cannot run NanoClaw.'
        Write-Host "  NanoClaw recommends a 4 GB+ RAM machine. Detected: $memMB MB"
    }
    Write-Host ''
    $ans = Read-Host '  Try anyway? [y/N]'
    if ($ans -notmatch '^[Yy]') {
        Write-Host '  Aborted. Re-run after upgrading the host.'
        exit 1
    }
    Write-Host ''
}

# --- Pre-flight: Docker Desktop check ---
$dockerBin = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerBin) {
    Write-Host ''
    if ($UseColor) {
        Write-Host "  `e[33mDocker Desktop is not installed.`e[0m"
        Write-Host "  `e[2mNanoClaw requires Docker Desktop for Windows (uses WSL2 backend for Linux containers).`e[0m"
    } else {
        Write-Host '  Docker Desktop is not installed.'
        Write-Host '  NanoClaw requires Docker Desktop for Windows.'
    }
    Write-Host ''
    $ans = Read-Host '  Install Docker Desktop now? [Y/n]'
    if ($ans -match '^[Nn]') {
        Write-Host '  NanoClaw needs Docker. Install from https://docker.com/products/docker-desktop and re-run.'
        exit 1
    }
    Write-Host ''
    $installScript = Join-Path $ProjectRoot 'setup' 'install-docker-win.ps1'
    & $installScript
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# --- Bootstrap: install the basics ---
$BootstrapRaw = Join-Path $StepsDir '01-bootstrap.log'
$BootstrapLabel = 'Installing the basics'
$BootstrapStart = Get-Date

Write-Spinner $BootstrapLabel

$env:NANOCLAW_BOOTSTRAP_LOG = $BootstrapRaw
$bootstrapScript = Join-Path $ProjectRoot 'setup-win.ps1'

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapScript *> $BootstrapRaw
    $BootstrapRC = $LASTEXITCODE
} catch {
    $_ | Out-File -Append -FilePath $BootstrapRaw -Encoding utf8
    $BootstrapRC = 1
}

$BootstrapDur = [math]::Floor(((Get-Date) - $BootstrapStart).TotalSeconds)

if ($BootstrapRC -eq 0) {
    Write-SpinnerSuccess 'Basics ready' $BootstrapDur
    Write-BootstrapEntry 'success' $BootstrapDur $BootstrapRaw
} else {
    Write-SpinnerFailure "Couldn't install the basics" $BootstrapDur
    Write-BootstrapEntry 'failed' $BootstrapDur $BootstrapRaw
    Write-Host ''
    Write-Host '-- last 40 lines of bootstrap log --'
    Get-Content $BootstrapRaw -Tail 40
    Write-Host ''
    Write-Host "Full raw log: $BootstrapRaw"
    Write-Host "Progression:  $ProgressLog"
    exit 1
}

# --- Hand off to setup:auto ---
$env:NANOCLAW_BOOTSTRAPPED = '1'

# Refresh PATH to pick up any newly installed pnpm
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Ensure pnpm is available
$pnpmBin = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $pnpmBin) {
    # Try npm global prefix
    $npmBin = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmBin) {
        $npmPrefix = & npm config get prefix 2>$null
        if ($npmPrefix -and (Test-Path (Join-Path $npmPrefix 'pnpm.cmd'))) {
            $env:Path = "$npmPrefix;$env:Path"
        }
    }
}

# Run setup:auto
& pnpm --silent run setup:auto @args
exit $LASTEXITCODE
