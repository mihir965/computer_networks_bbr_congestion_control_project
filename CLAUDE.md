# CS 552 — BBR Congestion Control Project
## Claude Code Context File

### Project Overview
This is a graduate-level computer networks project for CS 552 (Prof. Minsung Kim, Rutgers University, Spring 2026).
The goal is to empirically reproduce and analyze BBR (Bottleneck Bandwidth and Round-trip propagation time),
Google's congestion-based TCP congestion control algorithm, published in ACM Queue 2016 / ACM SIGCOMM CCR.

**Team members:** Mihir Kulkarni, Chaitanya Ranaware, Piyoosha Gadi

We are NOT implementing BBR from scratch. BBR already exists in the Linux kernel (since v4.9).
The project is about setting up controlled experiments, running them, and analyzing/visualizing the results.

---

### Core Paper
**Title:** BBR: Congestion-Based Congestion Control
**Authors:** Cardwell, Cheng, Gunn, Hassas Yeganeh, Jacobson (Google)
**Published:** ACM Queue 14(5), 2016. Republished in ACM SIGCOMM CCR 47(2), 92–101.
**Key idea:** Instead of reacting to packet loss (like CUBIC/RENO), BBR models the network path
by estimating bottleneck bandwidth (BtlBw) and minimum RTT (RTprop) to optimally set
pacing rate and congestion window.

---

### Experiment Objectives
1. **Throughput reproduction** — Reproduce paper's throughput comparison: BBR vs CUBIC vs RENO
   under varying bottleneck bandwidths, buffer sizes, AND propagation delays using tc netem + iperf3.
   Sweep at minimum:
   - Bandwidths: 10, 50, 100 Mbps
   - One-way delays: 5, 20, 80 ms (representing LAN, regional WAN, intercontinental)
   - Buffer sizes: 10, 100, 1000 packets (shallow, moderate, deep buffers)
   Validate results against published figures — BBR's advantage is most visible on high-latency, lossy links.

2. **Buffer bloat analysis** — Show that CUBIC inflates RTT due to queue buildup,
   while BBR maintains near-minimum latency at equivalent throughput. Run under a fixed
   bottleneck (e.g., 100 Mbps, 20 ms base RTT) with deep buffer (BDP-sized or larger) to
   make queue buildup visible. Capture RTT time-series alongside throughput time-series.

3. **Fairness analysis** — Run simultaneous BBR and CUBIC flows on a shared bottleneck.
   Analyze bandwidth distribution. This extends the paper — BBRv2 was partly motivated
   by unfairness issues found in original BBR vs CUBIC competition. Also test BBR vs BBR
   (intra-protocol fairness) as a baseline.

---

### Toolchain
- **OS:** Linux (Ubuntu 22.04 recommended)
- **Link emulation:** `tc netem` (part of iproute2) — controls bandwidth, delay, loss, queue size
- **Traffic generation:** `iperf3` — generates TCP flows, reports throughput
- **Packet capture:** `tcpdump`, `ss`, `Wireshark`
- **Switching CC algorithm:** `sysctl net.ipv4.tcp_congestion_control=bbr` (or cubic/reno)
- **Plotting:** Python with matplotlib, pandas
- **Environment:** Linux VMs (local or cloud — AWS/GCP free tier works)

---

### Repo Structure (to build toward)
```
bbr-project/
├── CLAUDE.md               # this file
├── setup/
│   └── setup.sh            # install dependencies, verify BBR available in kernel
├── experiments/
│   ├── exp1_throughput.sh  # Experiment 1: throughput vs bandwidth/buffer/delay sweep
│   ├── exp2_bufferbloat.sh # Experiment 2: RTT inflation under load (time-series)
│   └── exp3_fairness.sh    # Experiment 3: BBR vs CUBIC + BBR vs BBR competing flows
├── data/
│   └── raw/                # iperf3 JSON outputs, ss logs
│       ├── exp1/           # named by cc_bw_delay_buf (e.g., bbr_100mbit_20ms_1000p.json)
│       ├── exp2/
│       └── exp3/
├── analysis/
│   ├── parse.py            # parse iperf3 JSON into pandas DataFrames
│   ├── plot_throughput.py  # reproduce paper Figure comparisons (heatmap or line per delay)
│   ├── plot_rtt.py         # RTT over time plots
│   └── plot_fairness.py    # Jain's fairness index, bandwidth share over time
├── figures/                # output plots (one subdir per experiment)
└── report/                 # final written report
```

---

### Key Commands Reference

