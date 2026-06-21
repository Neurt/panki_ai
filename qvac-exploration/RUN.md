# Panki Edge — Run & Operate on the Pi 4B

QVAC Fabric LLM (`llama-server`) + the grounded `panki_demo.py` pipeline.

- Binaries: `~/qvac-fabric-llm.cpp/build/bin/` (`llama-server`, `llama-cli`)
- Model:    `~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf` (swap freely)
- Grounding lives in `~/qvac-exploration/toy-panki/panki_demo.py` — the **server alone does NOT ground**; only the script does (retrieval + deterministic params + grounded explanation).

---

## A. One-time setup — make the LLM start automatically

Paste these on the Pi once. After this the server is always running (boot + crash-restart), and you query with a single `panki` command.

### 1. Auto-start the LLM server (systemd)
```bash
pkill -9 -f llama-server 2>/dev/null; sleep 2   # stop any manual server first

sudo tee /etc/systemd/system/qvac-llm.service > /dev/null <<'EOF'
[Unit]
Description=QVAC Fabric LLM server (Panki Edge)
After=network-online.target
Wants=network-online.target

[Service]
User=panki
ExecStart=/home/panki/qvac-fabric-llm.cpp/build/bin/llama-server -m /home/panki/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 2048 --host 0.0.0.0 --port 11434
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now qvac-llm
```

### 2. The `panki` command (one word to query, from anywhere)
```bash
sudo tee /usr/local/bin/panki > /dev/null <<'EOF'
#!/usr/bin/env bash
DEMO=/home/panki/qvac-exploration/toy-panki/panki_demo.py
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  exec python3 "$DEMO" --product "$*"
fi
exec python3 "$DEMO" "$@"
EOF
sudo chmod +x /usr/local/bin/panki
```

### 3. (Optional) Show LLM status on login
```bash
cat >> ~/.bashrc <<'EOF'

# Panki: show LLM status on interactive login
if [[ $- == *i* ]]; then
  if curl -s --max-time 2 http://localhost:11434/v1/models | grep -q qwen; then
    echo "[Panki] LLM is READY  ->  panki \"your product description\""
  else
    echo "[Panki] LLM still loading or down  ->  systemctl status qvac-llm"
  fi
fi
EOF
```

---

## B. Daily use

```bash
ssh panki@<pi-ip>
panki "Bottled green tea drink with added vitamin C"
panki "Vitamin C 500 mg chewable tablet supplement"
panki                      # runs the default biscuit example
```
Each call prints: retrieved regulations, the deterministic required-test list, and the grounded customer explanation.

> First query after a reboot may return briefly while the model loads (~1–2 min for the 1.5B). The login banner (A.3) tells you when it's READY.

---

## C. Managing the server

```bash
systemctl status qvac-llm           # is it running?
sudo systemctl restart qvac-llm     # restart (e.g. after changing the model)
sudo systemctl stop qvac-llm        # stop
journalctl -u qvac-llm -f           # live logs
curl -s http://localhost:11434/v1/models | head -c 120; echo   # quick health check
```

---

## D. Switching models (speed vs quality)

The facts are deterministic, so model size only affects the *explanation*:

| Model | Speed on Pi 4B | Explanation quality |
|---|---|---|
| `qwen3-0.6b-q4_0.gguf` | fast (~7 tok/s) | weaker, may be terse |
| `qwen2.5-1.5b-instruct-q4_k_m.gguf` | slower (~4 tok/s, ~2 min/query) | full, professional |

To switch: edit the `ExecStart` model path in the service, then:
```bash
sudo nano /etc/systemd/system/qvac-llm.service   # change the -m path
sudo systemctl daemon-reload && sudo systemctl restart qvac-llm
```

---

## E. Raw model chat (NO grounding — for poking the model only)

```bash
~/qvac-fabric-llm.cpp/build/bin/llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
```
This is the bare model and **will hallucinate** on BPOM questions. For real answers always use `panki`.
