"""
bench.py — Structured inference audit log + benchmark for the QVAC Fabric /
llama-server OpenAI-compatible endpoint.

Writes a JSON Lines (.jsonl) audit log capturing, for one run:
  - a `model_load`   event  (model id, base_url, cold-start warmup TTFT, RSS)
  - one `inference`  record per call: prompt, prompt_tokens, completion_tokens,
    ttft_s, gen_s, total_s, tokens_per_s   (real tokens from the API `usage`
    field; falls back to a char/4 estimate if the server omits usage)
  - a `model_unload` event  (session end)
  - a `summary`      record (medians / min / max)

For the *authoritative* model load/unload timing (true load_ms + resident RAM
measured by wrapping the server start/stop), use metrics/run_audit.sh, which
calls this script with --no-model-events so events aren't double-logged.

Pair with metrics/capture.sh in another terminal to correlate inference load
with RAM / temp / load average.

Usage:
    pip install openai
    python bench.py --base-url http://localhost:11434/v1 --model panki-llm \
        --runs 10 --log audit-$(date +%Y%m%d-%H%M%S).jsonl
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import time
from datetime import datetime, timezone

from openai import OpenAI


PROMPTS = [
    "Name two mandatory BPOM laboratory tests for packaged biscuits.",
    "Which BPOM regulation covers carbonated beverage sweeteners?",
    "List the heavy metal limits for processed dairy products under BPOM rules.",
    "What microbiological tests apply to pasteurized milk in Indonesia?",
    "Summarize the BPOM labeling requirements for processed food in two sentences.",
]


def _iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _rss_mb(pid: int | None) -> float | None:
    """Resident set size of a process in MB (Linux /proc; None elsewhere)."""
    if not pid:
        return None
    try:
        with open(f"/proc/{pid}/status") as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    return round(int(line.split()[1]) / 1024, 1)
    except OSError:
        return None
    return None


def _emit(record: dict, fh) -> None:
    if fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
        fh.flush()


def run_once(client: OpenAI, model: str, prompt: str, max_tokens: int) -> dict:
    t0 = time.time()
    first_tok = None
    out = []
    usage = None
    stream = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2,
        max_tokens=max_tokens,
        stream=True,
        stream_options={"include_usage": True},
    )
    for chunk in stream:
        # The final usage chunk carries `usage` and an empty `choices` list.
        if getattr(chunk, "usage", None):
            usage = chunk.usage
        if chunk.choices:
            delta = chunk.choices[0].delta.content
            if delta:
                if first_tok is None:
                    first_tok = time.time()
                out.append(delta)
    t1 = time.time()

    full = "".join(out)
    if usage and getattr(usage, "completion_tokens", None):
        prompt_tokens = usage.prompt_tokens
        completion_tokens = usage.completion_tokens
        tokens_source = "api"
    else:
        prompt_tokens = max(1, len(prompt) // 4)
        completion_tokens = max(1, len(full) // 4)
        tokens_source = "estimate"

    gen_s = t1 - (first_tok or t0)
    return {
        "type": "inference",
        "ts": _iso(t0),
        "model": model,
        "prompt": prompt,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "tokens_source": tokens_source,
        "ttft_s": round(first_tok - t0, 3) if first_tok else None,
        "gen_s": round(gen_s, 3),
        "total_s": round(t1 - t0, 3),
        "tokens_per_s": round(completion_tokens / max(1e-6, gen_s), 2),
        "chars": len(full),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://localhost:11434/v1")
    ap.add_argument("--api-key", default=os.environ.get("QVAC_API_KEY", "no-key"))
    ap.add_argument("--model", default="panki-llm")
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--max-tokens", type=int, default=120)
    ap.add_argument("--log", default=None,
                    help="append a JSONL audit log to this path")
    ap.add_argument("--server-pid", type=int, default=None,
                    help="llama-server PID, to record resident RAM (RSS)")
    ap.add_argument("--no-model-events", action="store_true",
                    help="skip model_load/model_unload (run_audit.sh logs the "
                         "authoritative ones)")
    args = ap.parse_args()

    client = OpenAI(base_url=args.base_url, api_key=args.api_key)
    log_fh = open(args.log, "a", encoding="utf-8") if args.log else None

    print(f"[bench] {args.runs} runs against {args.base_url} model={args.model}"
          + (f" -> {args.log}" if args.log else ""))

    if not args.no_model_events:
        # A warmup call forces a cold model into memory; its TTFT approximates
        # the load cost. (run_audit.sh measures true load_ms by wrapping start.)
        warm_t0 = time.time()
        warm = run_once(client, args.model, "ping", max_tokens=1)
        _emit({
            "type": "model_load",
            "ts": _iso(warm_t0),
            "model": args.model,
            "base_url": args.base_url,
            "warmup_ttft_s": warm["ttft_s"],
            "rss_mb": _rss_mb(args.server_pid),
            "note": "warmup-based estimate; see run_audit.sh for true load_ms",
        }, log_fh)

    results = []
    for i in range(args.runs):
        prompt = PROMPTS[i % len(PROMPTS)]
        r = run_once(client, args.model, prompt, args.max_tokens)
        results.append(r)
        _emit(r, log_fh)
        print(
            f"  run {i + 1:>2}: ttft={r['ttft_s']:.2f}s "
            f"total={r['total_s']:.2f}s "
            f"~{r['tokens_per_s']:.1f} tok/s "
            f"({r['completion_tokens']} {r['tokens_source']} tok)"
        )

    def _stats(vals):
        return {
            "min": round(min(vals), 2),
            "median": round(statistics.median(vals), 2),
            "max": round(max(vals), 2),
        } if vals else None

    summary = {
        "type": "summary",
        "ts": _iso(time.time()),
        "runs": len(results),
        "model": args.model,
        "ttft_s": _stats([r["ttft_s"] for r in results if r["ttft_s"]]),
        "total_s": _stats([r["total_s"] for r in results]),
        "tokens_per_s": _stats([r["tokens_per_s"] for r in results]),
    }
    _emit(summary, log_fh)

    if not args.no_model_events:
        _emit({
            "type": "model_unload",
            "ts": _iso(time.time()),
            "model": args.model,
            "note": "session end (bench.py leaves the server running)",
        }, log_fh)

    print("\n[bench] summary")
    print("  TTFT (s):  ", summary["ttft_s"])
    print("  Total (s): ", summary["total_s"])
    print("  tok/s:     ", summary["tokens_per_s"])
    if log_fh:
        log_fh.close()
        print(f"\n[bench] audit log written: {args.log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
