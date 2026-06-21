#!/usr/bin/env python3
"""
panki_demo.py — Show the value of grounding: same question, asked two ways.

  1. UNGROUNDED: the raw model alone (what you saw hallucinate "Beef Product Operation").
  2. GROUNDED:   the SAME model, constrained to retrieved BPOM ground-truth chunks
                 and told to cite them and not invent anything.

Zero external dependencies — uses only the Python standard library, so it runs with
plain `python3 panki_demo.py` (no venv, no pip). Talks to any OpenAI-compatible chat
server (QVAC Fabric's llama-server, Ollama, etc.) at /v1/chat/completions.

Retrieval here is simple lexical overlap over the 10 fake chunks — enough to prove the
mechanism on a tiny corpus. Swap in real embeddings + real BPOM data later (see
toy_panki.py for the embeddings version).

Usage:
  python3 panki_demo.py
  python3 panki_demo.py --product "Functional beverage with ginseng extract and 150 mg caffeine"
  python3 panki_demo.py --base-url http://localhost:11434/v1 --model qwen3
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

STOP = {
    "the", "a", "an", "and", "or", "of", "for", "to", "in", "with", "is", "are",
    "be", "this", "that", "dan", "yang", "atau", "untuk", "dengan", "pada",
}


def tokenize(text: str) -> list[str]:
    return [t for t in re.split(r"[^a-z0-9]+", text.lower()) if len(t) > 2 and t not in STOP]


def retrieve(product: str, chunks: list[dict], k: int = 3) -> list[dict]:
    """Rank chunks by lexical overlap with the product; category matches weighted higher."""
    q = set(tokenize(product))
    scored = []
    for c in chunks:
        body = tokenize(
            c.get("category", "") + " " + c.get("text", "") + " "
            + " ".join(c.get("test_parameters", []))
        )
        overlap = sum(1 for t in body if t in q)
        cat_bonus = 2 * sum(1 for t in tokenize(c.get("category", "")) if t in q)
        scored.append((overlap + cat_bonus, c))
    scored.sort(key=lambda x: -x[0])
    top = [c for s, c in scored[:k] if s > 0]
    return top or [scored[0][1]]


def strip_think(text: str) -> str:
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def chat(base_url: str, model: str, messages: list[dict], max_tokens: int = 300) -> str:
    url = base_url.rstrip("/") + "/chat/completions"
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read())
        return strip_think(data["choices"][0]["message"]["content"])
    except urllib.error.URLError as e:
        sys.exit(f"\n[error] cannot reach {url}: {e}\n"
                 f"        Is llama-server running on that host/port?\n")
    except (KeyError, json.JSONDecodeError) as e:
        sys.exit(f"\n[error] unexpected response from server: {e}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://localhost:11434/v1")
    ap.add_argument("--model", default="qwen3",
                    help="llama-server ignores this and uses the loaded model")
    ap.add_argument("--corpus", default=str(Path(__file__).with_name("fake-bpom.json")))
    ap.add_argument("--product",
                    default="Packaged sweet biscuits made from wheat flour, sugar and palm oil, baked and sealed in film.")
    args = ap.parse_args()

    chunks = json.loads(Path(args.corpus).read_text(encoding="utf-8"))
    question = (
        "What are the mandatory BPOM laboratory test parameters for this product? "
        f"Product: {args.product}"
    )

    print("=" * 72)
    print("PRODUCT:", args.product)
    print("=" * 72)

    # 1) Ungrounded — the raw model, no ground truth.
    print("\n--- (1) UNGROUNDED: model alone, no ground truth ---\n")
    print(chat(args.base_url, args.model, [
        {"role": "system", "content": "You are a BPOM regulatory assistant. /no_think"},
        {"role": "user", "content": question},
    ]))

    # 2) Retrieve from the ground-truth corpus.
    hits = retrieve(args.product, chunks, k=3)
    print("\n--- (2) RETRIEVED GROUND-TRUTH CHUNKS ---\n")
    for c in hits:
        params = ", ".join(c.get("test_parameters", []))
        print(f"  [{c['id']}] {c['regulation']} {c.get('article', '')}")
        print(f"        required tests: {params}")

    # 3) Grounded — same model, constrained to the retrieved chunks.
    context = "\n\n".join(
        f"[{c['id']}] {c['regulation']} {c.get('article', '')}\n"
        f"{c['text']}\nRequired tests: {', '.join(c.get('test_parameters', []))}"
        for c in hits
    )
    print("\n--- (3) GROUNDED: same model, constrained to those chunks ---\n")
    print(chat(args.base_url, args.model, [
        {"role": "system", "content": (
            "You are a BPOM regulatory assistant. Answer ONLY using the provided regulation "
            "chunks. Cite the chunk IDs you used in square brackets like [id]. If the chunks "
            "do not cover the product, say so plainly. Never invent regulation numbers or test "
            "parameters. /no_think"
        )},
        {"role": "user", "content": f"REGULATION CHUNKS:\n{context}\n\nQUESTION: {question}"},
    ]))
    print("\n" + "=" * 72)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
