"""
bench.py — Measure tokens/sec, time-to-first-token (TTFT), and total latency
against the QVAC OpenAI-compatible server. Runs N completions and prints stats.

Pair with metrics/capture.sh in another terminal to correlate inference load
with RAM / temp / load average.

Usage:
    pip install openai
    python bench.py --base-url http://localhost:11434/v1 --runs 10
"""

from __future__ import annotations

import argparse
import os
import statistics
import sys
import time

from openai import OpenAI


PROMPTS = [
    "Name two mandatory BPOM laboratory tests for packaged biscuits.",
    "Which BPOM regulation covers carbonated beverage sweeteners?",
    "List the heavy metal limits for processed dairy products under BPOM rules.",
    "What microbiological tests apply to pasteurized milk in Indonesia?",
    "Summarize the BPOM labeling requirements for processed food in two sentences.",
]


def run_once(client: OpenAI, model: str, prompt: str, max_tokens: int) -> dict:
    t0 = time.time()
    first_tok = None
    out_tokens = 0
    full = []
    stream = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2,
        max_tokens=max_tokens,
        stream=True,
    )
    for chunk in stream:
        delta = chunk.choices[0].delta.content if chunk.choices else None
        if delta:
            if first_tok is None:
                first_tok = time.time()
            full.append(delta)
            out_tokens += max(1, len(delta) // 4)
    t1 = time.time()
    return {
        "prompt": prompt,
        "ttft_s": (first_tok - t0) if first_tok else None,
        "total_s": t1 - t0,
        "out_tokens_est": out_tokens,
        "tok_per_s": out_tokens / max(1e-6, t1 - (first_tok or t0)),
        "text_len": sum(len(s) for s in full),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://localhost:11434/v1")
    ap.add_argument("--api-key", default=os.environ.get("QVAC_API_KEY", "no-key"))
    ap.add_argument("--model", default="panki-llm")
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--max-tokens", type=int, default=120)
    args = ap.parse_args()

    client = OpenAI(base_url=args.base_url, api_key=args.api_key)

    print(f"[bench] {args.runs} runs against {args.base_url} model={args.model}")
    results = []
    for i in range(args.runs):
        prompt = PROMPTS[i % len(PROMPTS)]
        r = run_once(client, args.model, prompt, args.max_tokens)
        results.append(r)
        print(
            f"  run {i+1:>2}: ttft={r['ttft_s']:.2f}s "
            f"total={r['total_s']:.2f}s "
            f"~{r['tok_per_s']:.1f} tok/s "
            f"chars={r['text_len']}"
        )

    def stat(name, vals):
        if not vals:
            return f"{name}: -"
        return (
            f"{name}: min={min(vals):.2f} "
            f"median={statistics.median(vals):.2f} "
            f"max={max(vals):.2f}"
        )

    print("\n[bench] summary")
    print(" ", stat("TTFT (s)", [r["ttft_s"] for r in results if r["ttft_s"]]))
    print(" ", stat("Total (s)", [r["total_s"] for r in results]))
    print(" ", stat("tok/s   ", [r["tok_per_s"] for r in results]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
