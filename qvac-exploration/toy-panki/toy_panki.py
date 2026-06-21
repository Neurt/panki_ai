"""
toy_panki.py — End-to-end Panki Edge sanity check.

What it proves:
  1. A Python client can talk to QVAC's OpenAI-compatible server (no LangChain
     dependency needed for the smoke; LangGraph wraps the same primitives).
  2. The classify -> retrieve -> reason loop closes against a tiny fake BPOM
     corpus, end to end, with citations.
  3. The confidence gate (Panki Edge delegation rule) fires on a borderline
     product. Delegation itself is stubbed — we print what would happen.

Run on the Pi (or any machine with reachable QVAC server):
  pip install -r requirements.txt
  python toy_panki.py --base-url http://localhost:11434/v1
  python toy_panki.py --base-url http://<pi-ip>:11434/v1 --product "Functional beverage with ginseng extract, vitamin B-complex, 150 mg caffeine"
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
from openai import OpenAI


CLS_CONFIDENCE_THRESHOLD = 0.70
RETRIEVAL_SCORE_THRESHOLD = 0.55

CATEGORIES = [
    "biscuits",
    "beverages",
    "supplements",
    "dairy",
    "functional_beverages",
]

CLASSIFY_SYSTEM = (
    "You are a BPOM product classifier. Given a product description, "
    "return a single JSON object with keys: category (one of: "
    + ", ".join(CATEGORIES)
    + "), confidence (0-1 float), reasoning (one short sentence). "
    "Reply with ONLY the JSON object, nothing else."
)

ANSWER_SYSTEM = (
    "You are Panki, a BPOM regulatory assistant. You are given a product "
    "description and a list of retrieved BPOM regulation chunks. "
    "Recommend the mandatory test parameters for this product, citing the "
    "regulation IDs you used. Never invent regulation IDs that are not in "
    "the retrieved chunks. If the product appears borderline between "
    "categories, say so explicitly."
)


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    denom = (np.linalg.norm(a) * np.linalg.norm(b)) or 1e-9
    return float(np.dot(a, b) / denom)


def embed(client: OpenAI, texts: list[str], model: str) -> np.ndarray:
    resp = client.embeddings.create(model=model, input=texts)
    return np.array([d.embedding for d in resp.data], dtype=np.float32)


def parse_json_blob(s: str) -> dict:
    s = s.strip()
    start, end = s.find("{"), s.rfind("}")
    if start == -1 or end == -1:
        raise ValueError(f"no JSON object in: {s!r}")
    return json.loads(s[start : end + 1])


def classify(client: OpenAI, product: str, llm_model: str) -> dict:
    resp = client.chat.completions.create(
        model=llm_model,
        messages=[
            {"role": "system", "content": CLASSIFY_SYSTEM},
            {"role": "user", "content": product},
        ],
        temperature=0.0,
        max_tokens=200,
    )
    raw = resp.choices[0].message.content or ""
    try:
        return parse_json_blob(raw)
    except Exception as e:
        print(f"[warn] classifier returned non-JSON: {e}\nraw: {raw}", file=sys.stderr)
        return {"category": "unknown", "confidence": 0.0, "reasoning": raw}


def retrieve(
    client: OpenAI,
    product: str,
    chunks: list[dict],
    chunk_embeds: np.ndarray,
    embed_model: str,
    k: int = 4,
) -> list[tuple[float, dict]]:
    q = embed(client, [product], embed_model)[0]
    sims = chunk_embeds @ q / (
        np.linalg.norm(chunk_embeds, axis=1) * np.linalg.norm(q) + 1e-9
    )
    order = np.argsort(-sims)[:k]
    return [(float(sims[i]), chunks[i]) for i in order]


def should_delegate(cls: dict, retrieval: list[tuple[float, dict]]) -> tuple[bool, str]:
    conf = float(cls.get("confidence", 0.0))
    top_score = retrieval[0][0] if retrieval else 0.0
    if conf < CLS_CONFIDENCE_THRESHOLD:
        return True, f"classifier confidence {conf:.2f} < {CLS_CONFIDENCE_THRESHOLD}"
    if top_score < RETRIEVAL_SCORE_THRESHOLD:
        return True, f"top retrieval score {top_score:.2f} < {RETRIEVAL_SCORE_THRESHOLD}"
    return False, f"local inference: conf={conf:.2f}, top_score={top_score:.2f}"


def answer(
    client: OpenAI,
    product: str,
    category: str,
    retrieval: list[tuple[float, dict]],
    llm_model: str,
) -> tuple[str, float]:
    chunks_text = "\n\n".join(
        f"[{c['id']} | {c['regulation']} {c['article']}] {c['text']}"
        for _, c in retrieval
    )
    user = (
        f"PRODUCT: {product}\n"
        f"CANDIDATE CATEGORY: {category}\n\n"
        f"RETRIEVED BPOM CHUNKS:\n{chunks_text}\n\n"
        "Recommend the mandatory test parameters and cite the chunk IDs used."
    )
    t0 = time.time()
    resp = client.chat.completions.create(
        model=llm_model,
        messages=[
            {"role": "system", "content": ANSWER_SYSTEM},
            {"role": "user", "content": user},
        ],
        temperature=0.2,
        max_tokens=400,
    )
    dt = time.time() - t0
    return resp.choices[0].message.content or "", dt


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://localhost:11434/v1")
    ap.add_argument("--api-key", default=os.environ.get("QVAC_API_KEY", "no-key"))
    ap.add_argument("--llm-model", default="panki-llm")
    ap.add_argument("--embed-model", default="panki-embed")
    ap.add_argument(
        "--product",
        default="Packaged sweet biscuits with wheat flour, sugar, palm oil, baked then packed in metallized film. Ambient shelf storage.",
    )
    ap.add_argument(
        "--corpus",
        default=str(Path(__file__).with_name("fake-bpom.json")),
    )
    args = ap.parse_args()

    client = OpenAI(base_url=args.base_url, api_key=args.api_key)

    print(f"[panki] connecting to {args.base_url}")
    print(f"[panki] product: {args.product!r}\n")

    chunks = json.loads(Path(args.corpus).read_text(encoding="utf-8"))
    print(f"[panki] embedding {len(chunks)} BPOM chunks...")
    chunk_embeds = embed(client, [c["text"] for c in chunks], args.embed_model)

    print("[panki] classifying...")
    cls = classify(client, args.product, args.llm_model)
    print(f"        -> {json.dumps(cls, ensure_ascii=False)}")

    print("[panki] retrieving top 4 chunks...")
    retrieval = retrieve(client, args.product, chunks, chunk_embeds, args.embed_model, k=4)
    for score, c in retrieval:
        print(f"        {score:+.3f}  {c['id']}")

    delegate, reason = should_delegate(cls, retrieval)
    print(f"\n[panki] delegation decision: {'DELEGATE' if delegate else 'LOCAL'} ({reason})")
    if delegate:
        print(
            "        [stub] would call loadModel({delegate: {providerPublicKey, "
            "fallbackToLocal: true}}). Running local for the demo."
        )

    print("\n[panki] generating answer...")
    out, dt = answer(client, args.product, cls.get("category", "unknown"), retrieval, args.llm_model)
    print(f"\n--- PANKI ANSWER ({dt:.2f}s) ---\n{out}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
