param(
  [ValidateSet('launch','fast','auth','status','test','selftest')][string]$Mode = 'launch',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$ForwardArgs
)

$ErrorActionPreference = 'Stop'
$target = 'Codex/ClaudeQwenEnterprise/AlibabaSingapore'
$runtime = Join-Path $env:LOCALAPPDATA 'ClaudeQwenEnterprise'
$config = Join-Path $runtime 'claude-config'
$settings = Join-Path $PSScriptRoot 'qwen-settings.json'
$agents = Join-Path $PSScriptRoot 'qwen-agents.json'
$endpoint = 'https://llm-kcqiiw0if0n8a3fc.ap-southeast-1.maas.aliyuncs.com/apps/anthropic'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct QwenCredential {
    public UInt32 Flags;
    public UInt32 Type;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
    [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
    public Int64 LastWritten;
    public UInt32 CredentialBlobSize;
    public IntPtr CredentialBlob;
    public UInt32 Persist;
    public UInt32 AttributeCount;
    public IntPtr Attributes;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
    [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
}

public static class QwenCredMan {
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredWriteW")]
    public static extern bool Write(ref QwenCredential credential, UInt32 flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredReadW")]
    public static extern bool Read(string target, UInt32 type, UInt32 flags, out IntPtr credential);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredDeleteW")]
    public static extern bool Delete(string target, UInt32 type, UInt32 flags);
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern void CredFree(IntPtr credential);
}
'@

function Read-Key {
  $ptr = [IntPtr]::Zero
  if (-not [QwenCredMan]::Read($target, 1, 0, [ref]$ptr)) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($code -eq 1168) { return $null }
    throw "Windows Credential Manager read failed (error $code)."
  }
  try {
    $entry = [Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][QwenCredential])
    $bytes = New-Object byte[] $entry.CredentialBlobSize
    [Runtime.InteropServices.Marshal]::Copy($entry.CredentialBlob, $bytes, 0, $bytes.Length)
    try { return [Text.Encoding]::UTF8.GetString($bytes) }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
  } finally {
    [QwenCredMan]::CredFree($ptr)
  }
}

function Save-Key([string]$key) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($key)
  $blob = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
  try {
    [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $blob, $bytes.Length)
    $entry = [QwenCredential]::new()
    $entry.Type = 1
    $entry.TargetName = $target
    $entry.UserName = 'qwen-enterprise'
    $entry.CredentialBlobSize = [uint32]$bytes.Length
    $entry.CredentialBlob = $blob
    $entry.Persist = 2
    if (-not [QwenCredMan]::Write([ref]$entry, 0)) {
      $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      throw "Windows Credential Manager write failed (error $code)."
    }
  } finally {
    [Array]::Clear($bytes, 0, $bytes.Length)
    for ($i = 0; $i -lt $entry.CredentialBlobSize; $i++) {
      [Runtime.InteropServices.Marshal]::WriteByte($blob, $i, 0)
    }
    [Runtime.InteropServices.Marshal]::FreeHGlobal($blob)
  }
}

function Remove-Key {
  if (-not [QwenCredMan]::Delete($target, 1, 0)) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($code -ne 1168) { throw "Windows Credential Manager delete failed (error $code)." }
  }
}

function Test-KeyPresent {
  $ptr = [IntPtr]::Zero
  if ([QwenCredMan]::Read($target, 1, 0, [ref]$ptr)) {
    [QwenCredMan]::CredFree($ptr)
    return $true
  }
  $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  if ($code -eq 1168) { return $false }
  throw "Windows Credential Manager status failed (error $code)."
}

if ($Mode -eq 'selftest') {
  $target = 'Codex/ClaudeQwenEnterprise/SelfTest/' + [guid]::NewGuid().ToString('N')
  try {
    Save-Key 'dummy-test-only-731'
    if ((Read-Key) -ne 'dummy-test-only-731') { throw 'Credential Manager round trip failed.' }
    Write-Host 'Credential Manager round trip passed.'
  } finally { Remove-Key }
  exit 0
}

if ($Mode -eq 'auth') {
  if ($ForwardArgs -contains '--delete' -or $ForwardArgs -contains '-Delete') {
    Remove-Key
    Write-Host 'Enterprise credential deleted.'
    exit 0
  }
  $secure = Read-Host 'Alibaba Model Studio API key' -AsSecureString
  if ($secure.Length -lt 8) { throw 'Key is missing or too short.' }
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    Save-Key $plain
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $plain = $null
    $secure.Dispose()
  }
  Write-Host 'Enterprise credential stored in Windows Credential Manager.'
  exit 0
}

