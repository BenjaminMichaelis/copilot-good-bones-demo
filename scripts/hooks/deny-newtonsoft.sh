#!/usr/bin/env bash
# preToolUse hook: deny any tool call that would add Newtonsoft.Json / JsonConvert.
# Bash port of deny-newtonsoft.ps1 — same logic, for Linux/macOS/Codespaces hosts.
# NOTE: written to match the PowerShell version's behavior exactly, but this
# script was NOT exercised in this (Windows-only) verification session — only
# the .ps1 was actually run and tested. Treat this as best-effort until it has
# been run at least once on a Linux host.
set -euo pipefail

payload="$(cat)"

# VS Code's Local agent sends its own payload shape; map it onto the CLI's.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hook-compat.sh
. "$script_dir/hook-compat.sh"
hook_normalize || true

tool_name="$(jq -r '.toolName // empty' <<<"$payload" 2>/dev/null || true)"

case "$tool_name" in
  powershell|bash)
    command_text="$(jq -r '.toolArgs.command // empty' <<<"$payload" 2>/dev/null || true)"
    if echo "$command_text" | grep -Eiq 'Newtonsoft|JsonConvert'; then
      hook_result "$(jq -cn '{permissionDecision:"deny", permissionDecisionReason:"House rule (.github/copilot-instructions.md): this repo uses System.Text.Json, never Newtonsoft.Json/JsonConvert. Blocked by scripts/hooks/deny-newtonsoft.sh (L5 guardrail hook)."}')"
      exit 0
    fi
    ;;
  apply_patch)
    patch_text="$(jq -r 'if (.toolArgs|type) == "string" then .toolArgs else (.toolArgs|tostring) end' <<<"$payload" 2>/dev/null || true)"
    added_lines="$(echo "$patch_text" | grep -E '^\+[^+]|^\+$' || true)"
    if echo "$added_lines" | grep -Eiq 'Newtonsoft|JsonConvert'; then
      hook_result "$(jq -cn '{permissionDecision:"deny", permissionDecisionReason:"House rule (.github/copilot-instructions.md): this repo uses System.Text.Json, never Newtonsoft.Json/JsonConvert. Blocked by scripts/hooks/deny-newtonsoft.sh (L5 guardrail hook)."}')"
      exit 0
    fi
    ;;
  edit|create)
    candidate="$(jq -r '(.toolArgs.file_text // .toolArgs.new_str // (.toolArgs|tostring))' <<<"$payload" 2>/dev/null || true)"
    if echo "$candidate" | grep -Eiq 'Newtonsoft|JsonConvert'; then
      hook_result "$(jq -cn '{permissionDecision:"deny", permissionDecisionReason:"House rule (.github/copilot-instructions.md): this repo uses System.Text.Json, never Newtonsoft.Json/JsonConvert. Blocked by scripts/hooks/deny-newtonsoft.sh (L5 guardrail hook)."}')"
      exit 0
    fi
    ;;
  *)
    ;;
esac

echo '{}'
