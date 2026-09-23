<#
.SYNOPSIS
    postToolUse hook: after an edit/create touching *.cs or *.csproj, run
    `dotnet build` PLUS the bundled strict-format check (adopted from
    BenjaminMichaelis/DotnetTemplates, see the plugin README) and surface
    the first failures as additionalContext - deterministic, no model
    involved.

.DESCRIPTION
    Reads the postToolUse JSON payload from stdin: {sessionId, timestamp,
    cwd, toolName, toolArgs, toolResult}; VS Code's Local agent sends its own
    shape, which hook-compat.ps1 maps onto this one (and answers in VS Code's
    format). Only runs when the mutated path
    looks like C# source or a project file, so unrelated edits (README,
    notes, JSON config) don't pay the cost. From the reported `cwd` it runs,
    in order:
      1. `dotnet build --nologo -v q`
      2. Invoke-DotNetFormatStrict.ps1 -DiscoverFromCurrentDirectory
         (whitespace/style/analyzer format-verification, `--verify-no-changes`),
         bundled in this same scripts/ folder (plugin package is flat).
    Both are run every time (not short-circuited) so a single postToolUse
    turn surfaces every deterministic failure at once. Output is capped well
    under the docs' 10KB additionalContext join limit. The build output
    remains the primary, deterministic proof artifact used by this repo's
    verification captures; the format check is additive.
#>

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-compat.ps1')

function Write-Output-And-Exit {
    param([string]$Json)
    Write-Output $Json
    exit 0
}

try {
    $raw = [Console]::In.ReadToEnd()
    $payload = ConvertTo-CliPayload ($raw | ConvertFrom-Json -ErrorAction Stop)
} catch {
    Write-Output-And-Exit '{}'
}

$toolName = [string]$payload.toolName
$mutatingTools = @('apply_patch', 'edit', 'create')

if ($toolName -notin $mutatingTools) {
    Write-Output-And-Exit '{}'
}

# Figure out whether a .cs/.csproj file was touched, so we skip the build for
# unrelated edits (README, notes, JSON, etc).
$touchesCsFile = $false
switch ($toolName) {
    'apply_patch' {
        $patchText = if ($payload.toolArgs -is [string]) { $payload.toolArgs } else { [string]($payload.toolArgs | ConvertTo-Json -Depth 10) }
        if ($patchText -match '(?im)^\*\*\*\s+(Update|Add|Delete) File:.*\.(cs|csproj)\s*$') { $touchesCsFile = $true }
    }
    default {
        $path = [string]$payload.toolArgs.path
        if ($path -match '\.(cs|csproj)$') { $touchesCsFile = $true }
    }
}

if (-not $touchesCsFile) {
    Write-Output-And-Exit '{}'
}

$cwd = [string]$payload.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }

Push-Location $cwd
try {
    # A non-zero-exit external command is expected, meaningful data here,
    # not a script bug -- but under Windows PowerShell (powershell.exe,
    # which is how the CLI actually spawns a "powershell" hook script) a
    # native command's stderr output becomes a TERMINATING error when
    # $ErrorActionPreference = 'Stop' is in effect, unwinding the whole
    # script with empty stdout. Invoke-DotNetFormatStrict.ps1 sets its own
    # 'Stop' internally (copied as-is, not modified), so `dotnet format`
    # finding a violation throws from inside it regardless of our own
    # preference. Catch around each external call and fall back to the
    # exception's message (which already contains the real error text) so
    # a finding always becomes data, never an aborted hook.
    $buildExitCode = 0
    try {
        $buildOutput = & dotnet build --nologo -v q 2>&1 | Out-String
        $buildExitCode = $LASTEXITCODE
    } catch {
        $buildOutput = $_.Exception.Message
        $buildExitCode = 1
    }

    # Plugin package layout is flat: Invoke-DotNetFormatStrict.ps1 ships
    # alongside this script (see plugin/good-bones/README.md layout), unlike
    # the repo's own .github/scripts/ location.
    $formatScript = Join-Path $PSScriptRoot 'Invoke-DotNetFormatStrict.ps1'
    $formatExitCode = 0
    try {
        $formatOutput = & $formatScript -DiscoverFromCurrentDirectory 2>&1 | Out-String
        $formatExitCode = $LASTEXITCODE
    } catch {
        $formatOutput = $_.Exception.Message
        $formatExitCode = 1
    }
} finally {
    Pop-Location
}

$maxLen = 8000
$sections = [System.Collections.Generic.List[string]]::new()

if ($buildExitCode -ne 0) {
    $trimmed = if ($buildOutput.Length -gt $maxLen) { $buildOutput.Substring(0, $maxLen) + "`n...[truncated]" } else { $buildOutput }
    $sections.Add("dotnet build failed after this change:`n$trimmed")
}

if ($formatExitCode -ne 0) {
    $trimmed = if ($formatOutput.Length -gt $maxLen) { $formatOutput.Substring(0, $maxLen) + "`n...[truncated]" } else { $formatOutput }
    $sections.Add("dotnet format --verify-no-changes failed after this change:`n$trimmed")
}

if ($sections.Count -gt 0) {
    $context = ($sections -join "`n`n---`n`n")
    if ($context.Length -gt $maxLen) { $context = $context.Substring(0, $maxLen) + "`n...[truncated]" }
    $result = [ordered]@{ additionalContext = $context }
    Write-HookResult -Payload $payload -Fields $result
}

Write-Output-And-Exit '{}'
