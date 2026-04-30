#!/usr/bin/env bash
# Install deps, load tcp_bbr, verify env. Safe to re-run.
set -euo pipefail

echo "[1/4] Installing packages"
if command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm \
        iperf3 tcpdump iproute2 ethtool \
        python python-pandas python-matplotlib python-numpy
else
    echo "ERROR: pacman not found. This script targets CachyOS/Arch." >&2
    exit 1
fi

echo "[2/4] Loading tcp_bbr"
sudo modprobe tcp_bbr
echo tcp_bbr | sudo tee /etc/modules-load.d/bbr.conf >/dev/null

echo "[3/4] Verifying BBR available"
avail=$(sysctl -n net.ipv4.tcp_available_congestion_control)
echo "  available: $avail"
if ! echo "$avail" | grep -qw bbr; then
    echo "ERROR: bbr not in available_congestion_control after modprobe." >&2
    exit 1
fi

echo "[4/4] Verifying tools"
for t in iperf3 tc tcpdump ip ss; do
    if command -v "$t" >/dev/null 2>&1; then
        echo "  ok: $t -> $(command -v $t)"
    else
        echo "  MISSING: $t" >&2
        exit 1
    fi
done

echo
echo "Done. Kernel: $(uname -r)."
