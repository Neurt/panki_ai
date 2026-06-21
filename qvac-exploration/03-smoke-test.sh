#!/usr/bin/env bash
# 03-smoke-test.sh — Start QVAC's OpenAI-compatible server, hit it with curl,
# and prove the LLM and embeddings endpoints both respond.
#
# Run from the directory that holds qvac.config.json (i.e. qvac-exploration/).

set -euo pipefail

log()  { printf '\n\033[1;36m[smoke]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[smoke]\033[0m %s\n' "$*" >&2; exit 1; }

export PATH="$HOME/.npm-global/bin:$PATH"

[[ -f qvac.config.json ]] || fail "qvac.config.json not found in cwd. cd into qvac-exploration/ first."

log "Starting qvac serve openai in background..."
nohup qvac serve openai > qvac-server.log 2>&1 &
QVAC_PID=$!
echo "$QVAC_PID" > qvac-server.pid

cleanup() {
  if kill -0 "$QVAC_PID" 2>/dev/null; then
    log "Stopping QVAC server (pid $QVAC_PID)..."
    kill "$QVAC_PID" || true
  fi
}
trap cleanup EXIT

log "Waiting for server on http://localhost:11434/v1/models (up to 120s, models may download on first run)..."
for i in $(seq 1 120); do
  if curl -fsS http://localhost:11434/v1/models > /tmp/qvac-models.json 2>/dev/null; then
    log "Server up after ${i}s."
    break
  fi
  sleep 1
  if [[ $i -eq 120 ]]; then
    log "Server did not respond in 120s. Tail of qvac-server.log:"
    tail -50 qvac-server.log
    fail "Server boot timeout."
  fi
done

log "Loaded models:"
cat /tmp/qvac-models.json

log "Chat completion smoke test (panki-llm)..."
time curl -fsS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "panki-llm",
    "messages": [
      {"role": "system", "content": "Reply with a single short sentence."},
      {"role": "user", "content": "Name one mandatory BPOM test for biscuits."}
    ],
    "max_tokens": 60
  }' | tee /tmp/qvac-chat.json
echo

log "Embeddings smoke test (panki-embed)..."
curl -fsS http://localhost:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"panki-embed","input":["packaged biscuit","sweetened carbonated beverage"]}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('embedding dims:', len(d['data'][0]['embedding']), 'count:', len(d['data']))"

log "Smoke test PASSED. Server log at $(pwd)/qvac-server.log"
log "Server still running until this script exits (pid $QVAC_PID). For long-lived: run 'qvac serve openai' directly."