if ($Mode -eq 'status') {
  $cli = Get-Command claude.exe -ErrorAction SilentlyContinue
  [pscustomobject]@{
    ClaudeExecutable = if ($cli) { $cli.Source } else { '<missing>' }
    ClaudeVersion = if ($cli) { (& $cli.Source --version) } else { '<missing>' }
    Endpoint = $endpoint
    ConfigDirectory = $config
    CredentialPresent = (Test-KeyPresent)
    Primary = 'qwen3.8-max'
    Fast = 'qwen3.8-flash'
    SubagentDefault = 'qwen3.7-plus'
    AgentFiles = if (Test-Path -LiteralPath (Join-Path $config 'agents')) { @(Get-ChildItem -LiteralPath (Join-Path $config 'agents') -Filter '*.md' -File).Count } else { 0 }
  } | Format-List
  exit 0
}

if ($ForwardArgs | Where-Object { $_ -match '^--(settings|setting-sources|fallback-model)(=|$)' }) {
  throw 'These overrides are blocked in the Qwen launcher to keep provider routing explicit.'
}
if (-not (Test-KeyPresent)) {
  Write-Host 'No enterprise key enrolled. Run claude-qwen-auth in an interactive PowerShell terminal.'
  exit 2
}
if (-not (Test-Path -LiteralPath $settings)) { throw 'Qwen settings file is missing.' }
if (-not (Test-Path -LiteralPath $agents)) { throw 'Qwen agents file is missing.' }
$parsed = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
if ($parsed.env.ANTHROPIC_BASE_URL -ne $endpoint) { throw 'Qwen endpoint in settings does not match the pinned enterprise endpoint.' }
$agentsJson = Get-Content -LiteralPath $agents -Raw
$agentsObject = $agentsJson | ConvertFrom-Json
# Windows PowerShell 5.1 strips nested quotes when passing a JSON string to a
# native executable. Escaping quotes and JSON-encoding spaces preserves one arg.
$agentsArgument = ($agentsObject | ConvertTo-Json -Depth 20 -Compress).Replace(' ', '\u0020').Replace('"', '\"')
New-Item -ItemType Directory -Path $config -Force | Out-Null
$cli = (Get-Command claude.exe -ErrorAction Stop).Source

# This launcher runs in a separate powershell.exe process. Restore its own prior
# environment anyway so nested callers do not retain the enterprise key.
$changed = @{}
foreach ($item in Get-ChildItem Env: | Where-Object { $_.Name -like 'ANTHROPIC_*' -or $_.Name -like 'CLAUDE_CODE_USE_*' -or $_.Name -in @('CLAUDE_CONFIG_DIR','CLAUDE_CODE_OAUTH_TOKEN','CLAUDE_CODE_OAUTH_REFRESH_TOKEN','DISABLE_LOGIN_COMMAND','DISABLE_LOGOUT_COMMAND') }) {
  $changed[$item.Name] = $item.Value
  Remove-Item -Path "Env:$($item.Name)"
}
try {
  $env:CLAUDE_CONFIG_DIR = $config
  $env:ANTHROPIC_BASE_URL = $endpoint
  $env:ANTHROPIC_API_KEY = Read-Key
  if ([string]::IsNullOrEmpty($env:ANTHROPIC_API_KEY)) { throw 'Enterprise credential is empty.' }
  $env:ANTHROPIC_MODEL = if ($Mode -eq 'fast') { 'qwen3.8-flash' } else { 'qwen3.8-max' }
  $env:DISABLE_LOGIN_COMMAND = '1'
  $env:DISABLE_LOGOUT_COMMAND = '1'
  if ($Mode -eq 'test') {
    & (Join-Path $PSScriptRoot 'test-qwen.ps1') -ClaudeExecutable $cli -SettingsPath $settings -AgentsArgument $agentsArgument -Endpoint $endpoint
  } else {
    & $cli --strict-mcp-config --setting-sources user --settings $settings --agents $agentsArgument --model $env:ANTHROPIC_MODEL @ForwardArgs
  }
  exit $LASTEXITCODE
} finally {
  foreach ($name in @('CLAUDE_CONFIG_DIR','ANTHROPIC_BASE_URL','ANTHROPIC_API_KEY','ANTHROPIC_MODEL','DISABLE_LOGIN_COMMAND','DISABLE_LOGOUT_COMMAND')) {
    Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
  }
  foreach ($name in $changed.Keys) { Set-Item -Path "Env:$name" -Value $changed[$name] }
}
