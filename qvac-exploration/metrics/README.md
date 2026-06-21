# Metrics & audit log

Structured telemetry for the QVAC Fabric inference node on the Raspberry Pi 4B.
Captures **model load/unload events** and **per-call inference performance**
(prompt, real token counts, TTFT, tokens/sec, latency) as a JSON Lines audit log,
plus optional system resource sampling (RAM / CPU temp / load).

## Files

| File | Purpose |
|---|---|
| `run_audit.sh` | **One-command full capture.** Wraps `llama-server` start/stop to record the *true* model load time + resident RAM, runs the benchmark, and writes a complete `audit-<ts>.jsonl`. |
| `bench.py` | Drives N inference calls; logs each as a structured record with real token counts from the API `usage` field (estimate fallback). Usable standalone. |
| `capture.sh` | Samples RAM / CPU temp / 1-min load at 1 Hz to a CSV — run alongside a capture to correlate inference load with system pressure. |
| `sample-audit-log.jsonl` | **Representative example** of the output format (see note below). |

> ⚠️ **`sample-audit-log.jsonl` is illustrative, not a live capture.** Its values
> are representative of the Pi 4B running Qwen2.5-1.5B-Q4_K_M (the project's
> measured ~4 tok/s, ~1.5 GB resident) and are provided so the schema is concrete
> without hardware. The first line is a `meta` record flagging this. Replace it
> with a real run using the command below.

## Capture a real run (on the Pi)

```bash
pip install openai
cd qvac-exploration
./metrics/run_audit.sh ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf 10 panki-llm
# optional, in a second terminal, for system metrics over the same window:
./metrics/capture.sh 300
```

Output: `metrics/audit-<timestamp>.jsonl`.

## Audit log schema (JSON Lines)

One JSON object per line. Record `type`s, in order:

- **`model_load`** — `model`, `model_path`, `load_ms` (true wall-clock load when
  via `run_audit.sh`), `rss_mb` (resident RAM after load), `server_pid`.
- **`inference`** — `prompt`, `prompt_tokens`, `completion_tokens`,
  `tokens_source` (`api` = real counts, `estimate` = char/4 fallback),
  `ttft_s` (time to first token), `gen_s` (generation time), `total_s`,
  `tokens_per_s`, `chars`.
- **`summary`** — min / median / max of `ttft_s`, `total_s`, `tokens_per_s`.
- **`model_unload`** — emitted when the server is stopped.

Analyze with standard tools, e.g.:

```bash
# median tokens/sec across the run
grep '"type":"inference"' audit-*.jsonl | jq -s 'map(.tokens_per_s) | add/length'
# the model-load event
grep '"type":"model_load"' audit-*.jsonl | jq
```
