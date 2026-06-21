# Panki Edge — Project Summary & Demo Guide

**An offline-first BPOM compliance assistant running local AI on a $75 Raspberry Pi 4B, powered by QVAC.**

> One artifact, two competitions:
> - **TÜV Nord Indonesia — AI for Food & Drugs (Case 4):** intelligent BPOM test-parameter recommendation from a plain product description.
> - **QVAC Edge-AI track (≤4 GB SBC):** "maximum impact with minimum resources" — meaningful AI on extremely constrained hardware.

---

## 1. Elevator pitch

PT TÜV Nord Indonesia's customer-service staff manually cross-reference BPOM regulations to tell clients which mandatory laboratory tests a food/drug product needs. It's slow, error-prone, and depends on scarce experts.

**Panki Edge** turns a plain product description into a **correct, citation-backed list of required BPOM test parameters plus a customer-friendly explanation** — running entirely **locally on a Raspberry Pi 4B** via QVAC's inference engine, with **no cloud dependency**. A phone app talks to the Pi over **MQTT** (the IoT layer), giving a chatbot interface with history.

The core design principle that makes it trustworthy on a tiny model: **the facts are deterministic (assembled from the regulation data), and the small LLM only writes the explanation.** It can't drop or invent a required test.

---

## 2. The headline technical achievement (QVAC on a Cortex-A72)

This is the strongest differentiator for the edge-AI track:

