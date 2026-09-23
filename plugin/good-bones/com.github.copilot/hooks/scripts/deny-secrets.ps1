<#
.SYNOPSIS
    preToolUse hook: deny any tool call that would write a credential into
    this repo - deterministic, no model involved.

.DESCRIPTION
    Pattern set adapted from the secret-scan hook in
    ms-mfg-community/day-in-the-life-copilot-lab
    (scripts/hooks/pre-tool-use-secret-scan.ps1), rewritten for the payload
    shapes this CLI actually sends (see demos/captures/hook-payloads.md in
    the talk repo):

    - The lab's version reads toolArgs.content / toolArgs.new_string and only
      checks the create/edit/write tools. This CLI edits files with
      apply_patch, whose toolArgs is a *raw patch string*, and its create /
      edit tools use file_text / new_str. Run offline against those shapes,
      the lab's version allows every one of them.
    - This version inspects every mutating tool: shell commands
      (powershell/bash), apply_patch (only lines being ADDED, so unchanged
      context never false-positives), and create/edit (file_text, new_str,
      else the whole stringified toolArgs).

    VS Code's Local agent sends its own payload shape; hook-compat.ps1 maps
    it onto the CLI's and answers in VS Code's format.

    Like deny-newtonsoft.ps1, it ALLOWS on any unparseable payload rather
    than risk blocking unrelated tool calls live; the guarantee comes from
    scripts/hooks/test-hooks.ps1 exercising it offline.
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
    Write-Decision '{}'
}

$toolName = [string]$payload.toolName
$mutatingTools = @('powershell', 'bash', 'apply_patch', 'edit', 'create')

if ($toolName -notin $mutatingTools) {
    Write-Decision '{}'
}

switch ($toolName) {
    { $_ -in @('powershell', 'bash') } {
        $candidate = [string]$payload.toolArgs.command
    }
    'apply_patch' {
        $patchText = if ($payload.toolArgs -is [string]) { $payload.toolArgs } else { $payload.toolArgs | ConvertTo-Json -Depth 10 }
        # Only lines actually being added by the patch (leading '+', not '+++').
        $candidate = (($patchText -split "`n") | Where-Object { $_ -match '^\+[^+]' -or $_ -eq '+' }) -join "`n"
    }
    default {
        $candidate = $payload.toolArgs.file_text
        if (-not $candidate) { $candidate = $payload.toolArgs.new_str }
        if (-not $candidate) { $candidate = $payload.toolArgs | ConvertTo-Json -Depth 10 }
        $candidate = [string]$candidate
    }
}

# Ordered: the first match names the finding in the denial reason.
$patterns = [ordered]@{
    'private key'                = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'Azure Storage account key'  = '(?i)AccountKey=[A-Za-z0-9+/]{40,}={0,2}'
    'Azure shared access key'    = '(?i)SharedAccessKey=[A-Za-z0-9+/]{30,}={0,2}'
    'AWS access key ID'          = '(?<![A-Z0-9])(AKIA|ASIA)[0-9A-Z]{16}(?![A-Z0-9])'
    'GitHub token'               = '\b(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})'
    'API key (sk-...)'           = '\bsk-[A-Za-z0-9_-]{20,}'
    'connection-string password' = '(?i)\b(Password|Pwd)=[^;"''\s]{8,}'
}

foreach ($name in $patterns.Keys) {
    # Case-sensitive by default (key prefixes like AKIA/ghp_ are exact);
    # patterns that start with (?i) opt into case-insensitivity inline.
    if ($candidate -cmatch $patterns[$name]) {
        $reason = "Possible $name in this $($payload.displayName) call. Secrets never go in source: use ``dotnet user-secrets`` locally and Key Vault or managed identity in Azure. Blocked by the good-bones plugin (deny-secrets.ps1)."
        $decision = [ordered]@{
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
        Write-HookResult -Payload $payload -Fields $decision
    }
}

Write-Decision '{}'
