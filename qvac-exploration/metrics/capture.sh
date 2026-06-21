#!/usr/bin/env bash
# capture.sh — Sample RAM, CPU temperature, and load at 1 Hz for N seconds.
# Writes a CSV to metrics-<timestamp>.csv. Run alongside a benchmark.
#
# Usage: ./capture.sh 120    # 120 seconds of samples

set -euo pipefail

DURATION="${1:-120}"
OUT="metrics-$(date +%Y%m%d-%H%M%S).csv"

THERMAL_FILE="/sys/class/thermal/thermal_zone0/temp"

echo "ts_unix,ram_used_mb,ram_free_mb,ram_avail_mb,cpu_temp_c,load1" > "$OUT"
echo "[metrics] writing $OUT for ${DURATION}s..."

end=$(( $(date +%s) + DURATION ))
while [[ $(date +%s) -lt $end ]]; do
  ts=$(date +%s)
  read used free avail < <(free -m | awk '/^Mem:/ {print $3, $4, $7}')
  if [[ -r "$THERMAL_FILE" ]]; then
    temp_milli=$(cat "$THERMAL_FILE")
    temp=$(awk "BEGIN{printf \"%.1f\", $temp_milli/1000}")
  else
    temp="NA"
  fi
  load1=$(awk '{print $1}' /proc/loadavg)
  echo "$ts,$used,$free,$avail,$temp,$load1" >> "$OUT"
  sleep 1
done

echo "[metrics] done. Summary:"
python3 - "$OUT" <<'PY'
import csv, sys, statistics
path = sys.argv[1]
rows = list(csv.DictReader(open(path)))
def col(name, cast=float):
    return [cast(r[name]) for r in rows if r[name] not in ("", "NA")]
ram = col("ram_used_mb")
temp = col("cpu_temp_c")
load = col("load1")
print(f"  samples: {len(rows)}")
print(f"  RAM used MB:   min={min(ram):.0f} median={statistics.median(ram):.0f} max={max(ram):.0f}")
print(f"  CPU temp C:    min={min(temp):.1f} median={statistics.median(temp):.1f} max={max(temp):.1f}")
print(f"  load avg (1m): min={min(load):.2f} median={statistics.median(load):.2f} max={max(load):.2f}")
PY
