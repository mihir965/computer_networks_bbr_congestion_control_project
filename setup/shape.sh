#!/usr/bin/env bash
# shape.sh <bandwidth> <one-way-delay> <buffer-pkts>
# Apply tbf+netem on both veths so RTT = 2 * one-way-delay.
# Example: ./shape.sh 100mbit 20ms 1000  -> 100Mbps, 40ms RTT, 1000 pkt buffer.
#
# tbf must be root, netem chained as child. Reversed, delay is applied
# before rate-limiting and RTT is wrong.
set -euo pipefail

BW=${1:?bandwidth required (e.g. 100mbit)}
DELAY=${2:?one-way delay required (e.g. 20ms)}
BUF=${3:?buffer size in packets required (e.g. 1000)}

apply_shape() {
    local ns=$1 iface=$2

    sudo ip netns exec "$ns" tc qdisc del dev "$iface" root 2>/dev/null || true

    sudo ip netns exec "$ns" tc qdisc add dev "$iface" root handle 1: \
        tbf rate "$BW" burst 32kbit latency 400ms

    sudo ip netns exec "$ns" tc qdisc add dev "$iface" parent 1:1 handle 10: \
        netem delay "$DELAY" limit "$BUF"
}

apply_shape ns1 veth-ns1
apply_shape ns2 veth-ns2

echo "Shaped: rate=$BW one-way=$DELAY (RTT~=2x) buffer=${BUF}pkt"
echo "--- ns1/veth-ns1 ---"
sudo ip netns exec ns1 tc qdisc show dev veth-ns1
echo "--- ns2/veth-ns2 ---"
sudo ip netns exec ns2 tc qdisc show dev veth-ns2
