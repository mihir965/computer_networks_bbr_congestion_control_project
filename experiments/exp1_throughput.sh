#!/usr/bin/env bash
# Sweep CC x bandwidth x delay x buffer. 81 runs at 30s each, ~45 min total.
# Output: data/raw/exp1/<cc>_<bw>_<delay>_<buf>p.json
# Requires testbed up: sudo ./setup/topology.sh up
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

CCS=(bbr cubic reno)
BWS=(10mbit 50mbit 100mbit)
DELAYS=(5ms 20ms 80ms)
BUFS=(10 100 1000)
DURATION="${DURATION:-30}"

OUT="data/raw/exp1"
mkdir -p "$OUT"

if ! sudo ip netns list | grep -q '^ns1'; then
    echo "ERROR: ns1 not present. Run 'sudo ./setup/topology.sh up' first." >&2
    exit 1
fi

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

                ./setup/shape.sh "$bw" "$delay" "$buf" >/dev/null
                sleep 0.3

                if sudo ip netns exec ns2 iperf3 -c 10.0.0.1 -t "$DURATION" -O 1 -J -C "$cc" > "$out" 2>/dev/null; then
                    mbps=$(python3 -c "import json; d=json.load(open('$out')); print(f\"{d['end']['sum_received']['bits_per_second']/1e6:.1f}\")" 2>/dev/null || echo "?")
                    printf "%6s Mbps\n" "$mbps"
                else
                    printf "FAILED\n"
                fi

                sleep 1
            done
        done
    done
done

elapsed=$(( $(date +%s) - start ))
echo
echo "Done. $total runs in ${elapsed}s. Output in $OUT/"
