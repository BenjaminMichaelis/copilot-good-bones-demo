<#
.SYNOPSIS
    Offline, no-model proof for the L5 guardrail hooks. Pipes hand-written
    JSON payloads directly into scripts/hooks/deny-newtonsoft.ps1,
    deny-secrets.ps1, verify-build.ps1, and verify-tests.ps1 (exactly the way
    the Copilot CLI invokes a "powershell" command hook: spawn a process,
    write the JSON to its real stdin) and asserts the expected decision. No
    `copilot` process involved.

.NOTES
    Run from anywhere; it resolves paths relative to this script's location.
    Exits non-zero if any assertion fails.
#>

$ErrorActionPreference = 'Stop'
$hooksDir = Join-Path $PSScriptRoot '.'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$denyScript = Join-Path $hooksDir 'deny-newtonsoft.ps1'
$secretsScript = Join-Path $hooksDir 'deny-secrets.ps1'
$verifyScript = Join-Path $hooksDir 'verify-build.ps1'
$testsScript = Join-Path $hooksDir 'verify-tests.ps1'

$script:pass = 0
$script:fail = 0

function Invoke-Hook {
    param([string]$ScriptPath, [hashtable]$Payload)
    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    $output = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
    return ($output -join "`n")
}

function Assert-Substring {
    param([string]$Name, [string]$Actual, [string]$ExpectedSubstring)
    if ($Actual -like "*$ExpectedSubstring*") {
        Write-Output "PASS: $Name"
        $script:pass++
    } else {
        Write-Output "FAIL: $Name"
        Write-Output "  expected to contain: $ExpectedSubstring"
        Write-Output "  actual: $Actual"
        $script:fail++
    }
}

Write-Output '=== deny-newtonsoft.ps1 ==='

# 1. Shell command adding Newtonsoft.Json -> deny
$p1 = @{ sessionId = 's1'; timestamp = 1; cwd = "$repoRoot"; toolName = 'powershell'
         toolArgs = @{ command = 'dotnet add package Newtonsoft.Json'; description = 'add package' } }
Assert-Substring -Name 'shell add-package Newtonsoft -> deny' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p1) -ExpectedSubstring '"permissionDecision":"deny"'

# 2. Unrelated shell command -> allow
$p2 = @{ sessionId = 's2'; timestamp = 2; cwd = "$repoRoot"; toolName = 'powershell'
         toolArgs = @{ command = 'dotnet --version'; description = 'check version' } }
Assert-Substring -Name 'shell dotnet --version -> allow' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p2) -ExpectedSubstring '{}'

# 3. apply_patch ADDING a JsonConvert call (a '+' line) -> deny
$patchAdd = "*** Begin Patch`n*** Update File: Foo.cs`n@@`n+var x = JsonConvert.SerializeObject(y);`n*** End Patch"
$p3 = @{ sessionId = 's3'; timestamp = 3; cwd = "$repoRoot"; toolName = 'apply_patch'; toolArgs = $patchAdd }
Assert-Substring -Name 'apply_patch adds JsonConvert -> deny' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p3) -ExpectedSubstring '"permissionDecision":"deny"'

# 4. apply_patch where Newtonsoft only appears in UNCHANGED context (not a '+'
#    line) -> allow. Proves the hook does not false-positive on the seeded
#    `using Newtonsoft.Json;` line that already exists in Program.cs.
$patchContext = "*** Begin Patch`n*** Update File: Program.cs`n@@`n using Newtonsoft.Json;`n+// unrelated change`n*** End Patch"
$p4 = @{ sessionId = 's4'; timestamp = 4; cwd = "$repoRoot"; toolName = 'apply_patch'; toolArgs = $patchContext }
Assert-Substring -Name 'apply_patch context-only Newtonsoft -> allow (no false positive)' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p4) -ExpectedSubstring '{}'

# 5. create tool writing a new file containing Newtonsoft.Json -> deny
$p5 = @{ sessionId = 's5'; timestamp = 5; cwd = "$repoRoot"; toolName = 'create'
         toolArgs = @{ path = 'NewFile.cs'; file_text = "using Newtonsoft.Json;`nclass X {}" } }
Assert-Substring -Name 'create new file with Newtonsoft -> deny' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p5) -ExpectedSubstring '"permissionDecision":"deny"'

