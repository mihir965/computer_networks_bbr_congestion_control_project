#!/usr/bin/env bash
# exp3_fairness.sh — two competing iperf3 flows on a shared bottleneck.
#
# For each pair (cc_a, cc_b): launch flow A on port 5201 and flow B on
# port 5202 in parallel. Use iperf3 -C to set the per-flow CC explicitly
# so the two flows can use different algorithms from the same namespace.
#
# Output: data/raw/exp3/<pair>_A.json and <pair>_B.json
# Total time: ~3 min 20 s (3 conditions * ~65 s each).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

DURATION="${DURATION:-60}"
INTERVAL="${INTERVAL:-0.5}"
BW=100mbit
DELAY=20ms
BUF="${BUF:-1000}"   # ~3 * BDP — deep buffer, where BBR-vs-CUBIC unfairness is most documented
                     # (set BUF=100 to repeat the shallow-buffer condition)

# Pairs to test.
declare -a PAIRS=(
    "bbr cubic"
    "bbr bbr"
    "cubic cubic"
)

OUT="data/raw/exp3"
mkdir -p "$OUT"

if ! sudo ip netns list | grep -q '^ns1'; then
    echo "ERROR: ns1 not present. Run 'sudo ./setup/topology.sh up' first." >&2
    exit 1
fi

./setup/shape.sh "$BW" "$DELAY" "$BUF" >/dev/null
echo "Shaped: $BW / $DELAY one-way (RTT~40ms) / $BUF pkt buffer"

# Start two iperf3 servers (one per port). Single -s only handles one client at a time.
sudo pkill -f "iperf3 -s" 2>/dev/null || true
sleep 0.3
sudo ip netns exec ns1 iperf3 -s -p 5201 -D
sudo ip netns exec ns1 iperf3 -s -p 5202 -D
sleep 0.5
trap 'sudo pkill -f "iperf3 -s" 2>/dev/null || true' EXIT

for pair in "${PAIRS[@]}"; do
    read -r cc_a cc_b <<< "$pair"
    name="${cc_a}_vs_${cc_b}"
    out_a="$OUT/${name}_A.json"
    out_b="$OUT/${name}_B.json"
    echo
    echo "=== $name ==="

    # Launch both flows in parallel. Background and wait — they should start
    # within tens of ms of each other, well below the 60 s duration.
    sudo ip netns exec ns2 iperf3 -c 10.0.0.1 -p 5201 -t "$DURATION" -i "$INTERVAL" -J -C "$cc_a" > "$out_a" &
    pid_a=$!
    sudo ip netns exec ns2 iperf3 -c 10.0.0.1 -p 5202 -t "$DURATION" -i "$INTERVAL" -J -C "$cc_b" > "$out_b" &
    pid_b=$!
    wait "$pid_a" "$pid_b"

    # Headline: per-flow throughput, total, share, Jain's index.
    python3 -c "
import json
a = json.load(open('$out_a'))['end']['sum_received']['bits_per_second']/1e6
b = json.load(open('$out_b'))['end']['sum_received']['bits_per_second']/1e6
total = a + b
jain = (a + b)**2 / (2 * (a*a + b*b)) if (a*a + b*b) > 0 else float('nan')
print(f'  $cc_a (A) = {a:6.1f} Mbps   $cc_b (B) = {b:6.1f} Mbps   total = {total:6.1f} Mbps   share_A = {a/total:.2f}   Jain J = {jain:.3f}')
"
    sleep 2
done

echo
echo "Done. Outputs in $OUT/"
