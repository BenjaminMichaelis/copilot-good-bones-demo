<#
.SYNOPSIS
    agentStop hook: the agent may not finish while `dotnet test` is red -
    deterministic, no model involved.

.DESCRIPTION
    Reads the agentStop JSON payload from stdin: {sessionId, timestamp, cwd,
    stopReason, transcriptPath, stop_hook_active}. When the working tree has
    uncommitted changes to *.cs / *.csproj files, runs `dotnet test` from the
    reported `cwd`:

      - green -> `{}`: the agent stops normally.
      - red   -> `{"decision":"block","reason":...}`: the CLI enqueues the
                 reason (the failing tests) as a follow-up user message, so
                 the agent keeps working instead of declaring victory.

    Turns that changed no C# (a docs question, a README edit, an audit) skip
    the test run entirely, so Q&A turns don't pay ~20 s of test time.

    `stop_hook_active` is true when this stop is a re-entry caused by an
    earlier block. This hook still blocks while tests are red - enforcement
    is the point - and relies on the CLI's cap on consecutive blocks to end
    a turn the agent genuinely can't fix. The flag is echoed in the reason so
    the transcript shows it was a repeat.

    VS Code's Local agent runs this as its Stop hook (it maps agentStop) and
    has no such cap, so for VS Code sessions this hook counts consecutive
    blocks itself and lets the agent stop after the CLI's same 8.
    hook-compat.ps1 maps VS Code's payload and answers in its format.

    Why agentStop and not postToolUse: the build (verify-build.ps1) is cheap
    enough to run after every edit; the test suite is not. Once per turn, at
    the moment the agent claims it's done, is the right cadence for tests.

    Allows on any unparseable payload, like the other hooks here; the
    guarantee comes from scripts/hooks/test-hooks.ps1 exercising it offline.
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

$cwd = [string]$payload.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }
$isRepeat = [bool]$payload.stop_hook_active

# VS Code only: where this session's consecutive-block count lives.
$blockCountFile = $null
if ($payload.hookHost -eq 'vscode' -and $payload.sessionId) {
    $sessionKey = $payload.sessionId -replace '[^A-Za-z0-9-]', ''
    $blockCountFile = Join-Path ([IO.Path]::GetTempPath()) "good-bones-stop-$sessionKey.count"
}

function Exit-Allow {
    if ($blockCountFile) { Remove-Item -LiteralPath $blockCountFile -ErrorAction SilentlyContinue }
    Write-Output-And-Exit '{}'
}

Push-Location $cwd
try {
    # Did this turn leave any C# changes behind? If git itself fails (not a
    # repo, git missing), don't guess: run the tests.
    $changedCs = $true
    try {
        $status = & git status --porcelain --untracked-files=all 2>$null
        if ($LASTEXITCODE -eq 0) {
            $changedCs = [bool]($status | Where-Object { $_ -match '\.(cs|csproj)"?\s*$' })
        }
    } catch {
        $changedCs = $true
    }

    if (-not $changedCs) {
        Exit-Allow
    }

    # Same PowerShell 5.1 trap as verify-build.ps1, but worse here: VSTest
    # writes the failing test's line to STDERR, so under 'Stop' the first
    # failure becomes a terminating error and a try/catch keeps only that one
    # line (the test name, no assertion message). Relax the preference for
    # the native call so every stderr line is kept as data, and stringify
    # the ErrorRecords so they read as plain text.
    # `-v q` keeps build noise out; the console logger at `normal` is what
    # prints the assertion message and Expected/Actual for each failure.
    $testExitCode = 0
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $testOutput = & dotnet test --nologo -v q --logger 'console;verbosity=normal' 2>&1 |
            ForEach-Object { "$_" } | Out-String
        $testExitCode = $LASTEXITCODE
    } catch {
        $testOutput = $_.Exception.Message
        $testExitCode = 1
    } finally {
        $ErrorActionPreference = $previousPreference
    }
} finally {
    Pop-Location
}

if ($testExitCode -eq 0) {
    Exit-Allow
}

# VS Code: the 9th block in a row lets the agent stop, like the CLI's cap. A
# stop that isn't a re-entry (a new turn) starts the count again.
if ($blockCountFile) {
    $blockCount = 0
    if ($isRepeat -and (Test-Path -LiteralPath $blockCountFile)) {
        $blockCount = [int](Get-Content -LiteralPath $blockCountFile -Raw)
    }
    $blockCount++
    if ($blockCount -gt 8) { Exit-Allow }
    Set-Content -LiteralPath $blockCountFile -Value $blockCount
}

# Keep the lines that tell the agent what to fix: the failed test's name, its
# assertion message and Expected/Actual, the first frame in our own code,
# compile errors, and the totals. Skip xUnit's duplicate [xUnit.net ...] echo
# and the test host's Microsoft.Hosting.Lifetime chatter. Fall back to the
# tail if nothing matched (an unexpected failure shape).
$lines = $testOutput -split "`r?`n"
$relevant = $lines | Where-Object {
    $_ -notmatch '^\[xUnit\.net' -and (
        $_ -cmatch '^\s{2}Failed \S' -or
        $_ -cmatch '^\s*Error Message:' -or
        $_ -cmatch '^\s*Assert\.' -or
        $_ -cmatch '^(Expected|Actual):' -or
        $_ -cmatch '^\s+at SessionBoard\..* in .*:line \d+' -or
        $_ -cmatch 'error [A-Z]{2,}\d{3,}' -or
        $_ -cmatch '^\s*(Total tests|Passed|Failed):' -or
        $_ -cmatch '^Test Run Failed'
    )
}
$detail = if ($relevant) { ($relevant | Select-Object -First 60) -join "`n" } else { ($lines | Select-Object -Last 40) -join "`n" }

$maxLen = 6000
if ($detail.Length -gt $maxLen) { $detail = $detail.Substring(0, $maxLen) + "`n...[truncated]" }

$repeatNote = if ($isRepeat) { ' (still red after a previous block)' } else { '' }
$reason = "dotnet test failed$repeatNote. You may not finish while tests are red: fix the code or the tests so ``dotnet test`` passes, then stop. Blocked by scripts/hooks/verify-tests.ps1 (L5 agentStop hook).`n`n$detail"

$result = [ordered]@{
    decision = 'block'
    reason   = $reason
}
Write-HookResult -Payload $payload -Fields $result