# 6. view (read-only tool) of a file whose PATH mentions Newtonsoft -> allow.
#    Proves read-only tools are never blocked regardless of content.
$p6 = @{ sessionId = 's6'; timestamp = 6; cwd = "$repoRoot"; toolName = 'view'
         toolArgs = @{ path = 'NewtonsoftHelper.cs' } }
Assert-Substring -Name 'view of Newtonsoft-named file -> allow (read-only never blocked)' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p6) -ExpectedSubstring '{}'

# 6b. Central Package Management coverage: adding a Newtonsoft.Json
#     <PackageVersion> to Directory.Packages.props must ALSO be denied. The
#     hook's regex is file-path-agnostic (it scans added content, not the
#     path), so this needs no code change - this assertion is the proof.
$p6b = @{ sessionId = 's6b'; timestamp = 6.5; cwd = "$repoRoot"; toolName = 'create'
          toolArgs = @{ path = 'Directory.Packages.props'; file_text = '<Project><ItemGroup><PackageVersion Include="Newtonsoft.Json" Version="13.0.4" /></ItemGroup></Project>' } }
Assert-Substring -Name 'create Directory.Packages.props adding Newtonsoft -> deny (CPM coverage)' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p6b) -ExpectedSubstring '"permissionDecision":"deny"'

Write-Output ''
Write-Output '=== deny-secrets.ps1 ==='

# Fake credentials are assembled at runtime so no secret-shaped literal ever
# appears in this file (which would also trip GitHub push protection).
$fakeAws = 'AK' + 'IA' + ('Q' * 16)
$fakeGitHub = 'gh' + 'p_' + ('a1' * 18)
$fakeAccountKey = 'AccountKey=' + ('Ab9+' * 22) + '=='
$fakePrivateKey = '-----BEGIN ' + 'RSA PRIVATE KEY-----'

# 11. apply_patch ADDING an AWS access key ID -> deny. This is the payload
#     shape the lab's secret-scan hook never inspects (raw patch string).
$s1 = @{ sessionId = 'x1'; timestamp = 11; cwd = "$repoRoot"; toolName = 'apply_patch'
         toolArgs = "*** Begin Patch`n*** Add File: appsettings.Local.json`n+{ `"AwsKey`": `"$fakeAws`" }`n*** End Patch" }
Assert-Substring -Name 'apply_patch adds AWS key -> deny' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s1) -ExpectedSubstring '"permissionDecision":"deny"'

# 12. apply_patch where the secret is only in UNCHANGED context -> allow.
$s2 = @{ sessionId = 'x2'; timestamp = 12; cwd = "$repoRoot"; toolName = 'apply_patch'
         toolArgs = "*** Begin Patch`n*** Update File: x.json`n@@`n `"k`": `"$fakeAws`"`n+// unrelated change`n*** End Patch" }
Assert-Substring -Name 'apply_patch context-only secret -> allow (no false positive)' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s2) -ExpectedSubstring '{}'

# 13. create an appsettings file with an Azure Storage account key -> deny.
$s3 = @{ sessionId = 'x3'; timestamp = 13; cwd = "$repoRoot"; toolName = 'create'
         toolArgs = @{ path = 'appsettings.json'; file_text = "{ `"Storage`": `"DefaultEndpointsProtocol=https;AccountName=sessionboard;$fakeAccountKey`" }" } }
Assert-Substring -Name 'create appsettings with Azure AccountKey -> deny' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s3) -ExpectedSubstring 'Azure Storage account key'

