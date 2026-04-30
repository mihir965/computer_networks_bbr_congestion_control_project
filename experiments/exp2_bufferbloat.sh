#!/usr/bin/env bash
# 60s flow per CC at 100mbit, 20ms one-way (40ms RTT), 1000 pkt buffer.
# RTT comes from iperf3 per-interval TCP_INFO (-i 0.1).
# Output: data/raw/exp2/iperf_<cc>.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CCS=(bbr cubic reno)
DURATION="${DURATION:-60}"
INTERVAL="${INTERVAL:-0.1}"
BW=100mbit
DELAY=20ms
BUF=1000

OUT="data/raw/exp2"
mkdir -p "$OUT"

if ! sudo ip netns list | grep -q '^ns1'; then
    echo "ERROR: ns1 not present. Run 'sudo ./setup/topology.sh up' first." >&2
    exit 1
fi

./setup/shape.sh "$BW" "$DELAY" "$BUF" >/dev/null
echo "Shaped: $BW / $DELAY one-way (RTT~40ms) / $BUF pkt buffer"

sudo pkill -f "iperf3 -s" 2>/dev/null || true
sleep 0.3
sudo ip netns exec ns1 iperf3 -s -D
sleep 0.5
trap 'sudo pkill -f "iperf3 -s" 2>/dev/null || true' EXIT

for cc in "${CCS[@]}"; do
    echo
    echo "=== $cc ==="
    iperf_json="$OUT/iperf_${cc}.json"
    sudo ip netns exec ns2 iperf3 -c 10.0.0.1 -t "$DURATION" -i "$INTERVAL" -J -C "$cc" > "$iperf_json"

    python3 -c "
import json
d = json.load(open('$iperf_json'))
e = d['end']; s = e['streams'][0]['sender']
print(f'  thr={e[\"sum_received\"][\"bits_per_second\"]/1e6:.1f} Mbps  retrans={e[\"sum_sent\"][\"retransmits\"]}  '
      f'rtt min={s[\"min_rtt\"]/1000:.1f}ms mean={s[\"mean_rtt\"]/1000:.1f}ms max={s[\"max_rtt\"]/1000:.1f}ms  '
      f'inflation={s[\"mean_rtt\"]/s[\"min_rtt\"]:.2f}x')
"
    sleep 2
done

echo
echo "Done. Outputs in $OUT/"
