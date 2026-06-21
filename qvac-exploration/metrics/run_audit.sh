#!/usr/bin/env bash
# run_audit.sh — Capture ONE full structured audit run on the Pi.
#
# Starts llama-server (recording the REAL model-load time + resident RAM),
# runs the inference benchmark against it, then stops the server (recording the
# model unload). The result is a single JSON Lines audit log:
#
#     metrics/audit-<timestamp>.jsonl
#
# It contains: model_load -> inference (xN) -> summary -> model_unload.
# See metrics/README.md for the schema. Run metrics/capture.sh in another shell
# to also capture system RAM/temp/load as a CSV over the same window.
#
# Usage:
#     ./run_audit.sh /path/to/model.gguf [runs] [model-name]
#     ./run_audit.sh ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf 10 panki-llm

set -euo pipefail

MODEL_PATH="${1:?usage: ./run_audit.sh <model.gguf> [runs] [model-name]}"
RUNS="${2:-10}"
NAME="${3:-panki-llm}"
PORT="${PORT:-11434}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="${HERE}/audit-${TS}.jsonl"
SRVLOG="$(mktemp)"
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cleanup() {
  [[ -n "${SRV_PID:-}" ]] && kill "$SRV_PID" 2>/dev/null || true
  rm -f "$SRVLOG"
}
trap cleanup EXIT

echo "[audit] starting llama-server: $MODEL_PATH"
t_start=$(date +%s.%N)
llama-server -m "$MODEL_PATH" -c 2048 --host 127.0.0.1 --port "$PORT" \
  --alias "$NAME" >"$SRVLOG" 2>&1 &
SRV_PID=$!

# Wait until the model is loaded and the HTTP server is accepting requests.
# (Readiness strings vary slightly across llama.cpp builds — adjust if needed.)
ready=0
for _ in $(seq 1 180); do
  if grep -qiE "model loaded|server is listening|HTTP server listening|all slots are idle|waiting for new tasks" "$SRVLOG"; then
    ready=1; break
  fi
  if ! kill -0 "$SRV_PID" 2>/dev/null; then
    echo "[audit] server exited during load:"; cat "$SRVLOG"; exit 1
  fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || { echo "[audit] timed out waiting for server"; cat "$SRVLOG"; exit 1; }

t_ready=$(date +%s.%N)
load_ms=$(awk "BEGIN{printf \"%.0f\", ($t_ready-$t_start)*1000}")
rss_kb=$(awk '/VmRSS/{print $2}' "/proc/$SRV_PID/status" 2>/dev/null || true)
if [[ -n "$rss_kb" ]]; then
  rss_mb=$(awk "BEGIN{printf \"%.1f\", $rss_kb/1024}")
else
  rss_mb="null"
fi

# Authoritative model_load event (true wall-clock load + resident RAM).
printf '{"type":"model_load","ts":"%s","model":"%s","model_path":"%s","load_ms":%s,"rss_mb":%s,"server_pid":%s,"source":"server-wrapped"}\n' \
  "$(iso)" "$NAME" "$MODEL_PATH" "$load_ms" "$rss_mb" "$SRV_PID" >>"$LOG"
echo "[audit] model loaded in ${load_ms}ms, RSS ${rss_mb}MB"

# Inference records appended by bench.py (its own load/unload events suppressed).
python3 "${HERE}/bench.py" \
  --base-url "http://127.0.0.1:${PORT}/v1" \
  --model "$NAME" --runs "$RUNS" \
  --log "$LOG" --no-model-events --server-pid "$SRV_PID"

# Stop the server -> model unload.
echo "[audit] stopping server (model unload)"
kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
printf '{"type":"model_unload","ts":"%s","model":"%s","server_pid":%s,"source":"server-wrapped"}\n' \
  "$(iso)" "$NAME" "$SRV_PID" >>"$LOG"
SRV_PID=""

echo "[audit] done -> $LOG"
