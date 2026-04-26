#!/usr/bin/env bash
# exp1_throughput.sh — sweep CC × bandwidth × delay × buffer, record steady-state throughput.
#
# Output: data/raw/exp1/<cc>_<bw>_<delay>_<buf>p.json (one iperf3 JSON per run).
# Total: 3 CCs × 3 BW × 3 delays × 3 buffers = 81 runs * ~30s each ≈ 45 min.
#
# Requires: testbed already up (sudo ./setup/topology.sh up).
set -euo pipefail

# Locate project root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CCS=(bbr cubic reno)
BWS=(10mbit 50mbit 100mbit)
DELAYS=(5ms 20ms 80ms)
BUFS=(10 100 1000)
DURATION="${DURATION:-30}"   # seconds; override with DURATION=10 for quick sanity run

OUT="data/raw/exp1"
mkdir -p "$OUT"

# Verify testbed is up — fail fast with a useful message rather than producing garbage.
if ! sudo ip netns list | grep -q '^ns1'; then
    echo "ERROR: ns1 not present. Run 'sudo ./setup/topology.sh up' first." >&2
    exit 1
fi

# Start a single iperf3 server in ns1 (handles sequential clients on port 5201).
sudo pkill -f "iperf3 -s" 2>/dev/null || true
sleep 0.3
sudo ip netns exec ns1 iperf3 -s -D
sleep 0.5

cleanup() {
    sudo pkill -f "iperf3 -s" 2>/dev/null || true
}
trap cleanup EXIT

total=$(( ${#CCS[@]} * ${#BWS[@]} * ${#DELAYS[@]} * ${#BUFS[@]} ))
i=0
start=$(date +%s)

for cc in "${CCS[@]}"; do
    for bw in "${BWS[@]}"; do
        for delay in "${DELAYS[@]}"; do
            for buf in "${BUFS[@]}"; do
                i=$((i+1))
                name="${cc}_${bw}_${delay}_${buf}p"
                out="$OUT/${name}.json"

                printf "[%2d/%2d] %-30s " "$i" "$total" "$name"

                # Apply bottleneck for this run (silenced — already echoed by us).
                ./setup/shape.sh "$bw" "$delay" "$buf" >/dev/null
                sleep 0.3   # let qdisc settle

                # iperf3 -C sets per-flow congestion control on the sender (ns2).
                # -t = duration, -J = JSON output, -O 1 = omit first 1s (slow-start) from steady-state stats.
                if sudo ip netns exec ns2 iperf3 -c 10.0.0.1 -t "$DURATION" -O 1 -J -C "$cc" > "$out" 2>/dev/null; then
                    # Pull final receiver throughput for live progress display.
                    mbps=$(python3 -c "import json; d=json.load(open('$out')); print(f\"{d['end']['sum_received']['bits_per_second']/1e6:.1f}\")" 2>/dev/null || echo "?")
                    printf "%6s Mbps\n" "$mbps"
                else
                    printf "FAILED\n"
                fi

                sleep 1   # let queues drain between runs
            done
        done
    done
done

elapsed=$(( $(date +%s) - start ))
echo
echo "Sweep complete. $total runs in ${elapsed}s. Output in $OUT/"
