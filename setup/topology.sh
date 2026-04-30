#!/usr/bin/env bash
# topology.sh up|down
#
# ns1 (server) 10.0.0.1/24  <-- veth pair --> ns2 (client) 10.0.0.2/24
# veth-ns1                                    veth-ns2
#
# tc qdiscs are applied later by shape.sh on both veths.
set -euo pipefail

NS1=ns1
NS2=ns2
IF1=veth-ns1
IF2=veth-ns2
IP1=10.0.0.1/24
IP2=10.0.0.2/24

down() {
    sudo ip netns del $NS1 2>/dev/null || true
    sudo ip netns del $NS2 2>/dev/null || true
    echo "Topology down."
}

up() {
    sudo ip netns add $NS1
    sudo ip netns add $NS2

    sudo ip link add $IF1 type veth peer name $IF2
    sudo ip link set $IF1 netns $NS1
    sudo ip link set $IF2 netns $NS2

    sudo ip netns exec $NS1 ip addr add $IP1 dev $IF1
    sudo ip netns exec $NS2 ip addr add $IP2 dev $IF2
    sudo ip netns exec $NS1 ip link set $IF1 up
    sudo ip netns exec $NS2 ip link set $IF2 up
    sudo ip netns exec $NS1 ip link set lo up
    sudo ip netns exec $NS2 ip link set lo up

    # Disable offload so netem's packet-count limit is accurate.
    sudo ip netns exec $NS1 ethtool -K $IF1 tso off gso off gro off >/dev/null 2>&1 || true
    sudo ip netns exec $NS2 ethtool -K $IF2 tso off gso off gro off >/dev/null 2>&1 || true

    echo "Topology up."
    echo "  $NS1: $IP1 on $IF1"
    echo "  $NS2: $IP2 on $IF2"
    echo "Test: sudo ip netns exec $NS2 ping -c2 10.0.0.1"
}

case "${1:-}" in
    up)   down; up ;;
    down) down ;;
    *)    echo "usage: $0 up|down" >&2; exit 1 ;;
esac
