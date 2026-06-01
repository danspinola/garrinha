#Requires -Version 5.1
<#
.SYNOPSIS
  NanoClaw bootstrap for Windows — equivalent of setup.sh.
  Installs Node.js + pnpm, runs pnpm install, verifies native modules.
#>
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ($PSScriptRoot -eq (Split-Path -Parent $MyInvocation.MyCommand.Path)) {
    $ProjectRoot = $PSScriptRoot
}
# If invoked from project root directly
if (Test-Path (Join-Path $PSScriptRoot 'package.json')) {
    $ProjectRoot = $PSScriptRoot
}

$LogsDir = Join-Path $ProjectRoot 'logs'
if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }

$LogFile = if ($env:NANOCLAW_BOOTSTRAP_LOG) { $env:NANOCLAW_BOOTSTRAP_LOG } else { Join-Path $LogsDir 'bootstrap.log' }

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] [bootstrap] $msg" | Out-File -Append -FilePath $LogFile -Encoding utf8
}

# --- Platform detection ---
$Platform = 'windows'
$IsWSL = 'false'
$IsRoot = 'false'  # Not applicable on Windows

Write-Log "Platform: $Platform, WSL: $IsWSL, Root: $IsRoot"

# --- Node.js check ---
$NodeOK = 'false'
$NodeVersion = 'not_found'
$NodePathFound = 'not_found'

$nodeBin = Get-Command node -ErrorAction SilentlyContinue
if ($nodeBin) {
    $NodeVersion = (& node --version 2>$null) -replace '^v', ''
    $NodePathFound = $nodeBin.Source
    $major = [int]($NodeVersion.Split('.')[0])
    if ($major -ge 20) { $NodeOK = 'true' }
    Write-Log "Node $NodeVersion at $NodePathFound (major=$major, ok=$NodeOK)"
} else {
    Write-Log 'Node not found'
}

# --- Install Node if missing ---
if ($NodeOK -eq 'false') {
    Write-Log 'Node missing or too old - attempting install'
    $installScript = Join-Path $ProjectRoot 'setup' 'install-node-win.ps1'
    if (Test-Path $installScript) {
        & $installScript 2>&1 | Out-File -Append -FilePath $LogFile -Encoding utf8
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $nodeBin = Get-Command node -ErrorAction SilentlyContinue
        if ($nodeBin) {
            $NodeVersion = (& node --version 2>$null) -replace '^v', ''
            $NodePathFound = $nodeBin.Source
            $major = [int]($NodeVersion.Split('.')[0])
            if ($major -ge 20) { $NodeOK = 'true' }
            Write-Log "Node $NodeVersion at $NodePathFound (major=$major, ok=$NodeOK)"
        }
    } else {
        Write-Log 'install-node-win.ps1 not found'
    }
}

# --- pnpm install ---
$DepsOK = 'false'
$NativeOK = 'false'

if ($NodeOK -eq 'true') {
    Set-Location $ProjectRoot
    $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'

    # Enable corepack
    $corepackBin = Get-Command corepack -ErrorAction SilentlyContinue
    if ($corepackBin) {
        Write-Log 'Enabling corepack'
        & corepack enable 2>&1 | Out-File -Append -FilePath $LogFile -Encoding utf8
    }

    # Check pnpm
    $pnpmBin = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpmBin) {
        # Fallback: install via npm
        $npmBin = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmBin) {
            $pinned = 'latest'
            $pkgJson = Get-Content (Join-Path $ProjectRoot 'package.json') -Raw | ConvertFrom-Json
            if ($pkgJson.packageManager -match 'pnpm@(.+)') {
                $pinned = $Matches[1]
            }
            Write-Log "Installing pnpm@$pinned via npm"
            & npm install -g "pnpm@$pinned" 2>&1 | Out-File -Append -FilePath $LogFile -Encoding utf8
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        }
    }

    $pnpmBin = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpmBin) {
        Write-Log 'pnpm not on PATH after install attempts'
    } else {
        Write-Log 'Running pnpm install --frozen-lockfile'
        $installResult = & pnpm install --frozen-lockfile 2>&1
        $installResult | Out-File -Append -FilePath $LogFile -Encoding utf8
        if ($LASTEXITCODE -eq 0) {
            $DepsOK = 'true'
            Write-Log 'pnpm install succeeded'
        } else {
            Write-Log 'pnpm install failed'
        }

        # Verify native module
        if ($DepsOK -eq 'true') {
            Write-Log 'Verifying native modules'
            & node -e "require('better-sqlite3')" 2>&1 | Out-File -Append -FilePath $LogFile -Encoding utf8
            if ($LASTEXITCODE -eq 0) {
                $NativeOK = 'true'
                Write-Log 'better-sqlite3 loads OK'
            } else {
                Write-Log 'better-sqlite3 failed to load'
            }
        }
    }
} else {
    Write-Log 'Skipping pnpm install - Node not available'
}

# --- Build tools check ---
$HasBuildTools = 'false'
# On Windows, check for Visual Studio Build Tools (needed for native modules)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $HasBuildTools = 'true'
} elseif (Get-Command cl.exe -ErrorAction SilentlyContinue) {
    $HasBuildTools = 'true'
}
Write-Log "Build tools: $HasBuildTools"

# --- Status ---
$Status = 'success'
if ($NodeOK -eq 'false') { $Status = 'node_missing' }
elseif ($DepsOK -eq 'false') { $Status = 'deps_failed' }
elseif ($NativeOK -eq 'false') { $Status = 'native_failed' }

@"
=== NANOCLAW SETUP: BOOTSTRAP ===
PLATFORM: $Platform
IS_WSL: $IsWSL
IS_ROOT: $IsRoot
NODE_VERSION: $NodeVersion
NODE_OK: $NodeOK
NODE_PATH: $NodePathFound
DEPS_OK: $DepsOK
NATIVE_OK: $NativeOK
HAS_BUILD_TOOLS: $HasBuildTools
STATUS: $Status
LOG: logs/setup.log
=== END ===
"@

Write-Log "=== Bootstrap completed: $Status ==="

if ($NodeOK -eq 'false') { exit 2 }
if ($DepsOK -eq 'false' -or $NativeOK -eq 'false') { exit 1 }
