#!/usr/bin/env bash
# 02-install-qvac.sh — Install QVAC SDK + CLI and write a Pi-friendly config.
#
# Prerequisite: 01-pi-setup.sh has been run and PATH includes ~/.npm-global/bin.

set -euo pipefail

log() { printf '\n\033[1;36m[qvac]\033[0m %s\n' "$*"; }

export PATH="$HOME/.npm-global/bin:$PATH"

log "Installing @qvac/cli globally (provides the 'qvac' command)..."
npm install -g @qvac/cli

log "Installing @qvac/sdk LOCALLY in $(pwd) ..."
# The CLI server resolves the SDK relative to the project dir where it reads
# qvac.config.json — a global-only SDK install will boot but load zero models
# (qvac doctor flags this as "@qvac/sdk resolvable from project — not found").
if [[ ! -f package.json ]]; then
  npm init -y >/dev/null
fi
npm install @qvac/sdk

log "QVAC versions:"
qvac --version || true
npm list --depth=0 2>/dev/null | grep -E '@qvac/' || true

log "Verifying qvac CLI is on PATH..."
command -v qvac || { echo "qvac CLI not found on PATH"; exit 1; }

log "Copying qvac.config.json into place (Pi-friendly: small LLM + small embedding)..."
cp "$(dirname "$0")/qvac.config.json" ./qvac.config.json
cat ./qvac.config.json

log "Running qvac doctor — the '@qvac/sdk resolvable from project' check must be ✅."
qvac doctor || true

log "Install complete. Next: bash ./03-smoke-test.sh"
log "To start the server manually: qvac serve openai"
