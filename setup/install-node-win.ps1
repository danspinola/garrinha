#Requires -Version 5.1
<#
.SYNOPSIS
  Install Node.js 22 LTS on Windows.
  Tries winget first, then chocolatey, then direct MSI download.
#>
$ErrorActionPreference = 'Stop'

Write-Output '=== NANOCLAW SETUP: INSTALL_NODE ==='

$nodeBin = Get-Command node -ErrorAction SilentlyContinue
if ($nodeBin) {
    $version = & node --version 2>$null
    Write-Output "STATUS: already-installed"
    Write-Output "NODE_VERSION: $version"
    Write-Output '=== END ==='
    exit 0
}

# Try winget
$wingetBin = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetBin) {
    Write-Output 'STEP: winget-install-node'
    & winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent 2>&1
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $nodeBin = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeBin) {
        $version = & node --version 2>$null
        Write-Output "STATUS: installed"
        Write-Output "NODE_VERSION: $version"
        Write-Output '=== END ==='
        exit 0
    }
}

# Try chocolatey
$chocoBin = Get-Command choco -ErrorAction SilentlyContinue
if ($chocoBin) {
    Write-Output 'STEP: choco-install-node'
    & choco install nodejs-lts -y 2>&1
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $nodeBin = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeBin) {
        $version = & node --version 2>$null
        Write-Output "STATUS: installed"
        Write-Output "NODE_VERSION: $version"
        Write-Output '=== END ==='
        exit 0
    }
}

# Direct download fallback
Write-Output 'STEP: direct-download-node'
$arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
$msiUrl = "https://nodejs.org/dist/v22.16.0/node-v22.16.0-$arch.msi"
$msiPath = Join-Path $env:TEMP 'node-install.msi'

Write-Output "Downloading Node.js from $msiUrl ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

Write-Output 'Installing Node.js MSI...'
Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -NoNewWindow
Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

$nodeBin = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeBin) {
    Write-Output 'STATUS: failed'
    Write-Output 'ERROR: node not found on PATH after install'
    Write-Output '=== END ==='
    exit 1
}

$version = & node --version 2>$null
Write-Output "STATUS: installed"
Write-Output "NODE_VERSION: $version"
Write-Output '=== END ==='
