# Ollama fallback — temporary dev backend while QVAC #1823 is open

> **Why this file exists.** QVAC 0.12.2 cannot load its `llm-llamacpp` worker on Pi 4B (linux-arm64) due to upstream bug [tetherto/qvac#1823](https://github.com/tetherto/qvac/issues/1823) — the native binding crashes during init, even with `device: cpu`. Until that is fixed, we use Ollama as a drop-in OpenAI-compatible server on the Pi so that the rest of the Panki Edge work can move forward.
>
> **Scope.** This is *not* a change to the Panki Edge architecture or proposal. QVAC remains the target inference runtime in [`../PANKI-EDGE-ADDENDUM.md`](../PANKI-EDGE-ADDENDUM.md). When #1823 is fixed we swap servers; the LangGraph client and Panki pipeline don't change because both QVAC and Ollama expose the same OpenAI API on `:11434/v1/`.

---

## What stays the same when we swap to Ollama

- Port: `11434` (Ollama default, also QVAC default)
- Endpoint shape: `POST /v1/chat/completions`, `POST /v1/embeddings`, `GET /v1/models`
- `toy_panki.py` source code — **no changes**, only different `--llm-model` / `--embed-model` names
- The confidence-gated delegation rule (still works; QVAC peer can be on another machine where QVAC runs)
- The metrics capture and bench scripts

## What changes

| Concern | QVAC (target) | Ollama (current) |
|---|---|---|
| Server command | `qvac serve openai` | `systemctl --user status ollama` (runs as system service) |
| Config file | `qvac.config.json` | none — models pulled imperatively |
| LLM model name | `panki-llm` (alias for `QWEN3_600M_INST_Q4`) | `qwen2.5:0.5b` (direct Ollama tag) |
| Embedding model name | `panki-embed` (alias for `GTE_LARGE_FP16`) | `nomic-embed-text` |
| P2P delegation | `loadModel({ delegate: { providerPublicKey, fallbackToLocal: true } })` | Not available natively; demo P2P from a working-QVAC machine separately, or stub for now |

The only thing Ollama cannot do is QVAC's P2P delegation. That feature stays demoed *on the day* via a working-QVAC host (desktop or non-bug-affected SBC); on the Pi we show the local-inference half of the loop.

---

## Setup — one time on the Pi

```bash
# 1. Make sure nothing is on the port
sudo fuser -k 11434/tcp 2>/dev/null
sleep 2
ss -tlnp 2>/dev/null | grep 11434       # must print nothing

# 2. Install Ollama (auto-starts as systemd service)
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama
ollama --version

# 3. Pull a small chat model + an embedding model
ollama pull qwen2.5:0.5b               # ~400 MB, comparable role to QWEN3_600M_INST_Q4
ollama pull nomic-embed-text           # ~270 MB, replaces GTE_LARGE_FP16 role
ollama list

# 4. Sanity-check the OpenAI-compatible endpoint
curl -s http://localhost:11434/v1/models | python3 -m json.tool
curl -s http://localhost:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5:0.5b","messages":[{"role":"user","content":"Say hi in one word."}],"max_tokens":10}' \
  | python3 -m json.tool
```

If both `curl` calls succeed, the Pi is now a working OpenAI-compatible LLM host.

## Run the toy Panki loop against Ollama

```bash
cd ~/qvac-exploration/toy-panki
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Clear-cut product (should classify locally, decision = LOCAL)
python toy_panki.py \
  --llm-model qwen2.5:0.5b \
  --embed-model nomic-embed-text

# Borderline product (should hit confidence gate, decision = DELEGATE)
python toy_panki.py \
  --llm-model qwen2.5:0.5b \
  --embed-model nomic-embed-text \
  --product "Functional beverage with ginseng extract, vitamin B-complex, 150 mg caffeine"
```

## Capture the A1 / A2 numbers the addendum is waiting on

In one shell:

```bash
cd ~/qvac-exploration/metrics
chmod +x capture.sh
./capture.sh 180             # 3-minute sampler, writes metrics-*.csv
```

In another shell (start it within the same 3 minutes):

```bash
cd ~/qvac-exploration/toy-panki
source .venv/bin/activate
python ../metrics/bench.py \
  --base-url http://localhost:11434/v1 \
  --model qwen2.5:0.5b \
  --runs 10
```

The bench prints TTFT / total / tok/s; the capture prints peak RAM and max temperature. Both feed directly into the A1/A2 decision in the addendum.

## When QVAC #1823 is fixed

1. `npm install @qvac/sdk@latest @qvac/cli@latest` in `qvac-exploration/`
2. `./node_modules/.bin/qvac doctor` → all ✅
3. Stop Ollama (`sudo systemctl stop ollama`) or run QVAC on a different port
4. `./node_modules/.bin/qvac serve openai` with the existing `qvac.config.json`
5. Re-run `toy_panki.py` with `--llm-model panki-llm --embed-model panki-embed`
6. Re-run the bench. Compare numbers.

No code change in `toy_panki.py`, no architecture change in the addendum.
