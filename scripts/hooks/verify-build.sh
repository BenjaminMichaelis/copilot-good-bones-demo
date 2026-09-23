#!/usr/bin/env bash
# postToolUse hook: after an edit/create touching *.cs or *.csproj, run
# `dotnet build` PLUS the repo's strict-format check (adopted from
# BenjaminMichaelis/DotnetTemplates, see README.md "Good bones come from")
# and surface the first failures as additionalContext.
# Bash port of verify-build.ps1 — same logic, for Linux/macOS/Codespaces hosts.
# Invoke-DotNetFormatStrict.ps1 is PowerShell-only (it ships from the
# template as a .ps1 with no bash equivalent); this script shells out to
# `pwsh` to run it and skips the format check (build-only) if `pwsh` is not
# on PATH, so the hook degrades gracefully rather than failing hard.
# NOTE: not exercised in this (Windows-only) verification session — only the
# .ps1 was actually run and tested. Treat as best-effort until run on Linux.
set -uo pipefail

payload="$(cat)"

# VS Code's Local agent sends its own payload shape; map it onto the CLI's.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hook-compat.sh
. "$script_dir/hook-compat.sh"
hook_normalize || true

tool_name="$(jq -r '.toolName // empty' <<<"$payload" 2>/dev/null || true)"
case "$tool_name" in
  apply_patch|edit|create) ;;
  *) echo '{}'; exit 0 ;;
esac

touches_cs=0
if [ "$tool_name" = "apply_patch" ]; then
  patch_text="$(jq -r 'if (.toolArgs|type) == "string" then .toolArgs else (.toolArgs|tostring) end' <<<"$payload" 2>/dev/null || true)"
  if echo "$patch_text" | grep -Eiq '^\*\*\*[[:space:]]+(Update|Add|Delete) File:.*\.(cs|csproj)[[:space:]]*$'; then
    touches_cs=1
  fi
else
  path="$(jq -r '.toolArgs.path // empty' <<<"$payload" 2>/dev/null || true)"
  if echo "$path" | grep -Eiq '\.(cs|csproj)$'; then
    touches_cs=1
  fi
fi

if [ "$touches_cs" -eq 0 ]; then
  echo '{}'
  exit 0
fi

cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
if [ -z "$cwd" ]; then cwd="$(pwd)"; fi

build_output="$(cd "$cwd" && dotnet build --nologo -v q 2>&1)"
build_exit=$?

format_script="$script_dir/../../.github/scripts/Invoke-DotNetFormatStrict.ps1"
format_output=""
format_exit=0
if command -v pwsh >/dev/null 2>&1; then
  format_output="$(cd "$cwd" && pwsh -NoProfile -File "$format_script" -DiscoverFromCurrentDirectory 2>&1)"
  format_exit=$?
fi

sections=()

if [ "$build_exit" -ne 0 ]; then
  trimmed="$(echo "$build_output" | head -c 8000)"
  sections+=("dotnet build failed after this change:
$trimmed")
fi

if [ "$format_exit" -ne 0 ]; then
  trimmed="$(echo "$format_output" | head -c 8000)"
  sections+=("dotnet format --verify-no-changes failed after this change:
$trimmed")
fi

if [ "${#sections[@]}" -gt 0 ]; then
  ctx="$(printf '%s\n\n---\n\n' "${sections[@]}")"
  ctx="$(echo "$ctx" | head -c 8000)"
  hook_result "$(jq -cn --arg ctx "$ctx" '{additionalContext: $ctx}')"
  exit 0
fi

echo '{}'
