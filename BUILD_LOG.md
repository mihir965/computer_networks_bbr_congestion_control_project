# Build log

Notes on what was built, in order. Captures the testbed, the three
experiments, and the bugs hit along the way.

## Phase 0: scaffold and testbed

Single-host setup. Two Linux network namespaces (`ns1`, `ns2`) connected
by a veth pair. iperf3 server in `ns1`, client in `ns2`. Bottleneck
shaped with `tc tbf` + `netem`.

```
ns1 (server)                       ns2 (client)
10.0.0.1/24  <---- veth pair ----> 10.0.0.2/24
veth-ns1                           veth-ns2
```

Why netns instead of two VMs: same kernel as the host, so the BBR
implementation under test is exactly the kernel module. No virtualized
NIC interference with `tc netem`. Bring-up and tear-down is instant.

Files:

| Path | What it does |
|---|---|
| `setup/setup.sh` | Installs iperf3, tcpdump, iproute2, ethtool, python deps via pacman. `modprobe tcp_bbr`, persists in `/etc/modules-load.d/bbr.conf`. Verifies BBR is in `tcp_available_congestion_control`. |
| `setup/topology.sh` | `up` builds the two-netns + veth testbed. `down` deletes the netns (auto-removes veth). Disables TSO/GSO/GRO so `netem`'s packet-count `limit` reflects real packets. |
| `setup/shape.sh` | `shape.sh <bw> <delay> <buf>` applies `tbf` (root) + `netem` (child) on both `veth-ns1` and `veth-ns2`. Tears down any existing qdisc first. Symmetric so RTT = 2x one-way delay. |

`tc` shapes egress only. The first version of `shape.sh` only applied
qdiscs to `ns2`'s veth, so ACKs returned on an unshaped path and TCP
saw RTT = one-way delay (20 ms) instead of 40 ms. Fixed by shaping both
veths.

`tbf` must be the root qdisc and `netem` chained as child. Reversed,
delay is applied before rate-limiting and RTT measurements are wrong.

Bring-up:

```bash
./setup/setup.sh                            # one-time
sudo ./setup/topology.sh up                 # per session
sudo ./setup/shape.sh 100mbit 20ms 1000     # apply bottleneck
```

Sanity check (2026-04-24, `100mbit / 20ms / 1000pkt`):

| Metric | Expected | Observed |
|---|---|---|
| ping RTT | ~40 ms | 40.067 / 40.082 / 40.105 ms (min/avg/max) |
| iperf3 receiver | ~95 Mbps | 93.6 Mbps |
| iperf3 sender | ~95 Mbps | 96.6 Mbps |
| Retransmits (CUBIC, deep buffer) | non-zero | 65 |

## Phase 1: throughput sweep (Exp 1)

Goal: for every (CC, bw, delay, buffer) combination, measure
steady-state throughput. The paper claims BBR sustains near-bottleneck
throughput where loss-based CC degrades.

| Dimension | Values |
|---|---|
| CC | bbr, cubic, reno |
| Bandwidth | 10mbit, 50mbit, 100mbit |
| One-way delay | 5ms, 20ms, 80ms (RTT = 2x) |
| Buffer | 10, 100, 1000 packets |
| Total | 81 runs |

30 s per run, ~45 min total wall time.

Files:

| Path | What it does |
|---|---|
| `experiments/exp1_throughput.sh` | Starts iperf3 server in `ns1`, loops over the grid, applies shape, runs a 30 s test with `iperf3 -C <cc>`, saves JSON. |
| `analysis/parse.py` | Walks JSONs, extracts (cc, bw, delay, buf, throughput, retransmits, mean RTT) into `analysis/exp1_results.csv`. |
| `analysis/plot_throughput.py` | 3x3 facet grid (rows = delay, cols = bandwidth) with throughput vs buffer per CC. |

Run results (2026-04-24): 81 runs in 44 min 59 s. Output in
`data/raw/exp1/`, parsed to `analysis/exp1_results.csv`, plotted to
`figures/exp1_throughput.png`.

