<#
.SYNOPSIS
    Shared by the guardrail hooks so one script serves both Copilot CLI (and
    the Copilot app, which runs on its engine) and VS Code's Local agent.

.DESCRIPTION
    Both hosts load the same .github/hooks/guardrails.json. VS Code maps the
    Copilot format itself (agentStop -> Stop, powershell -> windows,
    bash -> linux/osx, timeoutSec -> timeout), but the two talk to the
    script differently:

      Copilot CLI  stdin {toolName, toolArgs, cwd, ...}
                   reads a top-level permissionDecision / additionalContext /
                   decision.
      VS Code      stdin {hook_event_name, tool_name, tool_input, cwd, ...}
                   reads those same fields only inside hookSpecificOutput,
                   and a hook that errors counts as deny (Stop: block).

    ConvertTo-CliPayload rewrites a VS Code payload into the CLI shapes the
    hooks already check, so their detection logic is the same for both
    hosts. Write-HookResult answers in whichever format the caller used.
    Verified against VS Code's bundled Copilot Chat 0.68.0 and the payloads
    in its "GitHub Copilot Chat Hooks" output log.
#>

function ConvertTo-CliPayload {
    param($Payload)

    if ($null -eq $Payload.hook_event_name) {
        $Payload | Add-Member -NotePropertyName hookHost -NotePropertyValue 'cli' -Force
        $Payload | Add-Member -NotePropertyName displayName -NotePropertyValue ([string]$Payload.toolName) -Force
        return $Payload
    }

    $name = [string]$Payload.tool_name
    $in = $Payload.tool_input
    $toolName = $name
    $toolArgs = $in
    switch ($name) {
        'run_in_terminal' {
            $toolName = 'powershell'
            $toolArgs = [pscustomobject]@{ command = [string]$in.command }
        }
        'apply_patch' {
            # Same "*** Begin Patch" text the CLI sends, wrapped in {input}.
            $toolName = 'apply_patch'
            $toolArgs = [string]$in.input
        }
        'create_file' {
            $toolName = 'create'
            $toolArgs = [pscustomobject]@{ path = [string]$in.filePath; file_text = [string]$in.content }
        }
        'replace_string_in_file' {
            $toolName = 'edit'
            $toolArgs = [pscustomobject]@{ path = [string]$in.filePath; new_str = [string]$in.newString }
        }
        'insert_edit_into_file' {
            $toolName = 'edit'
            $toolArgs = [pscustomobject]@{ path = [string]$in.filePath; new_str = [string]$in.code }
        }
        'edit_notebook_file' {
            $toolName = 'edit'
            $toolArgs = [pscustomobject]@{ path = [string]$in.filePath; new_str = [string]$in.newCode }
        }
        'multi_replace_string_in_file' {
            # One call can edit several files: check every new string, and
            # report a C# path if any of them is one (verify-build keys on it).
            $replacements = @($in.replacements)
            $paths = @($replacements | ForEach-Object { [string]$_.filePath })
            $csPath = $paths | Where-Object { $_ -match '\.(cs|csproj)$' } | Select-Object -First 1
            $toolName = 'edit'
            $toolArgs = [pscustomobject]@{
                path    = $(if ($csPath) { $csPath } elseif ($paths.Count) { $paths[0] } else { '' })
                new_str = ($replacements | ForEach-Object { [string]$_.newString }) -join "`n"
            }
        }
    }

    return [pscustomobject]@{
        hookHost         = 'vscode'
        hookEventName    = [string]$Payload.hook_event_name
        displayName      = $name
        toolName         = $toolName
        toolArgs         = $toolArgs
        cwd              = [string]$Payload.cwd
        sessionId        = [string]$Payload.session_id
        stop_hook_active = [bool]$Payload.stop_hook_active
    }
}

function Write-HookResult {
    # $Fields is the result in Copilot CLI's top-level shape; $null means no
    # opinion. Exits the hook script.
    param($Payload, [System.Collections.IDictionary]$Fields)

    if (-not $Fields) {
        Write-Output '{}'
        exit 0
    }
    if ($Payload.hookHost -eq 'vscode') {
        $specific = [ordered]@{ hookEventName = $Payload.hookEventName }
        foreach ($key in $Fields.Keys) { $specific[$key] = $Fields[$key] }
        $Fields = [ordered]@{ hookSpecificOutput = $specific }
    }
    Write-Output ($Fields | ConvertTo-Json -Compress -Depth 5)
    exit 0
}
