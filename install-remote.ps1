#Requires -Version 5.1
# =============================================================================
#  Instalador de un solo comando - claude-qwen (Claude Code + Qwen Enterprise)
#
#  Uso (en PowerShell, desde cualquier carpeta):
#    powershell -NoProfile -Command "irm https://raw.githubusercontent.com/TU-USUARIO/claude-qwen-enterprise/main/install-remote.ps1 | iex"
#
#  ANTES DE PUBLICAR: edita $RepoOwner (y $RepoName/$RepoBranch si hace falta)
#  con la URL real del repositorio compartido.
# =============================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch { }

$RepoOwner  = 'TU-USUARIO'             # <-- EDITAR: usuario u organizacion de GitHub
$RepoName   = 'claude-qwen-enterprise'
$RepoBranch = 'main'

if ($RepoOwner -eq 'TU-USUARIO') {
  throw 'install-remote.ps1 still has the placeholder owner. Set $RepoOwner to the real GitHub user or organization, then publish again.'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$stamp = [guid]::NewGuid().ToString('N')
$zip   = Join-Path $env:TEMP "claude-qwen-$stamp.zip"
$src   = Join-Path $env:TEMP "claude-qwen-src-$stamp"
try {
  $url = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$RepoBranch.zip"
  Write-Host "Descargando $url"
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  Expand-Archive -LiteralPath $zip -DestinationPath $src -Force
  $project = Get-ChildItem -LiteralPath $src -Directory | Select-Object -First 1
  if (-not $project -or -not (Test-Path -LiteralPath (Join-Path $project.FullName 'install.ps1'))) {
    throw 'El archivo descargado no contiene install.ps1. Verifica la URL del repositorio y que el repo sea accesible para tu cuenta.'
  }
  & (Join-Path $project.FullName 'install.ps1')
} finally {
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
}