Selected results at 100 Mbps:

| Condition | BBR | CUBIC | RENO |
|---|---|---|---|
| 10 ms RTT, any buffer | ~95 | ~95 | ~95 |
| 160 ms RTT, 10 pkt buffer | ~1 | ~1 | ~1 |
| 160 ms RTT, 100 pkt buffer | ~95 | ~22 | ~11 |
| 160 ms RTT, 1000 pkt buffer | ~95 | ~95 | ~48 |

On low-RTT links, CC choice doesn't matter. On high-RTT links,
CUBIC/RENO need buffer >= BDP to recover; BBR doesn't. Even BBR
collapses at buffer = 10 on high-RTT links because loss happens during
its bandwidth probing.

Note on plotting: `plot_throughput.py` forces matplotlib's `Agg`
backend. Without it, the process exits 139 (SIGSEGV) on this CachyOS
box from a GTK shutdown bug, even though the PNG writes correctly.

## Phase 2: buffer bloat (Exp 2)

Goal: at equal throughput on a deep buffer, show CUBIC/RENO inflate
RTT well above the propagation floor while BBR holds near it.

Conditions: 100 Mbps, 20 ms one-way delay (40 ms RTT), 1000-packet
buffer, 60 s flow per CC. BDP = 100 Mbps * 40 ms = 500 KB ~ 333
packets, so the buffer is ~3x BDP.

Files:

| Path | What it does |
|---|---|
| `experiments/exp2_bufferbloat.sh` | 60 s iperf3 per CC with `-i 0.1`. Saves one JSON per CC and prints a headline (throughput, retransmits, RTT min/mean/max, inflation). |
| `analysis/plot_rtt.py` | 2-panel figure: RTT-over-time on top with the 40 ms floor, throughput-over-time on bottom. Writes `analysis/exp2_inflation.csv`. |

The first version sampled RTT with a `ss -tin dst 10.0.0.1 | head -1`
loop. iperf3 keeps both a control socket and a data socket on port
5201, and `head -1` was grabbing the idle control socket. Result: a
flat 40 ms log while iperf3's own end-stats showed CUBIC at 120 ms.
Fix: drop the `ss` sampler; read RTT from iperf3's per-interval
`TCP_INFO` data, which comes off the data socket.

Run results (2026-04-24, ~3 min 14 s wall time):

| CC | Throughput | Retransmits | Min RTT | Mean RTT | Max RTT | Inflation |
|---|---|---|---|---|---|---|
| BBR   | 93.4 Mbps | 0   | 40.1 ms | 42.7 ms  | 82.9 ms  | 1.07x |
| CUBIC | 95.7 Mbps | 92  | 40.7 ms | 120.3 ms | 141.9 ms | 2.95x |
| RENO  | 95.6 Mbps | 888 | 40.7 ms | 104.2 ms | 141.0 ms | 2.56x |

The plot shows the textbook AIMD sawtooth in CUBIC: linear ramp from
~40 ms to ~140 ms as the buffer fills, then a sharp drop on each
tail-drop, then ramp again. RENO does the same with more aggressive
back-offs (888 retransmits vs 92 for CUBIC). BBR holds RTT near 40 ms
with small periodic spikes during PROBE_BW.

Same throughput, ~3x latency cost.

## Phase 3: fairness (Exp 3)

Goal: two TCP flows on a shared bottleneck. Three pairs:

1. BBR vs CUBIC
2. BBR vs BBR (intra-protocol baseline)
3. CUBIC vs CUBIC (second baseline)

Conditions: 100 Mbps, 40 ms RTT, 1000-packet buffer (~3x BDP, same as
Exp 2), 60 s. Flows started in parallel.

Files:

| Path | What it does |
|---|---|
| `experiments/exp3_fairness.sh` | Two iperf3 servers in `ns1` on ports 5201 and 5202. For each pair, two clients launched in parallel with their own `-C` flags, then `wait`. Buffer overridable via `BUF=`. |
| `analysis/plot_fairness.py` | 3-row figure with two flows per row. Writes `analysis/exp3_jain.csv` with mean throughput and Jain's index per pair. |

