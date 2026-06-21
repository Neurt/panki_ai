# Draft GitHub issue — QVAC #1823 reproduction on Raspberry Pi 4B (linux-arm64)

> File this at https://github.com/tetherto/qvac/issues/new — pick the **Bug** template. Reference #1823 in the body. Attach the three repro files listed at the bottom.

---

## Title

`[Bug]: RPC initialization timed out on linux-arm64 (Raspberry Pi 4B) — llm-llamacpp worker silently dies even with device: cpu (likely overlaps #1823)`

## SDK Version

`@qvac/sdk` `0.12.2`, `@qvac/cli` matching

## Node.js

`v22.22.3`

## Platform

`linux-arm64`, Raspberry Pi 4B (4 GB), Ubuntu Server 24.04.4 LTS arm64, Mesa Vulkan `V3D 4.2.14` confirmed present and reported ✅ by `qvac doctor`.

## Severity

Critical (complete blocker — no model can preload, `/v1/chat/completions` 503s with no model loaded).

## Frequency

Always — every fresh server start. Reproduced after multiple clean reinstalls.

## Summary

`qvac serve openai` reports *"Failed to preload <model>: RPC initialization timed out after 30000ms — the worker process may have failed to start"* for any model entry in the config, regardless of whether `device` is `cpu` or `gpu`, regardless of `gpu_layers`. No model file is ever fetched (the worker dies before the model registry resolver runs). The SDK does not surface any further diagnostic. Behaviour is consistent with #1823 ("device: 'cpu' should not be affected by GPU dependencies") but on linux-arm64 rather than the original Windows reproduction — filing for visibility.

## Minimal reproduction

```bash
# Pi 4B 4GB, Ubuntu Server 24.04 LTS arm64, fresh install
sudo apt-get install -y libvulkan1 mesa-vulkan-drivers vulkan-tools nodejs npm
# Node.js >= 22.17 via NodeSource

mkdir qvac-repro && cd qvac-repro
npm init -y
npm install @qvac/sdk @qvac/cli --no-audit --no-fund

cat > qvac.config.json <<'EOF'
{
  "serve": {
    "models": {
      "test-llm": {
        "model": "QWEN3_600M_INST_Q4",
        "default": true,
        "preload": true,
        "config": {
          "ctx_size": 1024,
          "tools": true,
          "device": "cpu",
          "gpu_layers": 0
        }
      }
    }
  }
}
EOF

./node_modules/.bin/qvac doctor
# Expected: all ✅ including @qvac/sdk resolvable from project, Vulkan: V3D 4.2.14

./node_modules/.bin/qvac serve openai
```

## Observed

```
ffmpeg not on PATH — /v1/videos/{id}/content will default to video/avi. Install ffmpeg to serve video/mp4. See: qvac doctor
Preloading 1 model(s): test-llm
Loading model "test-llm" from registry://hf/unsloth/Qwen3-0.6B-GGUF/blob/<sha>/Qwen3-0.6B-Q4_0.gguf...
[sdk:client] Model type "llm" is an alias and will be deprecated. Use "llamacpp-completion" instead.
Failed to preload "test-llm": RPC initialization timed out after 30000ms — the worker process may have failed to start
QVAC API server listening on http://127.0.0.1:11434
```

`/v1/models` then returns `{"object":"list","data":[]}` and `/v1/chat/completions` returns 503 in ~16 ms.

## Expected

Worker boots, model preloads (or fails with an actionable error such as a Vulkan ICD probe failure rather than a generic timeout), `/v1/models` lists `test-llm`, and `/v1/chat/completions` returns a completion.

## Diagnostics already collected

- `qvac doctor` is fully ✅, including Vulkan: V3D 4.2.14 and `@qvac/sdk resolvable from project — v0.12.2`.
- Worker spawn is confirmed via `NODE_DEBUG=child_process`:
  ```
  CHILD_PROCESS spawn {
    file: '<install-dir>/node_modules/@qvac/sdk/node_modules/bare-runtime-linux-arm64/bin/bare',
    args: [..., '<install-dir>/node_modules/@qvac/sdk/dist/server/worker.js', '{"QVAC_IPC_SOCKET_PATH":"/tmp/qvac-worker-...sock","HOME_DIR":"/home/<user>"}'],
    stdio: [ 'inherit', 'inherit', 'inherit' ]
  }
  ```
- After spawn, no further worker output reaches stdout/stderr before the 30 s parent timeout. The worker exits silently.
- Tested with `DEBUG=*` and `QVAC_LOG_LEVEL=debug` — no additional worker-side messages produced.
- Tested with `device: cpu` and `gpu_layers: 0`. No effect.
- Tested with Vulkan ICD present (verified by `vulkaninfo --summary`) and after `apt-get install --reinstall libvulkan1 mesa-vulkan-drivers vulkan-tools`. No effect.
- Tested with `@qvac/sdk` and `@qvac/cli` installed both globally and locally. Local install resolves correctly per `qvac doctor`; failure mode identical.
- Same behaviour observed with multiple registry models (`QWEN3_600M_INST_Q4`, `LLAMA_3_2_1B_INST_Q4_0`).

## Suspected cause

Per #1823 the `@qvac/llm-llamacpp` native binding fails to load on certain GPU/driver combinations, dragging the worker down before any user-visible diagnostic. On linux-arm64 the same surfaces as a silent worker exit (rather than the "specified procedure could not be found" the Windows reporter saw), which is also consistent with the symptoms in #2399 where Vulkan-linked allocations crash without a chance for graceful CPU fallback.

## Asks

1. A documented way to **disable the Vulkan-linked path** of `@qvac/llm-llamacpp` at install or runtime (env var, npm flag, or build option). The current `device: cpu` config is not sufficient per #1823.
2. A flag or env var to **extend the worker RPC handshake timeout** beyond 30 s, so first-run model downloads on slow links don't compound with the diagnostic loss above.
3. An option to **pipe worker stderr to the parent** even on clean exit, so silent crashes are visible without `strace`.

## Attachments (collected on the affected host)

- `qvac-repro-doctor.txt` — `./node_modules/.bin/qvac doctor` output + `node --version` + `uname -a`
- `qvac-repro-config.json` — the `qvac.config.json` above
- `qvac-repro-debug.log` — `DEBUG=* QVAC_LOG_LEVEL=debug NODE_DEBUG=child_process ./node_modules/.bin/qvac serve openai 2>&1 | tee` for one full failure cycle

(Generate these on the Pi with the commands at the bottom of [`qvac-exploration/OLLAMA-FALLBACK.md`](qvac-exploration/OLLAMA-FALLBACK.md) or:

```bash
cd ~/qvac-exploration
./node_modules/.bin/qvac doctor > qvac-repro-doctor.txt
node --version >> qvac-repro-doctor.txt
uname -a >> qvac-repro-doctor.txt
cp qvac.config.json qvac-repro-config.json
DEBUG='*' QVAC_LOG_LEVEL=debug NODE_DEBUG=child_process \
  ./node_modules/.bin/qvac serve openai 2>&1 | tee qvac-repro-debug.log
```

then attach the three files to the GitHub issue.)
