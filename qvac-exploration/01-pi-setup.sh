#!/usr/bin/env bash
# 01-pi-setup.sh — Bring a fresh Pi 4B up to QVAC's official Linux baseline.
#
# Target OS: Ubuntu Server 24.04 LTS arm64 (Raspberry Pi image).
# Run on the Pi as the default user. Idempotent: safe to re-run.
#
# Verified against QVAC docs on 2026-06-04:
#   - Linux: Ubuntu 22+, arm64/x64, Vulkan runtime required
#     https://docs.qvac.tether.io/installation/
#   - Node.js >= v22.17
#     https://docs.qvac.tether.io/installation/

set -euo pipefail

log() { printf '\n\033[1;36m[setup]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[setup]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Sanity checks ---------------------------------------------------------

log "Checking architecture..."
arch="$(uname -m)"
if [[ "$arch" != "aarch64" ]]; then
  fail "Expected aarch64 (arm64), got $arch. Are you on a 64-bit OS? 32-bit Pi OS will not work."
fi

log "Checking Ubuntu version..."
if ! grep -qiE 'ubuntu' /etc/os-release; then
  log "WARNING: not Ubuntu. QVAC officially supports Ubuntu 22+. Continuing anyway."
fi

# --- Base packages ---------------------------------------------------------

log "Updating apt and installing base tools..."
sudo apt-get update -y
sudo apt-get install -y \
  curl ca-certificates gnupg lsb-release \
  build-essential git unzip pkg-config \
  python3 python3-venv python3-pip \
  htop lm-sensors

# --- Vulkan runtime (QVAC requirement on Linux) ----------------------------

log "Installing Mesa Vulkan drivers (v3dv for Pi 4 VideoCore VI)..."
sudo apt-get install -y mesa-vulkan-drivers vulkan-tools libvulkan1

log "Vulkan summary (must show v3dv device, otherwise QVAC will fall back to CPU):"
if ! vulkaninfo --summary 2>/dev/null | tee /tmp/vulkan-summary.txt; then
  log "WARNING: vulkaninfo failed. QVAC LLM inference will run CPU-only."
fi

# --- Node.js >= 22.17 via NodeSource (arm64) -------------------------------

log "Installing Node.js 22.x from NodeSource..."
if ! command -v node >/dev/null || [[ "$(node -v)" < "v22.17" ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

node_version="$(node -v)"
log "Node.js version: $node_version"
if [[ "$node_version" < "v22.17" ]]; then
  fail "Node.js $node_version is below the QVAC-required v22.17."
fi

# --- npm global prefix without sudo ----------------------------------------

log "Configuring npm global prefix to ~/.npm-global (avoids sudo for global installs)..."
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
if ! grep -q '.npm-global/bin' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.npm-global/bin:$PATH"

log "Setup complete. Next: bash ./02-install-qvac.sh"
