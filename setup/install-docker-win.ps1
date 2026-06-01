#Requires -Version 5.1
<#
.SYNOPSIS
  Install Docker Desktop on Windows.
  Tries winget first, then chocolatey, then guides manual install.
#>
$ErrorActionPreference = 'Stop'

Write-Output '=== NANOCLAW SETUP: INSTALL_DOCKER ==='

$dockerBin = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerBin) {
    $version = & docker --version 2>$null
    Write-Output "STATUS: already-installed"
    Write-Output "DOCKER_VERSION: $version"
    Write-Output '=== END ==='
    exit 0
}

# Try winget
$wingetBin = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetBin) {
    Write-Output 'STEP: winget-install-docker'
    & winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent 2>&1
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $dockerBin = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerBin) {
        $version = & docker --version 2>$null
        Write-Output "STATUS: installed"
        Write-Output "DOCKER_VERSION: $version"
        Write-Output "NOTE: You may need to restart your computer and start Docker Desktop before continuing."
        Write-Output '=== END ==='
        exit 0
    }
}

# Try chocolatey
$chocoBin = Get-Command choco -ErrorAction SilentlyContinue
if ($chocoBin) {
    Write-Output 'STEP: choco-install-docker'
    & choco install docker-desktop -y 2>&1
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $dockerBin = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerBin) {
        $version = & docker --version 2>$null
        Write-Output "STATUS: installed"
        Write-Output "DOCKER_VERSION: $version"
        Write-Output "NOTE: You may need to restart your computer and start Docker Desktop before continuing."
        Write-Output '=== END ==='
        exit 0
    }
}

Write-Output 'STATUS: failed'
Write-Output 'ERROR: Could not install Docker Desktop automatically.'
Write-Output 'Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop/'
Write-Output 'After installing, restart your computer, start Docker Desktop, and re-run this setup.'
Write-Output '=== END ==='
exit 1