# 14. edit (new_str) adding a GitHub token -> deny.
$s4 = @{ sessionId = 'x4'; timestamp = 14; cwd = "$repoRoot"; toolName = 'edit'
         toolArgs = @{ path = 'Program.cs'; old_str = '// token'; new_str = "var token = `"$fakeGitHub`";" } }
Assert-Substring -Name 'edit adds GitHub token -> deny' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s4) -ExpectedSubstring 'GitHub token'

# 15. shell command writing a private key -> deny.
$s5 = @{ sessionId = 'x5'; timestamp = 15; cwd = "$repoRoot"; toolName = 'powershell'
         toolArgs = @{ command = "Set-Content key.pem '$fakePrivateKey'"; description = 'write key' } }
Assert-Substring -Name 'shell writes private key -> deny' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s5) -ExpectedSubstring 'private key'

# 16. create ordinary C# -> allow.
$s6 = @{ sessionId = 'x6'; timestamp = 16; cwd = "$repoRoot"; toolName = 'create'
         toolArgs = @{ path = 'Foo.cs'; file_text = 'namespace SessionBoard.Api; public record Foo(int Id);' } }
Assert-Substring -Name 'create ordinary C# -> allow' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s6) -ExpectedSubstring '{}'

# 17. view (read-only) of appsettings.json -> allow.
$s7 = @{ sessionId = 'x7'; timestamp = 17; cwd = "$repoRoot"; toolName = 'view'
         toolArgs = @{ path = 'appsettings.json' } }
Assert-Substring -Name 'view appsettings.json -> allow (read-only never blocked)' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $s7) -ExpectedSubstring '{}'

Write-Output ''
Write-Output '=== verify-build.ps1 ==='

# 7. Non-.cs path -> fast allow, no build invoked
$p7 = @{ sessionId = 's7'; timestamp = 7; cwd = "$repoRoot"; toolName = 'create'
         toolArgs = @{ path = 'README.md'; file_text = '# notes' } }
Assert-Substring -Name 'create README.md -> allow, build skipped' -Actual (Invoke-Hook -ScriptPath $verifyScript -Payload $p7) -ExpectedSubstring '{}'

# 8. Real build, currently green -> `dotnet build` succeeds (no "build
#    failed" text), but Invoke-DotNetFormatStrict.ps1 ALSO runs and still
#    flags the seeded, pre-existing style debt (e.g. IDE0161 block
#    namespaces -- one of the demo's OWN seeded smells -- and IDE0090) as
#    baseline noise on every edit that touches a .cs file. This is expected:
#    `dotnet build` remains the authoritative green/red gate: it is never
#    the source of "failed" here. The format findings are supplementary
#    context, not a hard fail, and are deliberately NOT auto-fixed (fixing
#    IDE0161 would erase a seeded smell the talk depends on).
$p8 = @{ sessionId = 's8'; timestamp = 8; cwd = "$repoRoot"; toolName = 'edit'
         toolArgs = @{ path = (Join-Path $repoRoot 'src\SessionBoard.Api\Program.cs') } }
$out8 = Invoke-Hook -ScriptPath $verifyScript -Payload $p8
Assert-Substring -Name 'edit Program.cs on green tree -> dotnet build succeeds' -Actual $out8 -ExpectedSubstring 'additionalContext'
if ($out8 -like '*dotnet build failed*') {
    Write-Output 'FAIL: edit Program.cs on green tree -> dotnet build must NOT report failure'
    $script:fail++
} else {
    Write-Output 'PASS: edit Program.cs on green tree -> dotnet build must NOT report failure'
    $script:pass++
}

# 9. Force a REAL build break with a scratch file, confirm additionalContext
#    surfaces the `dotnet build failed` error, then clean up and confirm the
#    build (not the format baseline) goes back to passing.
$scratchFile = Join-Path $repoRoot 'src\SessionBoard.Api\_scratch_test_hook.cs'
try {
    Set-Content -Path $scratchFile -Value 'this is not valid C#' -NoNewline
    $p9 = @{ sessionId = 's9'; timestamp = 9; cwd = "$repoRoot"; toolName = 'create'
             toolArgs = @{ path = $scratchFile; file_text = 'this is not valid C#' } }
    Assert-Substring -Name 'create broken .cs file -> additionalContext shows dotnet build failed' -Actual (Invoke-Hook -ScriptPath $verifyScript -Payload $p9) -ExpectedSubstring 'dotnet build failed'
} finally {
    Remove-Item -Path $scratchFile -ErrorAction SilentlyContinue
}

# 10. Confirm `dotnet build` is green again after removing the scratch file
#     (the format-baseline noise from test 8 is expected to still be
#     present -- same deterministic finding, proving the signal is stable).
$p10 = @{ sessionId = 's10'; timestamp = 10; cwd = "$repoRoot"; toolName = 'edit'
          toolArgs = @{ path = (Join-Path $repoRoot 'src\SessionBoard.Api\Program.cs') } }
$out10 = Invoke-Hook -ScriptPath $verifyScript -Payload $p10
if ($out10 -like '*dotnet build failed*') {
    Write-Output 'FAIL: tree green again after cleanup -> dotnet build must NOT report failure'
    $script:fail++
} else {
    Write-Output 'PASS: tree green again after cleanup -> dotnet build must NOT report failure'
    $script:pass++
}

Write-Output ''
Write-Output '=== verify-tests.ps1 (agentStop) ==='

# 18. A turn that changed no C#: point cwd at a throwaway git repo with only a
#     README, so the "skip the test run" path is exercised deterministically
#     regardless of this repo's own working-tree state.
$emptyRepo = Join-Path ([IO.Path]::GetTempPath()) ("hooks-no-cs-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $emptyRepo | Out-Null
    & git -C $emptyRepo init --quiet 2>$null
    Set-Content -Path (Join-Path $emptyRepo 'README.md') -Value '# notes'
    $t1 = @{ sessionId = 't1'; timestamp = 18; cwd = "$emptyRepo"; stopReason = 'end_turn' }
    Assert-Substring -Name 'agentStop, no C# changed -> allow, tests skipped' -Actual (Invoke-Hook -ScriptPath $testsScript -Payload $t1) -ExpectedSubstring '{}'
} finally {
    Remove-Item -Path $emptyRepo -Recurse -Force -ErrorAction SilentlyContinue
}

# 19. C# changed and the suite is green -> allow. A scratch PASSING test makes
#     the tree dirty so the hook actually runs `dotnet test`.
$scratchTest = Join-Path $repoRoot 'tests\SessionBoard.Api.Tests\_scratch_hook_test.cs'
try {
    Set-Content -Path $scratchTest -Value "namespace SessionBoard.Api.Tests;`n`npublic class ScratchHookTest`n{`n    [Fact]`n    public void ScratchHookPasses() => Assert.Equal(4, 2 + 2);`n}"
    $t2 = @{ sessionId = 't2'; timestamp = 19; cwd = "$repoRoot"; stopReason = 'end_turn' }
    Assert-Substring -Name 'agentStop, tests green -> allow' -Actual (Invoke-Hook -ScriptPath $testsScript -Payload $t2) -ExpectedSubstring '{}'

    # 20. C# changed and a test fails -> block, and the reason names the test
    #     and carries the assertion's Expected/Actual for the agent to act on.
    Set-Content -Path $scratchTest -Value "namespace SessionBoard.Api.Tests;`n`npublic class ScratchHookTest`n{`n    [Fact]`n    public void ScratchHookAlwaysFails() => Assert.Equal(5, 4);`n}"
    $t3 = @{ sessionId = 't3'; timestamp = 20; cwd = "$repoRoot"; stopReason = 'end_turn' }
    $out20 = Invoke-Hook -ScriptPath $testsScript -Payload $t3
    Assert-Substring -Name 'agentStop, test fails -> block' -Actual $out20 -ExpectedSubstring '"decision":"block"'
    Assert-Substring -Name 'agentStop block reason names the failing test' -Actual $out20 -ExpectedSubstring 'ScratchHookAlwaysFails'
} finally {
    Remove-Item -Path $scratchTest -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output '=== VS Code Local agent payloads (same scripts) ==='

# VS Code's Local agent loads the same guardrails.json but sends its own
# payload ({hook_event_name, tool_name, tool_input}, shape copied from its
# "GitHub Copilot Chat Hooks" log) and reads decisions only from
# hookSpecificOutput. Every hook must answer it in that format.
function Get-VsCodePayload {
    param([string]$EventName, [string]$ToolName, $ToolInput, [string]$Session = 'vs-session', [bool]$StopHookActive = $false)
    $p = @{ hook_event_name = $EventName; session_id = $Session; timestamp = '2026-10-01T19:26:50.795Z'
            transcript_path = 'transcript.jsonl'; cwd = "$repoRoot" }
    if ($ToolName) { $p.tool_name = $ToolName; $p.tool_input = $ToolInput; $p.tool_use_id = 'call_1__vscode-1' }
    if ($EventName -eq 'Stop') { $p.stop_hook_active = $StopHookActive }
    return $p
}

function Assert-NoSubstring {
    param([string]$Name, [string]$Actual, [string]$UnexpectedSubstring)
    if ($Actual -like "*$UnexpectedSubstring*") {
        Write-Output "FAIL: $Name"
        Write-Output "  expected NOT to contain: $UnexpectedSubstring"
        Write-Output "  actual: $Actual"
        $script:fail++
    } else {
        Write-Output "PASS: $Name"
        $script:pass++
    }
}

$vsDeny = '"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"'

# 21. The exact call VS Code logged for the live deny prompt.
$v1 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'run_in_terminal' -ToolInput @{
    command = 'dotnet add src/SessionBoard.Api package Newtonsoft.Json'; explanation = 'x'; goal = 'Add Newtonsoft.Json package'; mode = 'sync' }
Assert-Substring -Name 'vscode run_in_terminal add Newtonsoft -> deny in hookSpecificOutput' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v1) -ExpectedSubstring $vsDeny
Assert-NoSubstring -Name 'cli shell add Newtonsoft -> top-level only (unchanged for the CLI)' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $p1) -UnexpectedSubstring 'hookSpecificOutput'

# 22. Unrelated terminal command -> allow.
$v2 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'run_in_terminal' -ToolInput @{ command = 'dotnet --version'; explanation = 'x'; goal = 'x'; mode = 'sync' }
Assert-Substring -Name 'vscode run_in_terminal dotnet --version -> allow' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v2) -ExpectedSubstring '{}'

# 23. Each VS Code edit tool that can add Newtonsoft -> deny.
$v3 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'create_file' -ToolInput @{ filePath = (Join-Path $repoRoot 'src\SessionBoard.Api\Json.cs'); content = 'var s = JsonConvert.SerializeObject(x);' }
Assert-Substring -Name 'vscode create_file with JsonConvert -> deny' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v3) -ExpectedSubstring $vsDeny
$v4 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'multi_replace_string_in_file' -ToolInput @{ explanation = 'x'; replacements = @(
    @{ filePath = (Join-Path $repoRoot 'README.md'); oldString = 'a'; newString = 'b' }
    @{ filePath = (Join-Path $repoRoot 'src\SessionBoard.Api\Program.cs'); oldString = 'c'; newString = 'using Newtonsoft.Json;' }) }
Assert-Substring -Name 'vscode multi_replace adding Newtonsoft in its 2nd file -> deny' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v4) -ExpectedSubstring $vsDeny
$v5 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'apply_patch' -ToolInput @{ explanation = 'x'; input = $patchAdd }
Assert-Substring -Name 'vscode apply_patch adds JsonConvert -> deny' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v5) -ExpectedSubstring $vsDeny

# 24. Removing Newtonsoft (only oldString mentions it) and reads -> allow.
$v6 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'replace_string_in_file' -ToolInput @{ filePath = (Join-Path $repoRoot 'src\SessionBoard.Api\Program.cs'); oldString = 'using Newtonsoft.Json;'; newString = 'using System.Text.Json;' }
Assert-Substring -Name 'vscode replace_string removing Newtonsoft -> allow' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v6) -ExpectedSubstring '{}'
$v7 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'read_file' -ToolInput @{ filePath = 'Newtonsoft.Json.md'; startLine = 1; endLine = 10 }
Assert-Substring -Name 'vscode read_file of Newtonsoft-named file -> allow' -Actual (Invoke-Hook -ScriptPath $denyScript -Payload $v7) -ExpectedSubstring '{}'

# 25. Secrets through VS Code's tools -> deny, naming VS Code's tool.
$v8 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'run_in_terminal' -ToolInput @{ command = "dotnet user-secrets set `"Aws:AccessKeyId`" `"$fakeAws`""; explanation = 'x'; goal = 'x'; mode = 'sync' }
$out25 = Invoke-Hook -ScriptPath $secretsScript -Payload $v8
Assert-Substring -Name 'vscode run_in_terminal writes AWS key -> deny' -Actual $out25 -ExpectedSubstring $vsDeny
Assert-Substring -Name 'vscode secret denial names run_in_terminal' -Actual $out25 -ExpectedSubstring 'in this run_in_terminal call'
$v9 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'create_file' -ToolInput @{ filePath = (Join-Path $repoRoot 'src\SessionBoard.Api\appsettings.Local.json'); content = "{ `"Storage`": `"$fakeAccountKey`" }" }
Assert-Substring -Name 'vscode create_file with Azure AccountKey -> deny' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $v9) -ExpectedSubstring 'Azure Storage account key'
$v10 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'replace_string_in_file' -ToolInput @{ filePath = (Join-Path $repoRoot 'src\SessionBoard.Api\appsettings.json'); oldString = '{'; newString = "{ `"Token`": `"$fakeGitHub`"," }
Assert-Substring -Name 'vscode replace_string adds GitHub token -> deny' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $v10) -ExpectedSubstring $vsDeny
$v11 = Get-VsCodePayload -EventName 'PreToolUse' -ToolName 'create_file' -ToolInput @{ filePath = (Join-Path $repoRoot 'src\SessionBoard.Api\Ok.cs'); content = 'public static class Ok { }' }
Assert-Substring -Name 'vscode create_file ordinary C# -> allow' -Actual (Invoke-Hook -ScriptPath $secretsScript -Payload $v11) -ExpectedSubstring '{}'

# 26. PostToolUse: README skips the build; a broken .cs file reports it in
#     hookSpecificOutput.additionalContext.
$v12 = Get-VsCodePayload -EventName 'PostToolUse' -ToolName 'create_file' -ToolInput @{ filePath = (Join-Path $repoRoot 'README.md'); content = '# notes' }
Assert-Substring -Name 'vscode PostToolUse create README.md -> allow, build skipped' -Actual (Invoke-Hook -ScriptPath $verifyScript -Payload $v12) -ExpectedSubstring '{}'
try {
    Set-Content -Path $scratchFile -Value 'this is not valid C#' -NoNewline
    $v13 = Get-VsCodePayload -EventName 'PostToolUse' -ToolName 'create_file' -ToolInput @{ filePath = $scratchFile; content = 'this is not valid C#' }
    $out26 = Invoke-Hook -ScriptPath $verifyScript -Payload $v13
    Assert-Substring -Name 'vscode PostToolUse broken .cs -> additionalContext in hookSpecificOutput' -Actual $out26 -ExpectedSubstring '"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":'
    Assert-Substring -Name 'vscode PostToolUse context says dotnet build failed' -Actual $out26 -ExpectedSubstring 'dotnet build failed'
} finally {
    Remove-Item -Path $scratchFile -ErrorAction SilentlyContinue
}

# 27. Stop (VS Code's name for agentStop): red suite -> block in
#     hookSpecificOutput; and VS Code has no block cap, so the hook lets the
#     9th consecutive block through itself.
$capFile = Join-Path ([IO.Path]::GetTempPath()) 'good-bones-stop-vs-cap.count'
try {
    Set-Content -Path $scratchTest -Value "namespace SessionBoard.Api.Tests;`n`npublic class ScratchHookTest`n{`n    [Fact]`n    public void ScratchHookAlwaysFails() => Assert.Equal(5, 4);`n}"
    $v14 = Get-VsCodePayload -EventName 'Stop' -Session 'vs-red'
    $out27 = Invoke-Hook -ScriptPath $testsScript -Payload $v14
    Assert-Substring -Name 'vscode Stop, test fails -> block in hookSpecificOutput' -Actual $out27 -ExpectedSubstring '"hookSpecificOutput":{"hookEventName":"Stop","decision":"block"'
    Assert-Substring -Name 'vscode Stop block reason names the failing test' -Actual $out27 -ExpectedSubstring 'ScratchHookAlwaysFails'

    Set-Content -Path $capFile -Value 8
    $v15 = Get-VsCodePayload -EventName 'Stop' -Session 'vs-cap' -StopHookActive $true
    Assert-Substring -Name 'vscode Stop, 9th consecutive block -> allow (cap)' -Actual (Invoke-Hook -ScriptPath $testsScript -Payload $v15) -ExpectedSubstring '{}'
} finally {
    Remove-Item -Path $scratchTest, $capFile -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path ([IO.Path]::GetTempPath()) 'good-bones-stop-vs-red.count') -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output "Results: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
exit 0
