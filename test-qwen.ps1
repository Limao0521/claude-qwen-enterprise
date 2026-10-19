param(
  [Parameter(Mandatory)][string]$ClaudeExecutable,
  [Parameter(Mandatory)][string]$SettingsPath,
  [Parameter(Mandatory)][string]$AgentsArgument,
  [Parameter(Mandatory)][string]$Endpoint
)
$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()
$testDir = Join-Path $env:TEMP ("claude-qwen-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null

function Add-Result([string]$name, [string]$state, [string]$note) {
  $results.Add([pscustomobject]@{ Check = $name; State = $state; Note = $note })
}
function Send-Message([object[]]$messages, [object[]]$tools = @(), [object]$toolChoice = $null) {
  $body = @{
    model = 'qwen3.8-flash'
    max_tokens = 96
    messages = $messages
  }
  if ($tools.Count -gt 0) { $body.tools = $tools }
  if ($null -ne $toolChoice) { $body.tool_choice = $toolChoice }
  $headers = @{
    'x-api-key' = $env:ANTHROPIC_API_KEY
    'anthropic-version' = '2023-06-01'
    'Content-Type' = 'application/json'
  }
  return Invoke-RestMethod -Uri "$Endpoint/v1/messages" -Method Post -Headers $headers -Body ($body | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 90
}
function Find-AgentIds([object]$node, [System.Collections.Generic.HashSet[string]]$ids, [System.Collections.Generic.HashSet[string]]$names) {
  if ($node -is [pscustomobject]) {
    if ($node.type -eq 'tool_use' -and $node.name) {
      $null = $names.Add([string]$node.name)
      if ($node.name -eq 'Agent' -and $node.id) { $null = $ids.Add([string]$node.id) }
    }
    foreach ($property in $node.PSObject.Properties) { Find-AgentIds $property.Value $ids $names }
  } elseif ($node -is [array]) {
    foreach ($item in $node) { Find-AgentIds $item $ids $names }
  }
}
function Invoke-Claude([string]$prompt, [int]$turns = 6) {
  $priorPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = & $ClaudeExecutable --strict-mcp-config --setting-sources user --settings $SettingsPath --agents $AgentsArgument --model qwen3.8-flash --print --output-format stream-json --verbose --no-session-persistence --max-turns $turns --allowedTools 'Read,Write,Bash,Agent' --permission-mode dontAsk $prompt 2>&1
    $exit = $LASTEXITCODE
  } finally { $ErrorActionPreference = $priorPreference }
  $lines = @($raw | ForEach-Object { [string]$_ })
  $ids = [System.Collections.Generic.HashSet[string]]::new()
  $names = [System.Collections.Generic.HashSet[string]]::new()
  $availableAgent = $false
  $finalResult = ''
  foreach ($line in $lines) {
    try {
      $event = $line | ConvertFrom-Json -ErrorAction Stop
      Find-AgentIds $event $ids $names
      if ($event.type -eq 'system' -and $event.subtype -eq 'init') { $availableAgent = (@($event.tools) -contains 'Agent') }
      if ($event.type -eq 'result' -and $event.result) { $finalResult = [string]$event.result }
    } catch { }
  }
  $preview = ($finalResult -replace 'sk-[^\s\"]+', '<redacted>')
  if ($preview.Length -gt 320) { $preview = $preview.Substring(0, 320) }
  return [pscustomobject]@{ ExitCode = $exit; AgentCalls = $ids.Count; AgentAvailable = $availableAgent; ToolNames = (@($names) -join ','); ResultPreview = $preview; Raw = ($lines -join "`n") }
}

try {
  try {
    $text = Send-Message @(@{ role='user'; content='Reply with PONG only.' })
    if (@($text.content | Where-Object { $_.type -eq 'text' -and -not [string]::IsNullOrWhiteSpace($_.text) }).Count -gt 0) {
      Add-Result 'Anthropic Messages authentication and text' 'PASS' 'Authenticated Messages response received.'
    } else {
      $types = (@($text.content | ForEach-Object { $_.type }) -join ',')
      Add-Result 'Anthropic Messages authentication and text' 'FAIL' ("No text content; content types=$types; stop_reason=$($text.stop_reason); output_tokens=$($text.usage.output_tokens)")
    }
  } catch {
    Add-Result 'Anthropic Messages authentication and text' 'FAIL' ("HTTP or protocol error: " + $_.Exception.GetType().Name)
  }
  if ($results[$results.Count - 1].State -eq 'FAIL') {
    Add-Result 'Remaining endpoint and Claude Code checks' 'UNVERIFIED' 'Stopped after the initial connection failure.'
    $results | Format-Table -AutoSize
    exit 1
  }

  $toolUse = $null
  $tool = @{ name='echo_value'; description='Echo an integer'; input_schema=@{ type='object'; properties=@{ value=@{ type='integer' } }; required=@('value') } }
  try {
    $toolUse = Send-Message @(@{ role='user'; content='Call echo_value with value 7.' }) @($tool) @{ type='tool'; name='echo_value' }
    $call = @($toolUse.content | Where-Object { $_.type -eq 'tool_use' -and $_.name -eq 'echo_value' }) | Select-Object -First 1
    if ($call) { Add-Result 'Tool-use request' 'PASS' 'tool_use block returned.' }
    else { Add-Result 'Tool-use request' 'FAIL' 'No tool_use block returned.' }
  } catch {
    Add-Result 'Tool-use request' 'FAIL' ("HTTP or protocol error: " + $_.Exception.GetType().Name)
  }
  if ($call) {
    try {
      $next = Send-Message @(
        @{ role='user'; content='Call echo_value with value 7, then say done.' },
        @{ role='assistant'; content=$toolUse.content },
        @{ role='user'; content=@(@{ type='tool_result'; tool_use_id=$call.id; content='7' }) }
      )
      if (@($next.content | Where-Object { $_.type -eq 'text' }).Count -gt 0) {
        Add-Result 'Multi-turn tool result' 'PASS' 'Continuation returned text.'
      } else { Add-Result 'Multi-turn tool result' 'FAIL' 'No continuation text.' }
    } catch {
      Add-Result 'Multi-turn tool result' 'FAIL' ("HTTP or protocol error: " + $_.Exception.GetType().Name)
    }
  } else { Add-Result 'Multi-turn tool result' 'UNVERIFIED' 'Tool-use request did not pass.' }

  Set-Content -LiteralPath (Join-Path $testDir 'input.txt') -Value 'QWEN-SMOKE-731' -NoNewline
  Push-Location $testDir
  try {
    $harness = Invoke-Claude 'Use Read to inspect input.txt. Use Write to create output.txt containing exactly QWEN-SMOKE-731. Use Bash to run a harmless PowerShell command that creates command.txt containing exactly COMMAND-OK. Then reply done.' 7
    if ($harness.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $testDir 'output.txt')) -and (Get-Content -LiteralPath (Join-Path $testDir 'output.txt') -Raw) -match 'QWEN-SMOKE-731') {
      Add-Result 'Claude Code read and write tools' 'PASS' 'Output file contains expected marker.'
    } else { Add-Result 'Claude Code read and write tools' 'FAIL' 'Expected output file not created.' }
    if ($harness.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $testDir 'command.txt')) -and (Get-Content -LiteralPath (Join-Path $testDir 'command.txt') -Raw) -match 'COMMAND-OK') {
      Add-Result 'Claude Code terminal tool' 'PASS' 'Terminal command created expected marker.'
    } else { Add-Result 'Claude Code terminal tool' 'FAIL' 'Expected command marker not created.' }

    $one = Invoke-Claude 'Invoke the qwen-explorer subagent to read input.txt and report its exact marker. Do not read the file yourself. Return the subagent result.' 5
    if ($one.ExitCode -eq 0 -and $one.AgentCalls -ge 1 -and $one.Raw -match 'QWEN-SMOKE-731') {
      Add-Result 'One Qwen subagent' 'PASS' 'Agent tool invocation was observed.'
    } else { Add-Result 'One Qwen subagent' 'FAIL' ("No Agent tool invocation; exit=$($one.ExitCode); available=$($one.AgentAvailable); tools=$($one.ToolNames); result=$($one.ResultPreview)") }

    $two = Invoke-Claude 'Start exactly two independent qwen-explorer subagents concurrently. Agent one reads input.txt; agent two lists files in this directory. Wait for both and summarize. Do not spawn any other agents.' 6
    if ($two.ExitCode -eq 0 -and $two.AgentCalls -ge 2) {
      Add-Result 'Two subagent invocations' 'PASS' 'Two Agent tool invocation events were observed.'
      Add-Result 'Concurrent overlap' 'UNVERIFIED' 'Event overlap requires manual inspection or provider telemetry.'
    } else {
      Add-Result 'Two subagent invocations' 'FAIL' ("Fewer than two Agent invocation events; exit=$($two.ExitCode); available=$($two.AgentAvailable); calls=$($two.AgentCalls); tools=$($two.ToolNames); result=$($two.ResultPreview)")
      Add-Result 'Concurrent overlap' 'UNVERIFIED' 'Two successful invocations are required first.'
    }
  } finally { Pop-Location }
} finally {
  # The test directory contains only generated markers and CLI transient data.
  $resolved = [IO.Path]::GetFullPath($testDir)
  $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and ([IO.Path]::GetFileName($resolved) -match '^claude-qwen-smoke-[0-9a-f]{32}$') -and (Test-Path -LiteralPath $resolved)) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

$results | Format-Table -AutoSize -Wrap
if (@($results | Where-Object State -eq 'FAIL').Count -gt 0) { exit 1 }
exit 0
