#!/usr/bin/env bash
# 04-build-qvac-fabric.sh — Build QVAC's Fabric LLM engine FROM SOURCE on the Pi 4B.
#
# Why: the prebuilt npm @qvac/llm-llamacpp binary is compiled for ARMv8.2 (dotprod/
# FP16) and SIGILLs on the Pi 4B's Cortex-A72 (ARMv8.0). Building here, GGML_NATIVE
# auto-detects THIS CPU and emits A72-safe code. Result: QVAC's own engine running
# locally on the Pi, exposing an OpenAI-compatible server on :11434 — same /v1/ API
# the prebuilt one would have, so toy_panki.py works unchanged.
#
# Engine: https://github.com/tetherto/qvac-fabric-llm.cpp (MIT)
#
# Run inside tmux — the compile takes ~30-45 min on a Pi 4B.
#   tmux new -s build   (detach: Ctrl+B then D ; reattach: tmux attach -t build)

set -euo pipefail

log()  { printf '\n\033[1;36m[fabric]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[fabric]\033[0m %s\n' "$*" >&2; exit 1; }

JOBS="${JOBS:-2}"   # keep low on 4 GB RAM to avoid OOM during compile; override: JOBS=3 ./04-...
SRC="$HOME/qvac-fabric-llm.cpp"

# --- 0. Sanity ---
[[ "$(uname -m)" == "aarch64" ]] || fail "Not aarch64."
log "CPU: $(grep -m1 'model name\|Hardware\|CPU part' /proc/cpuinfo || true)"
log "Building with -j$JOBS (set JOBS=N to change)."

# --- 1. Build deps ---
log "Installing build dependencies..."
sudo apt-get update -y
sudo apt-get install -y git cmake build-essential libcurl4-openssl-dev

# --- 2. Get the source ---
if [[ -d "$SRC/.git" ]]; then
  log "Source already cloned; pulling latest..."
  git -C "$SRC" pull --ff-only || true
else
  log "Cloning qvac-fabric-llm.cpp..."
  git clone --depth 1 https://github.com/tetherto/qvac-fabric-llm.cpp.git "$SRC"
fi
cd "$SRC"

# --- 3. Configure (GGML_NATIVE on = target THIS Cortex-A72) ---
log "Configuring CMake (CPU build, native arch = Cortex-A72)..."
# If GGML_NATIVE ever misdetects, swap the next line for:
#   cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON

# --- 4. Build (this is the slow part) ---
log "Compiling (~30-45 min on Pi 4B; if it OOMs, re-run with JOBS=1)..."
cmake --build build --config Release -j"$JOBS"

# --- 5. Verify the binaries run on the A72 (this is the SIGILL test) ---
log "Verifying binaries execute on this CPU (no illegal instruction)..."
./build/bin/llama-cli --version || fail "llama-cli failed to run — check the build log."

log "BUILD OK. Binaries are in $SRC/build/bin/ (llama-cli, llama-server, ...)."
cat <<EOF

Next:
  1. Quick proof the QVAC engine runs + answers on the Pi (downloads a tiny model):
       $SRC/build/bin/llama-cli -hf Qwen/Qwen2.5-0.5B-Instruct-GGUF \\
         -p "Name one mandatory BPOM laboratory test for packaged biscuits." -n 64

  2. Start the OpenAI-compatible server on :11434 (LAN-reachable):
       $SRC/build/bin/llama-server -hf Qwen/Qwen2.5-0.5B-Instruct-GGUF \\
         -c 2048 --host 0.0.0.0 --port 11434

  3. From another shell, point the Panki loop at it (unchanged client):
       curl -s http://localhost:11434/v1/models | python3 -m json.tool
EOF