- QVAC's prebuilt npm inference addon (`@qvac/llm-llamacpp` 0.12.2) is compiled for **ARMv8.2-A** (Pi 5 / Graviton / Apple-class CPUs). The **Pi 4B's Cortex-A72 is ARMv8.0-A** and lacks those instructions → the worker crashed with `Illegal instruction (core dumped)` (SIGILL).
- **We didn't give up on the Pi 4B or buy a Pi 5.** We built QVAC's open-source engine, **[`qvac-fabric-llm.cpp`](https://github.com/tetherto/qvac-fabric-llm.cpp)** (Tether's MIT-licensed llama.cpp fork), **from source on the Pi itself** — so the compiler targeted the actual A72 and produced A72-safe code.
- Result: **QVAC Fabric runs natively on the Pi 4B**, serving an OpenAI-compatible API. *"It actually runs on that."*

> Takeaway for judges: we made QVAC's edge engine run on a CPU below its prebuilt baseline by compiling on-device — proving local AI really is accessible on a $75 board.

---

## 3. Verified stack & versions

| Component | Version / detail |
|---|---|
| **Device** | Raspberry Pi 4B, 4 GB RAM |
| **CPU** | Cortex-A72 (CPU part `0xd08`), **ARMv8.0-A** (features: `fp asimd evtstrm crc32 cpuid`; no dotprod/FP16) |
| **OS** | Ubuntu Server 24.04 LTS (arm64) |
| **Inference engine** | **QVAC Fabric** — `qvac-fabric-llm.cpp`, build `b1-6f541c5`, MIT, built with GNU 13.3.0 for aarch64 |
| **bare runtime** | v1.28.6 (runs fine on A72) |
| **QVAC SDK (npm)** | `@qvac/sdk` 0.12.2 — *prebuilt LLM addon is ARMv8.2, incompatible with A72; we use the source-built Fabric engine instead* |
| **Node.js** | v22.22.3 (QVAC requires ≥ 22.17) |
| **Vulkan** | V3D 4.2.14 (Mesa `v3dv`) |
| **LLM (fast)** | Qwen3-0.6B-Q4_0 (unsloth GGUF) — ~7.5 tok/s, terse |
| **LLM (quality)** | **Qwen2.5-1.5B-Instruct-Q4_K_M** (Qwen GGUF) — ~4 tok/s, ~2 min/query, full professional explanation |
| **Server** | `llama-server` — OpenAI-compatible API on `:11434` |
| **Messaging** | MQTT — **Mosquitto** on the Pi (`:1883`, LAN / fully offline) **or** **HiveMQ Cloud** (`:8883`, TLS + auth) for cross-network access; `python3-paho-mqtt` client (bridge takes `--broker/--broker-port/--username/--password/--tls`) |
| **App** | Flutter (Android), `mqtt_client` with **TLS + credentials**; Connect tab (host / port / user / pass / TLS toggle, persisted) + Chatbot with persistent history |

**Reference (QVAC docs, verified):** Linux support = Ubuntu 22+, arm64/x64, Vulkan runtime; OpenAI-compatible CLI server on `localhost:11434/v1/`; delegated-inference API uses `providerPublicKey`/`fallbackToLocal` (no `topic`/discovery phase). Sources: https://docs.qvac.tether.io/

---

## 4. Architecture

```
 ┌─────────────┐   MQTT panki/ask     ┌──────────────────────── Raspberry Pi 4B ─────────────────────────┐
 │  Flutter    │ ───(correlation id)─▶ │  Mosquitto broker (:1883)                                        │
 │  Android    │                       │        │                                                         │
 │  chatbot    │ ◀──MQTT panki/answer──│        ▼                                                         │
 │ + history   │                       │  panki_mqtt_service.py  (threaded bridge)                        │
 └─────────────┘                       │        │                                                         │
                                       │        ├─▶ lexical retrieval over BPOM corpus (ground truth)     │
                                       │        ├─▶ DETERMINISTIC required-test list (complete, cited)    │
                                       │        └─▶ llama-server :11434  → grounded EXPLANATION            │
                                       │                 (QVAC Fabric engine, Qwen2.5-1.5B)               │
                                       └──────────────────────────────────────────────────────────────────┘
```

**Transport options (inference stays 100% local either way):** the phone↔Pi link is pluggable. On the **same Wi-Fi** the app talks to the Pi's **Mosquitto** broker on `:1883` — zero cloud, true offline-first (the headline demo). For **cross-network / cellular** access without port-forwarding or tunnels, both the Pi bridge and the app instead dial *out* to a **HiveMQ Cloud** broker on `:8883` (TLS + username/password). Only the *message transport* relays through the cloud broker — the model, the regulation data, and all inference never leave the Pi.

**Why hybrid (the key idea):** A 1B-scale model alone hallucinates (it invented *"BPOM = Beef Product Operation"* and *"breadth of biscuits ≥ 10 mm"*). So the **required-test list is assembled deterministically from the regulation data** — always complete, correct, and cited — and the **LLM only writes the natural-language explanation**. This maps directly onto Case 4's two asks: *"rule-based regulatory mapping"* + *"assist staff in explaining technical reasons to customers."*

---

## 5. How a query flows

1. Phone publishes `{"id": <uuid>, "message": "<product>"}` to `panki/ask`.
2. Bridge retrieves the matching BPOM regulation chunks (by category/keywords).
3. Bridge builds the **authoritative parameter list** straight from the chunks' data (e.g. biscuits → ALT, kapang dan khamir, Salmonella, Pb, Cd, As, Hg — each cited).
4. Bridge asks `llama-server` (QVAC Fabric) to write a **grounded explanation** constrained to those chunks.
5. Bridge publishes the structured answer to `panki/answer` with the same `id`; the app matches it to the question and renders it in the chat.

---


---

## 6. Setup (reproduction outline)

Detailed steps live in `qvac-exploration/RUN.md` and `panki-app/README.md`. Condensed:

**Pi — OS & toolchain**
- Flash Ubuntu Server 24.04 LTS arm64.
- Node 22 + Vulkan (`mesa-vulkan-drivers vulkan-tools`).
- Build tools — note: a broken `bzip2`/`build-essential` chain was sidestepped with `sudo apt install -y g++ make libc6-dev libcurl4-openssl-dev` + `sudo snap install cmake --classic`.

**Pi — QVAC Fabric engine (the unlock)**
```bash
git clone --depth 1 https://github.com/tetherto/qvac-fabric-llm.cpp.git
cd qvac-fabric-llm.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON   # GGML_NATIVE targets THIS A72
cmake --build build --config Release -j2
```

**Pi — models**
```bash
mkdir -p ~/models && cd ~/models
wget -O qwen2.5-1.5b-instruct-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

**Pi — services**
- LLM: `llama-server -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 2048 --host 0.0.0.0 --port 11434` (systemd unit `qvac-llm` in RUN.md).
- Broker + bridge: `sudo apt install -y mosquitto mosquitto-clients python3-paho-mqtt`; open the LAN listener; run `panki_mqtt_service.py`.

**App**
```bash
cd panki-app && flutter pub get && flutter build apk --release
```
Install the APK. **Same-network (offline):** Connect to the Pi's LAN IP (`hostname -I`) on port 1883. **Cross-network:** create a free HiveMQ Cloud cluster, run the bridge with `--broker <cluster>.hivemq.cloud --broker-port 8883 --username … --password … --tls`, and in the app enter the same cluster host on port 8883 with the credentials (TLS auto-enables).

---


> *Panki Edge: an offline-first BPOM compliance assistant that runs QVAC's AI engine locally on a $75 Raspberry Pi 4B — giving instant, citation-backed test-parameter recommendations by combining a deterministic regulation lookup with a small local LLM, accessed from a phone over MQTT.*
