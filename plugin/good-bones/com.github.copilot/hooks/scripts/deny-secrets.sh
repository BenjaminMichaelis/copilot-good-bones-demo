#!/usr/bin/env bash
# preToolUse hook: deny any tool call that would write a credential into this repo.
# Bash port of deny-secrets.ps1 — same logic, for Linux/macOS/Codespaces hosts.
# Pattern set adapted from ms-mfg-community/day-in-the-life-copilot-lab
# (scripts/hooks/pre-tool-use-secret-scan.sh), rewritten for the payload shapes
# this CLI actually sends: apply_patch's toolArgs is a raw patch string, and
# create/edit carry file_text/new_str.
set -euo pipefail

payload="$(cat)"

# VS Code's Local agent sends its own payload shape; map it onto the CLI's.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hook-compat.sh
. "$script_dir/hook-compat.sh"
hook_normalize || true

tool_name="$(jq -r '.toolName // empty' <<<"$payload" 2>/dev/null || true)"
display_name="$(jq -r '.displayName // .toolName // empty' <<<"$payload" 2>/dev/null || true)"

case "$tool_name" in
  powershell|bash)
    candidate="$(jq -r '.toolArgs.command // empty' <<<"$payload" 2>/dev/null || true)"
    ;;
  apply_patch)
    patch_text="$(jq -r 'if (.toolArgs|type) == "string" then .toolArgs else (.toolArgs|tostring) end' <<<"$payload" 2>/dev/null || true)"
    # Only lines actually being added by the patch (leading '+', not '+++').
    candidate="$(echo "$patch_text" | grep -E '^\+[^+]|^\+$' || true)"
    ;;
  edit|create)
    candidate="$(jq -r '(.toolArgs.file_text // .toolArgs.new_str // (.toolArgs|tostring))' <<<"$payload" 2>/dev/null || true)"
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

deny() {
  hook_result "$(jq -cn --arg name "$1" --arg tool "$display_name" \
    '{permissionDecision:"deny", permissionDecisionReason:("Possible " + $name + " in this " + $tool + " call. Secrets never go in source: use `dotnet user-secrets` locally and Key Vault or managed identity in Azure. Blocked by the good-bones plugin (deny-secrets.sh).")}')"
  exit 0
}

# Same order as the PowerShell version: the first match names the finding.
grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' <<<"$candidate" && deny 'private key'
grep -Eiq 'AccountKey=[A-Za-z0-9+/]{40,}={0,2}' <<<"$candidate" && deny 'Azure Storage account key'
grep -Eiq 'SharedAccessKey=[A-Za-z0-9+/]{30,}={0,2}' <<<"$candidate" && deny 'Azure shared access key'
grep -Eq '(^|[^A-Z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^A-Z0-9]|$)' <<<"$candidate" && deny 'AWS access key ID'
grep -Eq '\b(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})' <<<"$candidate" && deny 'GitHub token'
grep -Eq '\bsk-[A-Za-z0-9_-]{20,}' <<<"$candidate" && deny 'API key (sk-...)'
grep -Eiq '\b(Password|Pwd)=[^;"'"'"'[:space:]]{8,}' <<<"$candidate" && deny 'connection-string password'

echo '{}'
