<#
.SYNOPSIS
    preToolUse hook: deny any tool call that would add Newtonsoft.Json / JsonConvert
    to this repo - deterministic, no model involved.

.DESCRIPTION
    Reads the preToolUse JSON payload from stdin: {sessionId, timestamp, cwd,
    toolName, toolArgs}. VS Code's Local agent sends its own shape instead;
    hook-compat.ps1 maps it onto this one and answers in VS Code's format.
    Only inspects tools that can mutate the repo (a shell command, or a file
    edit/create). Everything else is a fast no-op allow.

    - Shell tools (powershell/bash): deny if the command text mentions
      "Newtonsoft" (covers `dotnet add package Newtonsoft.Json`, nuget CLI,
      manual csproj edits via shell, etc).
    - apply_patch (this CLI's edit primitive): toolArgs is a *raw patch
      string*, not an object (confirmed empirically - see
      demos/captures/hook-payloads.md). Only lines that are actually being
      ADDED (prefixed with a literal "+") are checked, so the hook does not
      false-positive on unchanged context lines that still show the seeded
      `using Newtonsoft.Json;` / `JsonConvert.SerializeObject(...)` in
      Program.cs.
    - create / edit (generic file-mutation tool shapes): checks the new
      content field if present, else the whole stringified toolArgs.

    On any unexpected shape or parse failure this hook ALLOWS by default
    (returns {}) rather than risk randomly blocking unrelated tool calls
    during a live demo - the actual guarantee comes from this script being
    tested offline (scripts/hooks/test-hooks.ps1) against known payloads,
    not from an untested fail-closed crash path.
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-compat.ps1')

function Write-Decision {
    param([string]$Json)
    Write-Output $Json
    exit 0
}

try {
    $raw = [Console]::In.ReadToEnd()
    $payload = ConvertTo-CliPayload ($raw | ConvertFrom-Json -ErrorAction Stop)
} catch {
    # Can't understand the payload - allow rather than risk blocking the demo.
    Write-Decision '{}'
}

$toolName = [string]$payload.toolName
$mutatingTools = @('powershell', 'bash', 'apply_patch', 'edit', 'create')

if ($toolName -notin $mutatingTools) {
    Write-Decision '{}'
}

$pattern = 'Newtonsoft|JsonConvert'
$hit = $false

switch ($toolName) {
    { $_ -in @('powershell', 'bash') } {
        $command = [string]$payload.toolArgs.command
        if ($command -match $pattern) { $hit = $true }
    }
    'apply_patch' {
        $patchText = if ($payload.toolArgs -is [string]) { $payload.toolArgs } else { $payload.toolArgs | ConvertTo-Json -Depth 10 }
        # Only lines actually being added by the patch (leading '+', not '+++').
        $addedLines = ($patchText -split "`n") | Where-Object { $_ -match '^\+[^+]' -or $_ -eq '+' }
        foreach ($line in $addedLines) {
            if ($line -match $pattern) { $hit = $true; break }
        }
    }
    default {
        # create / edit - try the likely "new content" fields first, else fall
        # back to the whole stringified toolArgs.
        $candidate = $payload.toolArgs.file_text
        if (-not $candidate) { $candidate = $payload.toolArgs.new_str }
        if (-not $candidate) { $candidate = $payload.toolArgs | ConvertTo-Json -Depth 10 }
        if ([string]$candidate -match $pattern) { $hit = $true }
    }
}

if ($hit) {
    $reason = 'House rule (.github/copilot-instructions.md): this repo uses System.Text.Json, never Newtonsoft.Json/JsonConvert. Blocked by scripts/hooks/deny-newtonsoft.ps1 (L5 guardrail hook).'
    $decision = [ordered]@{
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    }
    Write-HookResult -Payload $payload -Fields $decision
}

Write-Decision '{}'