```bash
# Check BBR is available
sysctl net.ipv4.tcp_available_congestion_control

# Set congestion control
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
sudo sysctl -w net.ipv4.tcp_congestion_control=cubic
sudo sysctl -w net.ipv4.tcp_congestion_control=reno

# Emulate a bottleneck: tbf controls rate, netem controls delay + buffer
# NOTE: tbf must be added first (root), netem chained as a child (handle 10:)
# Example: 100Mbps, 20ms one-way delay (40ms RTT), 1000 packet queue
sudo tc qdisc add dev eth0 root handle 1: tbf rate 100mbit burst 32kbit latency 400ms
sudo tc qdisc add dev eth0 parent 1:1 handle 10: netem delay 20ms limit 1000

# Tear down all qdiscs on an interface
sudo tc qdisc del dev eth0 root

# Vary delay for Experiment 1 sweep (swap netem delay value per run)
# 5ms  → LAN scenario
# 20ms → regional WAN
# 80ms → intercontinental / satellite-adjacent

# Run iperf3 server (background, use -p for additional ports)
iperf3 -s -p 5201 &
iperf3 -s -p 5202 &

# Run iperf3 client (30s test, JSON output, named by parameters)
iperf3 -c <server_ip> -t 30 -J > data/raw/exp1/bbr_100mbit_20ms_1000p.json

# Monitor RTT in real time
ss -tin dst <server_ip>

# Collect ss RTT samples every 100ms during a run (pipe to log for Exp 2)
while true; do ss -tin dst <server_ip> | grep -oP 'rtt:\K[0-9.]+'; sleep 0.1; done > data/raw/exp2/rtt_bbr.log

# Multiple competing flows (fairness experiment — Exp 3)
iperf3 -c <server_ip> -p 5201 -t 30 -J > data/raw/exp3/bbr_flow.json &
iperf3 -c <server_ip> -p 5202 -t 30 -J > data/raw/exp3/cubic_flow.json &
wait
```

---

### Metrics to Collect Per Experiment

**All experiments:**
- Throughput (Mbps) — time-series and steady-state average
- RTT (ms) — minimum, average, 99th percentile
- Retransmission count and retransmission rate

**Experiment 1 (throughput sweep):**
- Steady-state throughput per (CC, bandwidth, delay, buffer) combination
- Throughput utilization ratio: achieved / configured bottleneck bandwidth

**Experiment 2 (buffer bloat):**
- RTT time-series at 100ms resolution (via `ss` loop)
- RTT inflation ratio: avg RTT / min RTT — quantifies queue buildup
- Queue occupancy (infer from RTT inflation × BDP)

**Experiment 3 (fairness):**
- Per-flow bandwidth share over time
- Jain's Fairness Index: `J = (Σxᵢ)² / (n · Σxᵢ²)`  — 1.0 = perfectly fair
- Steady-state bandwidth ratio (BBR share / CUBIC share)

---

### Validation Target
Results should qualitatively match figures in the BBR paper:
- BBR should achieve throughput close to bottleneck bandwidth across all delay/buffer conditions
- BBR's advantage over CUBIC/RENO should grow with higher propagation delay (high-latency links)
- CUBIC/RENO should show significantly higher RTT under load (buffer bloat) — RTT inflation ratio >> 1
- BBR should maintain near-minimum RTT even at high throughput (RTT inflation ratio ≈ 1)
- Fairness experiment: expect BBR to grab disproportionate bandwidth vs CUBIC in some conditions;
  BBR vs BBR should converge to roughly equal shares (intra-protocol fairness baseline)

---

### Presentation (Due Next Week)
Separate from experiments. Covers the paper itself and connects to CS 552 course material:

**Paper content:**
- Why loss-based CC fails — buffer bloat: large buffers cause RTT inflation without signaling congestion
- BBR's network model: BtlBw + RTprop = BDP — the two physical quantities BBR estimates
- Four phases: STARTUP (exponential ramp-up to find BtlBw), DRAIN (clear startup queue),
  PROBE_BW (steady-state pacing with periodic bandwidth probing), PROBE_RTT (RTprop refresh)
- Real-world deployment: Linux kernel v4.9+, Google's WAN, YouTube, QUIC/HTTP3
- Key results from the paper: throughput, latency, high-latency link performance

**CS 552 theory connections (explicit for the presentation):**
- TCP/IP model: BBR operates at the transport layer but models the network layer (bottleneck link)
- Transport layer design: how pacing rate differs from CWND-based control; why both are set in BBR
- Congestion control theory: the Bandwidth-Delay Product as the optimal operating point;
  contrast with AIMD (CUBIC/RENO) and why AIMD over-fills buffers
- Relate BBR's BtlBw estimation to the concept of available bandwidth measurement from the course

---

### Notes & Gotchas
- BBR requires Linux kernel >= 4.9. Verify with `uname -r`
- **tc ordering matters:** tbf (rate limiter) must be root; netem (delay/loss) chained as child.
  Reversing this causes the delay to be applied before rate limiting, producing wrong RTT measurements.
- Always `tc qdisc del dev eth0 root` between runs — leftover qdiscs silently stack
- iperf3 JSON output is the cleanest format for programmatic parsing
- Name output files with all parameters in the filename (e.g., `bbr_100mbit_20ms_1000p.json`)
  to make the analysis scripts self-documenting
- For fairness experiments, use two separate iperf3 server ports (5201, 5202)
- Start both iperf3 flows within ~1 second of each other to ensure they compete from the start
- Cloud VMs may have virtualized NICs that interfere with tc netem — test locally first if possible
- BBRv2 exists but is not mainline yet; stick to BBRv1 (default in kernel) for reproducibility
- `ss -tin` reports RTT from the kernel's TCP state — more accurate than iperf3's own RTT field
- Run each condition at least 3 times and average to reduce noise from background system activity
