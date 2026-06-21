#!/usr/bin/env python3
"""
panki_mqtt_service.py — Pi-side bridge: MQTT <-> grounded Panki pipeline.

Subscribes to a request topic, runs the SAME grounded pipeline as panki_demo.py
(lexical retrieval over the BPOM corpus -> deterministic required-test list ->
llama-server writes the explanation), and publishes the answer back, echoing the
request's correlation id so the phone can match it.

Requires (install via apt, no pip/bzip2 needed):
    sudo apt install -y mosquitto mosquitto-clients python3-paho-mqtt

Run:
    python3 panki_mqtt_service.py
    python3 panki_mqtt_service.py --broker localhost --corpus ~/qvac-exploration/toy-panki/fake-bpom.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

import paho.mqtt.client as mqtt

STOP = {"the","a","an","and","or","of","for","to","in","with","is","are","be",
        "this","that","dan","yang","atau","untuk","dengan","pada"}


def tokenize(text):
    return [t for t in re.split(r"[^a-z0-9]+", text.lower()) if len(t) > 2 and t not in STOP]


def retrieve(product, chunks, k=3):
    q = set(tokenize(product))
    scored = []
    for c in chunks:
        body = tokenize(c.get("category","") + " " + c.get("text","") + " " + " ".join(c.get("test_parameters", [])))
        score = sum(1 for t in body if t in q) + 2 * sum(1 for t in tokenize(c.get("category","")) if t in q)
        scored.append((score, c))
    scored.sort(key=lambda x: -x[0])
    top = [c for s, c in scored[:k] if s > 0]
    return top or [scored[0][1]]


def strip_think(text):
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def llm_explain(base_url, facts, context, product, max_tokens=500, timeout=600):
    url = base_url.rstrip("/") + "/chat/completions"
    payload = json.dumps({
        "model": "panki",
        "messages": [
            {"role": "system", "content": (
                "You are a BPOM customer-service assistant. The mandatory tests are FIXED and "
                "given by the system - do NOT add, drop, or rename any. Using the regulation "
                "chunks, write a short, friendly explanation for a customer: state the required "
                "tests and briefly why each matters. Cite chunk IDs in [brackets]. /no_think")},
            {"role": "user", "content": (
                f"PRODUCT: {product}\n\nMANDATORY TESTS (authoritative, do not change):\n{facts}\n\n"
                f"REGULATION CHUNKS:\n{context}\n\nWrite the customer explanation.")},
        ],
        "max_tokens": max_tokens,
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return strip_think(json.loads(resp.read())["choices"][0]["message"]["content"])


def build_answer(product, chunks, base_url):
    hits = retrieve(product, chunks, k=3)
    category = hits[0].get("category", "unknown") if hits else "unknown"

    params, seen, rows = [], set(), []
    for c in hits:
        for p in c.get("test_parameters", []):
            if p.lower() not in seen:
                seen.add(p.lower())
                params.append({"name": p, "chunk_id": c["id"], "regulation": c["regulation"]})
                rows.append(f"  - {p}   [{c['id']}] {c['regulation']} {c.get('article','')}")
    facts = "\n".join(rows)
    citations = sorted({c["id"] for c in hits})
    context = "\n\n".join(f"[{c['id']}] {c['regulation']} {c.get('article','')}\n{c['text']}" for c in hits)

    try:
        explanation = llm_explain(base_url, facts, context, product)
    except (urllib.error.URLError, TimeoutError) as e:
        explanation = f"(LLM explanation unavailable: {e}. The required tests above are still authoritative.)"

    answer_text = "Required BPOM test parameters:\n" + \
        "\n".join(f"• {p['name']}  [{p['chunk_id']}]" for p in params) + \
        "\n\n" + explanation

    return {
        "category": category,
        "parameters": params,
        "citations": citations,
        "explanation": explanation,
        "answer": answer_text,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--broker", default="localhost")
    ap.add_argument("--broker-port", type=int, default=1883)
    ap.add_argument("--ask-topic", default="panki/ask")
    ap.add_argument("--answer-topic", default="panki/answer")
    ap.add_argument("--llm-url", default="http://localhost:11434/v1")
    ap.add_argument("--corpus", default=str(Path.home() / "qvac-exploration/toy-panki/fake-bpom.json"))
    args = ap.parse_args()

    chunks = json.loads(Path(args.corpus).read_text(encoding="utf-8"))
    print(f"[panki-mqtt] loaded {len(chunks)} BPOM chunks from {args.corpus}")

    # paho 2.x needs an explicit callback API version; 1.x doesn't have the enum.
    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
    except (AttributeError, TypeError):
        client = mqtt.Client()

    def on_connect(c, userdata, flags, rc, *extra):
        print(f"[panki-mqtt] connected to broker (rc={rc}); subscribing to {args.ask_topic}")
        c.subscribe(args.ask_topic)

    def on_message(c, userdata, msg):
        try:
            req = json.loads(msg.payload.decode())
        except Exception as e:
            print(f"[panki-mqtt] bad request payload: {e}")
            return
        cid = req.get("id", "")
        product = (req.get("message") or req.get("product") or "").strip()
        print(f"[panki-mqtt] ask id={cid[:8]} product={product!r}")
        if not product:
            return
        result = build_answer(product, chunks, args.llm_url)
        result["id"] = cid
        result["product"] = product
        c.publish(args.answer_topic, json.dumps(result))
        print(f"[panki-mqtt] answered id={cid[:8]} ({len(result['parameters'])} params)")

    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(args.broker, args.broker_port, keepalive=60)
    print(f"[panki-mqtt] bridge running. ask->{args.ask_topic}  answer->{args.answer_topic}")
    client.loop_forever()


if __name__ == "__main__":
    sys.exit(main())
