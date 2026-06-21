# qvac-exploration

Reality-check for the **Panki Edge** addendum: prove that QVAC actually runs on a Raspberry Pi 4B (4 GB) with our chosen models, then measure the numbers (latency, RAM, tokens/sec, temperature) before we commit those claims to the proposal.

> Read [`../PANKI-EDGE-ADDENDUM.md`](../PANKI-EDGE-ADDENDUM.md) first. The assumption table at the end of that doc (A1–A5) is what this folder validates.

## Folder map

```
qvac-exploration/
├── 01-pi-setup.sh         # Pi base prep: Vulkan, Node 22, npm prefix
├── 02-install-qvac.sh     # @qvac/sdk + @qvac/cli + config in place
├── 03-smoke-test.sh       # Start server, curl /v1/models, chat, embeddings
├── qvac.config.json       # Qwen3 0.6B Q4 (chat) + GTE-large FP16 (embeddings)
├── toy-panki/
│   ├── toy_panki.py       # Full classify -> retrieve -> reason -> delegate
│   ├── fake-bpom.json     # 10 fake-but-realistic BPOM chunks (ID, biscuits, beverages, supplements, dairy)
│   └── requirements.txt
└── metrics/
    ├── capture.sh         # 1 Hz CSV of RAM / CPU temp / load avg
    └── bench.py           # TTFT, total latency, tok/s over N runs
```

## Target host

- **Hardware:** Raspberry Pi 4B, 4 GB RAM, active cooling recommended (sustained inference will heat it).
- **OS (recommended):** Ubuntu Server 24.04 LTS arm64 (the QVAC-supported configuration).
- **OS (alt):** Raspberry Pi OS 64-bit Bookworm — works in practice (same glibc/Mesa lineage) but off the official QVAC matrix. Use this if you also plan to wire up GPIO/sensors.

These scripts are bash + Python; they expect a Linux shell. **Transfer them to the Pi before running** (e.g. `scp -r qvac-exploration pi@<ip>:~/`). On Windows-edited files you may need `dos2unix` if you see `\r`-not-found errors:

```bash
sudo apt-get install -y dos2unix
find qvac-exploration -type f \( -name '*.sh' -o -name '*.py' \) -exec dos2unix {} +
```

## Run order

```bash
# 1. On the Pi, once per fresh OS:
cd ~/qvac-exploration
chmod +x *.sh metrics/*.sh
bash ./01-pi-setup.sh          # installs Vulkan, Node 22, sets npm prefix
source ~/.bashrc               # pick up PATH change

# 2. Install QVAC:
bash ./02-install-qvac.sh      # global @qvac/sdk + @qvac/cli, copies qvac.config.json

# 3. Smoke test (will download models on first run — minutes, not seconds):
bash ./03-smoke-test.sh        # starts server, hits /v1/models, /v1/chat, /v1/embeddings

# 4. End-to-end Panki loop with the fake BPOM corpus:
cd toy-panki
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python toy_panki.py            # clear-cut biscuit example, should classify locally
python toy_panki.py --product "Functional beverage with ginseng extract, vitamin B-complex, 150 mg caffeine, claim to boost energy"
                               # borderline product, should trigger DELEGATE decision

# 5. Benchmark (run in parallel with metrics/capture.sh in another shell):
cd ../metrics
./capture.sh 120 &             # background, samples 120s
cd ../toy-panki
python ../metrics/bench.py --runs 10
```

## What "pass" looks like (decision gate)

The assumption table from `PANKI-EDGE-ADDENDUM.md`, with concrete pass criteria:

| # | Assumption | Pass criterion |
|---|---|---|
| A1 | Qwen3 0.6B Q4 inference usable | `bench.py` median tok/s ≥ **5**, median TTFT ≤ **3 s** |
| A2 | LLM + embeddings + vector DB co-resident | `capture.sh` max RAM used ≤ **3500 MB** during a full `toy_panki.py` run |
| A3 | Python LangGraph client reaches QVAC server | `toy_panki.py` returns a non-empty answer with at least 1 cited chunk ID |
| A4 | No thermal-throttle under 2-minute sustained inference | `capture.sh` max CPU temp < **82 °C** during 10-run bench |
| A5 | Delegation falls back cleanly | (later, with desktop peer) `loadModel({delegate: ..., fallbackToLocal: true})` returns a local answer when peer is unreachable |

If A1 or A2 fails, fall back in this order:

1. Swap embedding model to a smaller one (e.g. `gte-small`/`bge-small` — ~80 MB instead of ~700 MB).
2. Drop `ctx_size` from 2048 to 1024 in `qvac.config.json`.
3. Move the LLM to delegated-only mode (Pi does retrieval + control, desktop peer does inference). The architecture still holds; the headline weakens from "fully local on a $75 Pi" to "edge-first, peer-augmented."

## What this folder is *not*

- Not the final Panki Edge product. The reviewer UI, real BPOM corpus, audited regulation-sync job, and live metrics dashboard come later.
- Not a substitute for measuring the *real* corpus. 10 fake chunks confirm the pipeline closes; they do not validate retrieval quality on actual BPOM regulations.
- Not a benchmark with cache invalidation handled. The bench reuses prompts after the first cycle; numbers are best-case warm runs.

## Notes on QVAC specifics (verified 2026-06-04)

- HTTP server is OpenAI-compatible at `http://localhost:11434/v1/` (`qvac serve openai`). LangChain is on the official compatible-tools list. — https://docs.qvac.tether.io/cli/http-server/
- Node.js `>= v22.17` is required. — https://docs.qvac.tether.io/installation/
- Delegated-inference parameters are `providerPublicKey`, `timeout`, `fallbackToLocal`, `forceNewConnection`. There is **no `topic`** field and **no discovery phase** — peers connect directly by public key. — https://docs.qvac.tether.io/p2p-capabilities/delegated-inference/