First run used `BUF=100` (~0.3x BDP). The fairness pattern was right
but total link utilization was only 45-60 Mbps - both flows lost
packets faster than CWND could grow. Bumped to 1000 (~3x BDP) and re-ran.

Discarded shallow-buffer numbers, kept here for completeness:

| Pair | A | B | Total | share_A | Jain |
|---|---|---|---|---|---|
| BBR vs CUBIC | 38.9 | 13.3 | 52.2 | 0.75 | 0.805 |
| BBR vs BBR | 30.5 | 30.1 | 60.6 | 0.50 | 1.000 |
| CUBIC vs CUBIC | 25.7 | 20.1 | 45.8 | 0.56 | 0.985 |

Final results, 1000-packet buffer (2026-04-24, ~3 min 20 s):

| Pair | A | B | Total | share_A | Jain |
|---|---|---|---|---|---|
| BBR vs CUBIC | 55.7 | 39.8 | 95.5 | 0.58 | 0.973 |
| BBR vs BBR | 50.1 | 43.6 | 93.7 | 0.53 | 0.995 |
| CUBIC vs CUBIC | 60.6 | 34.8 | 95.5 | 0.64 | 0.932 |

Output: `figures/exp3_fairness.png`, `analysis/exp3_jain.csv`.

BBR vs BBR converges to ~50/50 as expected. BBR vs CUBIC has BBR
slightly favored (58/42), much fairer than the original paper's
result; the Linux BBR implementation has had several fairness patches
since 2016. CUBIC vs CUBIC is the least fair here (0.932) because one
flow won the early CWND race in this single trial. Multi-trial
averaging would smooth this out.

## Phase 4: report

| Path | What it does |
|---|---|
| `report/REPORT.md` | Writeup. Sections: abstract, intro, methodology, the three experiments, discussion, theory connections, appendix. |
| `report/PRESENTATION.md` | 10-minute slide outline with timing budget and Q&A prep. |

Figures in `figures/`:

- `exp1_throughput.png` - 3x3 facet grid.
- `exp2_rtt.png` - RTT and throughput over time.
- `exp3_fairness.png` - per-pair, two flows each.

CSVs in `analysis/`:

- `exp1_results.csv` - 81 rows, one per condition.
- `exp2_inflation.csv` - 3 rows, RTT stats and inflation per CC.
- `exp3_jain.csv` - 3 rows, mean Mbps and Jain index per pair.

Top-line take-aways:

1. Exp 2 is the clearest single-figure result: equal throughput, ~3x
   RTT cost for loss-based CC.
2. Exp 1 reproduces the paper's high-RTT, shallow-buffer result (BBR
   95 Mbps, CUBIC 22 Mbps at 100 Mbps / 160 ms RTT / 100 pkt).
3. Exp 3's BBR vs CUBIC fairness was milder than the paper's (Jain
   0.97 vs the paper's marked unfairness). Likely upstream Linux
   patches post-2016.

## Artifact index

| Type | Path |
|---|---|
| Setup | `setup/setup.sh` |
| Setup | `setup/topology.sh` |
| Setup | `setup/shape.sh` |
| Driver | `experiments/exp1_throughput.sh` |
| Driver | `experiments/exp2_bufferbloat.sh` |
| Driver | `experiments/exp3_fairness.sh` |
| Analysis | `analysis/parse.py` |
| Analysis | `analysis/plot_throughput.py` |
| Analysis | `analysis/plot_rtt.py` |
| Analysis | `analysis/plot_fairness.py` |
| Data | `data/raw/exp{1,2,3}/*.json` |
| Output | `figures/*.png` |
| Output | `analysis/*.csv` |
| Doc | `report/REPORT.md` |
| Doc | `report/PRESENTATION.md` |
| Doc | `BUILD_LOG.md` |
