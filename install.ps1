#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Remove)
$ErrorActionPreference = 'Stop'

# Instala (o retira) los comandos claude-qwen para el usuario actual de Windows.
# - La app se copia a %LOCALAPPDATA%\ClaudeQwenEnterprise\app para que los
#   comandos sigan funcionando aunque esta carpeta se mueva o se borre.
# - Los shims (.cmd) se crean en %USERPROFILE%\.local\bin, carpeta que se
#   agrega al PATH de usuario si aun no esta.
# - Aqui no se guarda ninguna API key: cada persona registra la suya con
#   claude-qwen-auth (Windows Credential Manager).

$bin       = Join-Path $env:USERPROFILE '.local\bin'
$appDir    = Join-Path $env:LOCALAPPDATA 'ClaudeQwenEnterprise\app'
$appScript = Join-Path $appDir 'claude-qwen.ps1'
$appFiles  = @('claude-qwen.ps1','test-qwen.ps1','install.ps1','qwen-settings.json','qwen-agents.json')
$names = [ordered]@{
  'claude-qwen.cmd'        = 'launch'
  'claude-qwen-fast.cmd'   = 'fast'
  'claude-qwen-auth.cmd'   = 'auth'
  'claude-qwen-status.cmd' = 'status'
  'claude-qwen-test.cmd'   = 'test'
}

if (-not $Remove) {
  # --- copiar la app a una ubicacion estable ---
  foreach ($file in ($appFiles + 'agents')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) { throw "Falta un elemento del proyecto: $file" }
  }
  $agentsSrc = Join-Path $PSScriptRoot 'agents'
  New-Item -ItemType Directory -Path $appDir -Force | Out-Null
  foreach ($file in $appFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $appDir $file) -Force
  }
  $agentsApp = Join-Path $appDir 'agents'
  New-Item -ItemType Directory -Path $agentsApp -Force | Out-Null
  Copy-Item -Path (Join-Path $agentsSrc '*.md') -Destination $agentsApp -Force
  $configAgents = Join-Path $env:LOCALAPPDATA 'ClaudeQwenEnterprise\claude-config\agents'
  New-Item -ItemType Directory -Path $configAgents -Force | Out-Null
  Copy-Item -Path (Join-Path $agentsSrc '*.md') -Destination $configAgents -Force

  # --- garantizar la carpeta de shims y el PATH de usuario ---
  if (-not (Test-Path -LiteralPath $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
  $segments = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })
  $pathAdded = $segments -notcontains $bin
  if ($pathAdded) {
    [Environment]::SetEnvironmentVariable('Path', (($segments + $bin) -join ';'), 'User')
  }
}

# --- shims (.cmd) ---
foreach ($name in $names.Keys) {
  $path = Join-Path $bin $name
  if (Test-Path -LiteralPath $path) {
    $current = Get-Content -LiteralPath $path -Raw
    if ($current -notmatch 'claude-qwen\.ps1') { throw "No se reemplaza un comando ajeno: $path" }
  }
  if ($Remove) {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    continue
  }
  $body = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$appScript`" $($names[$name]) %*`r`nexit /b %ERRORLEVEL%`r`n"
  if ((Test-Path -LiteralPath $path) -and ((Get-Content -LiteralPath $path -Raw) -eq $body)) { continue }
  if (Test-Path -LiteralPath $path) {
    Copy-Item -LiteralPath $path -Destination "$path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  }
  Set-Content -LiteralPath $path -Value $body -Encoding Ascii -NoNewline
}

if ($Remove) {
  if (Test-Path -LiteralPath $appDir) { Remove-Item -LiteralPath $appDir -Recurse -Force }
  Write-Host 'Comandos claude-qwen retirados y copia de la app eliminada.'
  Write-Host 'Los datos de sesion (claude-config) y la credencial guardada no se tocaron.'
  Write-Host 'Para borrar tambien la clave: Administrador de credenciales de Windows, destino Codex/ClaudeQwenEnterprise/AlibabaSingapore.'
  exit 0
}

if (-not (Get-Command claude.exe -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath (Join-Path $bin 'claude.exe'))) {
  Write-Warning 'No se encontro claude.exe. Instala Claude Code primero: powershell -NoProfile -Command "irm https://claude.ai/install.ps1 | iex"'
}
if ($pathAdded) { Write-Host "Se agrego $bin al PATH de usuario." }
Write-Host 'Comandos claude-qwen instalados.'
Write-Host ''
Write-Host 'Pasos siguientes:'
Write-Host '  1. Abre una ventana NUEVA de PowerShell (para refrescar el PATH).'
Write-Host '  2. claude-qwen-status    (comprobacion local, sin llamadas a la API)'
Write-Host '  3. claude-qwen-auth      (pega TU clave empresarial en el aviso oculto)'
Write-Host '  4. claude-qwen           (inicia una sesion con qwen3.8-max)'
