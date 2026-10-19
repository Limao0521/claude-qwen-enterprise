param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$bin = Join-Path $env:USERPROFILE '.local\bin'
$names = @{
  'claude-qwen.cmd' = 'launch'
  'claude-qwen-fast.cmd' = 'fast'
  'claude-qwen-auth.cmd' = 'auth'
  'claude-qwen-status.cmd' = 'status'
  'claude-qwen-test.cmd' = 'test'
}
$script = Join-Path $PSScriptRoot 'claude-qwen.ps1'
if (-not (Test-Path -LiteralPath $bin)) { throw "PATH directory missing: $bin" }
foreach ($name in $names.Keys) {
  $path = Join-Path $bin $name
  if (Test-Path -LiteralPath $path) {
    $current = Get-Content -LiteralPath $path -Raw
    if ($current -notmatch [regex]::Escape($script)) {
      throw "Refusing to replace unrelated command: $path"
    }
    $backup = "$path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $path -Destination $backup
  }
  if ($Remove) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    continue
  }
  $body = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`" $($names[$name]) %*`r`nexit /b %ERRORLEVEL%`r`n"
  Set-Content -LiteralPath $path -Value $body -Encoding Ascii -NoNewline
}
if (-not $Remove) {
  $config = Join-Path $env:LOCALAPPDATA 'ClaudeQwenEnterprise\claude-config'
  $agents = Join-Path $config 'agents'
  New-Item -ItemType Directory -Path $agents -Force | Out-Null
  foreach ($agent in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'agents') -Filter '*.md' -File) {
    $target = Join-Path $agents $agent.Name
    if (Test-Path -LiteralPath $target) {
      $backup = "$target.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
      Copy-Item -LiteralPath $target -Destination $backup
    }
    Copy-Item -LiteralPath $agent.FullName -Destination $target
  }
  Write-Host 'Qwen commands installed. Run claude-qwen-status, then claude-qwen-auth.'
} else {
  Write-Host 'Qwen command shims removed. Runtime data and credentials were left intact.'
}
