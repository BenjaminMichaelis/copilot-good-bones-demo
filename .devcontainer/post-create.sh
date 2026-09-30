#!/usr/bin/env bash
# Codespaces / dev container setup for following along with the talk.
set -euo pipefail

# The Linux hook scripts (scripts/hooks/*.sh, from the L5-hooks layer on)
# parse hook payloads with jq.
if ! command -v jq >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq jq
fi

dotnet restore SessionBoard.slnx
dotnet build SessionBoard.slnx --no-restore --nologo -v q

# HTTPS dev certificate for the Aspire dashboard; harmless if already trusted.
aspire certs trust --non-interactive || true

cat <<'EOF'

Ready. To follow along:
  git checkout L0-bare
  copilot            # sign in with /login if prompted, then paste the hero prompt from README.md
Between layers, discard the agent's changes and move up one layer:
  git checkout -- . && git clean -fd && git checkout L1-instructions
EOF
