#!/usr/bin/env bash
# agentStop hook: the agent may not finish while `dotnet test` is red.
# Bash port of verify-tests.ps1 — same logic, for Linux/macOS/Codespaces hosts.
# Returns {} (stop normally) when no C# changed or tests pass; otherwise
# {"decision":"block","reason":...} so the CLI feeds the failing tests back to
# the agent as its next prompt.
set -uo pipefail

payload="$(cat)"

# VS Code's Local agent runs this as its Stop hook with its own payload shape;
# map it onto the CLI's.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hook-compat.sh
. "$script_dir/hook-compat.sh"
hook_normalize || true

cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
[ -z "$cwd" ] && cwd="$(pwd)"
is_repeat="$(jq -r '.stop_hook_active // false' <<<"$payload" 2>/dev/null || echo false)"

# VS Code has no cap on consecutive Stop blocks (the CLI stops honoring them
# after 8), so for VS Code sessions count them here and allow the 9th.
count_file=""
if [ "$HOOK_HOST" = "vscode" ]; then
  session_key="$(jq -r '.sessionId // empty' <<<"$payload" 2>/dev/null | tr -cd 'A-Za-z0-9-')"
  [ -n "$session_key" ] && count_file="${TMPDIR:-/tmp}/good-bones-stop-$session_key.count"
fi

allow() {
  [ -n "$count_file" ] && rm -f "$count_file"
  echo '{}'
  exit 0
}

cd "$cwd" || allow

# Did this turn leave any C# changes behind? If git fails, run the tests.
if status="$(git status --porcelain --untracked-files=all 2>/dev/null)"; then
  if ! grep -Eq '\.(cs|csproj)"?[[:space:]]*$' <<<"$status"; then
    allow
  fi
fi

test_output="$(dotnet test --nologo -v q --logger 'console;verbosity=normal' 2>&1)"
test_exit=$?

if [ "$test_exit" -eq 0 ]; then
  allow
fi

if [ -n "$count_file" ]; then
  block_count=0
  if [ "$is_repeat" = "true" ] && [ -f "$count_file" ]; then
    block_count="$(cat "$count_file")"
  fi
  block_count=$((block_count + 1))
  [ "$block_count" -gt 8 ] && allow
  echo "$block_count" > "$count_file"
fi

# Same line filter as the PowerShell version: failed test name, assertion
# message, Expected/Actual, first frame in our code, compile errors, totals.
detail="$(grep -v '^\[xUnit\.net' <<<"$test_output" | grep -E \
  -e '^  Failed [^ ]' \
  -e '^[[:space:]]*Error Message:' \
  -e '^[[:space:]]*Assert\.' \
  -e '^(Expected|Actual):' \
  -e '^[[:space:]]+at SessionBoard\..* in .*:line [0-9]+' \
  -e 'error [A-Z]{2,}[0-9]{3,}' \
  -e '^[[:space:]]*(Total tests|Passed|Failed):' \
  -e '^Test Run Failed' | head -n 60)"
[ -z "$detail" ] && detail="$(tail -n 40 <<<"$test_output")"
detail="${detail:0:6000}"

repeat_note=""
[ "$is_repeat" = "true" ] && repeat_note=" (still red after a previous block)"

hook_result "$(jq -cn --arg detail "$detail" --arg note "$repeat_note" \
  '{decision:"block", reason:("dotnet test failed" + $note + ". You may not finish while tests are red: fix the code or the tests so `dotnet test` passes, then stop. Blocked by scripts/hooks/verify-tests.sh (L5 agentStop hook).\n\n" + $detail)}')"
