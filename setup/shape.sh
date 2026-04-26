#!/usr/bin/env bash
# shape.sh <bandwidth> <one-way-delay> <buffer-pkts>
# Apply a bottleneck on the ns1<->ns2 link symmetrically.
#
# Example: ./shape.sh 100mbit 20ms 1000
#   -> 100 Mbps cap each direction, 20 ms delay each direction,
#      so end-to-end RTT ~= 40 ms and one-way delay = 20 ms.
#
# WHY BOTH DIRECTIONS:
#   tc applies to egress only. If we shape just one veth, ACKs return
#   instantly on the unshaped path and TCP sees RTT = one_way_delay,
#   not 2*one_way_delay. That breaks the "one-way delay" semantics the
#   experiment plan assumes (5/20/80 ms one-way -> 10/40/160 ms RTT).
#
# WHY tbf-then-netem ORDERING:
#   tbf must be the root qdisc and netem must be its child. Reversed,
#   delay would be applied before rate-limiting and RTT measurements
#   would be wrong. (See CLAUDE.md note.)
set -euo pipefail

BW=${1:?bandwidth required (e.g. 100mbit)}
DELAY=${2:?one-way delay required (e.g. 20ms)}
BUF=${3:?buffer size in packets required (e.g. 1000)}

apply_shape() {
    local ns=$1 iface=$2

    # Wipe any existing qdisc — leftover qdiscs silently stack.
    sudo ip netns exec "$ns" tc qdisc del dev "$iface" root 2>/dev/null || true

    # tbf: rate-limit. burst = token bucket size; latency = max wait before drop.
    # Generous tbf latency so tbf itself doesn't become the bottleneck queue —
    # netem's `limit` owns queue depth.
    sudo ip netns exec "$ns" tc qdisc add dev "$iface" root handle 1: \
        tbf rate "$BW" burst 32kbit latency 400ms

    # netem: one-way delay + queue cap (in packets).
    sudo ip netns exec "$ns" tc qdisc add dev "$iface" parent 1:1 handle 10: \
        netem delay "$DELAY" limit "$BUF"
}

apply_shape ns1 veth-ns1
apply_shape ns2 veth-ns2

echo "Shaped both directions: rate=$BW, one-way-delay=$DELAY (RTT~=2x), buffer=${BUF} pkts"
echo "--- ns1/veth-ns1 ---"
sudo ip netns exec ns1 tc qdisc show dev veth-ns1
echo "--- ns2/veth-ns2 ---"
sudo ip netns exec ns2 tc qdisc show dev veth-ns2
