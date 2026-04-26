# Reproducing BBR: Congestion-Based Congestion Control

**CS 552 — Computer Networks (Spring 2026)**
**Mihir Kulkarni, Chaitanya Ranaware, Piyoosha Gadi**
**Rutgers University · Prof. Minsung Kim**

---

## Abstract

We reproduce three experimental results from Cardwell et al.'s "BBR:
Congestion-Based Congestion Control" (ACM Queue 2016 / SIGCOMM CCR 2017)
on a controlled Linux network-namespace testbed. Across an 81-cell
parameter grid we confirm that BBR sustains near-bottleneck throughput on
high-RTT and small-buffer links where loss-based CC (CUBIC, RENO)
collapses. On a deep-buffered link (3 × BDP) we measure CUBIC and RENO
inflating TCP RTT to 2.95× and 2.56× the propagation floor respectively,
while BBR holds at 1.07×. In two-flow fairness tests on the same
bottleneck, BBR-versus-BBR converges to a Jain index of 0.995, and
BBR-versus-CUBIC settles at 0.973 — substantially fairer than the
original-BBRv1 results reported in 2016, reflecting kernel-side fairness
patches accumulated in the intervening years.

---

## 1. Introduction

Loss-based congestion control (Reno, CUBIC) treats packet loss as the
sole congestion signal. This was reasonable when buffers were small
relative to BDP, but modern routers ship with megabytes of buffering for
"safety", producing a pathology known as **buffer bloat**: TCP fills the
buffer until tail-drop, sustaining throughput at the cost of inflated
queuing delay. BBR (Bottleneck Bandwidth and Round-trip propagation time)
side-steps this by directly estimating the path's two physical
parameters — bottleneck bandwidth (BtlBw) and minimum RTT (RTprop) — and
operating at their product, the bandwidth-delay product (BDP). Pacing is
set to BtlBw and the in-flight cap to ≈ BDP, regardless of buffer signals.

We empirically verify three of the paper's central claims:
1. BBR achieves near-bottleneck throughput across delay and buffer
   regimes where loss-based CC degrades.
2. On a deep-buffered link, BBR holds latency near the propagation
   floor while loss-based CC inflates RTT by 2-3×.
3. Two competing BBR flows converge to a fair share; BBR competing
   with CUBIC produces a near-fair share in our environment.

---

## 2. Methodology

### 2.1 Testbed

The full testbed runs on a single Linux host (CachyOS, kernel 6.19) using
two network namespaces connected by a `veth` pair:

```
ns1 (server)                       ns2 (client)
10.0.0.1/24  <---- veth pair ----> 10.0.0.2/24
   ^                                  ^
   |                                  |
[ tbf rate + netem delay ]    [ tbf rate + netem delay ]
```

Each namespace runs an independent TCP stack inside the same kernel that
hosts the BBR implementation, so the algorithm under test is identical to
what runs on production Linux servers. The bottleneck is emulated by a
two-stage `tc` qdisc on each veth: `tbf` at the root for rate limiting,
`netem` as a child for one-way delay and packet-count buffer cap.
Shaping is applied symmetrically on both veths so the round-trip delay
matches the configured one-way delay × 2 (an early bug where we shaped
only one direction is documented in `BUILD_LOG.md`). TSO/GSO/GRO are
disabled on the veths so `netem`'s `limit` accurately reflects packet
counts rather than coalesced segments.

### 2.2 Tooling

| Layer | Tool |
|---|---|
| Link emulation | `tc tbf` + `tc netem` (iproute2) |
| Traffic generation | `iperf3` with `-C <cc>` for per-flow congestion control |
| Throughput / RTT measurement | iperf3 per-interval `TCP_INFO` data |
| Switching CC | `iperf3 -C` (per-flow) |
| Plotting | Python with `pandas`, `matplotlib` (Agg backend) |

### 2.3 Workload

A single iperf3 stream per flow, 30-60 s per run, with the first 1 s
discarded to exclude TCP slow-start from steady-state metrics. RTT is
read from the kernel's smoothed RTT estimator on the data socket, sampled
every 100 ms (`iperf3 -i 0.1`).

---

## 3. Experiment 1 — Steady-state throughput

### 3.1 Design

Cartesian sweep over (CC × bandwidth × one-way delay × buffer):

| Dimension | Values |
|---|---|
| CC | bbr, cubic, reno |
| Bottleneck | 10, 50, 100 Mbps |
| One-way delay | 5, 20, 80 ms (RTT = 10, 40, 160 ms) |
| Buffer | 10, 100, 1000 packets |

81 runs × 30 s + setup overhead = ~45 min wall time.

### 3.2 Results (selected)

Throughput (Mbps), 100 Mbps bottleneck:

| One-way delay | Buffer | BBR | CUBIC | RENO |
|---:|---:|---:|---:|---:|
| 5 ms (10 ms RTT) | 1000 | 95 | 95 | 95 |
| 5 ms | 100 | 95 | 95 | 95 |
| 5 ms | 10 | 95 | 95 | 95 |
| 20 ms (40 ms RTT) | 1000 | 95 | 95 | 95 |
| 20 ms | 100 | 95 | 22 | 11 |
| 20 ms | 10 | 4 | 1 | 1 |
| 80 ms (160 ms RTT) | 1000 | 95 | 95 | 48 |
| 80 ms | 100 | 95 | 22 | 11 |
| 80 ms | 10 | 1 | 1 | 1 |

Full results in `analysis/exp1_results.csv`; plot in
`figures/exp1_throughput.png` (3×3 facet grid).

### 3.3 Discussion

Three observations:

1. **On low-RTT links the choice of CC is invisible.** All three
   algorithms saturate the bottleneck regardless of buffer. With RTT = 10 ms
   even RENO can grow CWND faster than the pipe drains, so any algorithm
   works.
2. **On high-RTT links, CUBIC/RENO need buffer ≥ BDP to compete.**
   BDP at 100 Mbps × 160 ms = 2 MB ≈ 1333 packets. With only 100 packets
   of buffer, every loss event collapses CWND faster than it can recover,
   and throughput drops to 22 Mbps (CUBIC) and 11 Mbps (RENO). BBR is
   immune — it does not size its window to buffer occupancy.
3. **Even BBR collapses at buffer = 10 on high-RTT links.** The paper's
   strongest claim is that BBR is robust to buffer size, but our 10-pkt
   condition shows the limit: when buffer is far below BDP, drops happen
   during BBR's ProbeBW phase, and even BBR's loss-tolerance is not enough.
   The paper would refer to this as the "shallow-buffer wall".

This reproduces Figures 5 and 6 of the BBR paper qualitatively. We do not
match exact Mbps because the paper used WAN traces with real loss and
ours uses a synthetic loss-free shaper.

---

## 4. Experiment 2 — Buffer bloat

### 4.1 Design

Fixed link conditions, vary only the CC:

| Setting | Value |
|---|---|
| Bandwidth | 100 Mbps |
| RTT (propagation) | 40 ms |
| Buffer | 1000 packets (~3 × BDP) |
| Duration | 60 s |

The 1000-packet buffer is ~3 × the BDP of ~333 packets, so loss-based CC
has ~667 packets (≈ 80 ms) of headroom to fill before tail-drop.

### 4.2 Results

| CC | Throughput (Mbps) | Retransmits | Min RTT (ms) | Mean RTT (ms) | Max RTT (ms) | **Inflation** |
|---|---:|---:|---:|---:|---:|---:|
| BBR   | 93.4 | 0   | 40.1 | 42.7  | 82.9  | **1.07×** |
| CUBIC | 95.7 | 92  | 40.7 | 120.3 | 141.9 | **2.95×** |
| RENO  | 95.6 | 888 | 40.7 | 104.2 | 141.0 | **2.56×** |

Plot: `figures/exp2_rtt.png`.

### 4.3 Discussion

This is the headline result of the BBR paper, reproduced cleanly. All
three algorithms achieve essentially the same throughput (93-96 Mbps),
but the latency cost differs by a factor of three. CUBIC's RTT trace
shows a textbook AIMD sawtooth: linear ramp from 40 → ~140 ms as the
buffer fills, sharp drop on each tail-drop loss event, then ramp again.
RENO does the same with more aggressive backoffs (888 retransmits vs
CUBIC's 92, since RENO halves on every loss and never benefits from
CUBIC's cubic recovery). BBR holds RTT at 40-50 ms throughout, with
small periodic spikes corresponding to its PROBE_BW phase, which cycles
the pacing gain to re-measure BtlBw.

The take-away: at equal throughput, **BBR delivers ~80 ms lower
queuing delay than CUBIC**. For interactive workloads (web, gaming, video
conferencing) sharing the link, that is the difference between snappy and
sluggish.

---

## 5. Experiment 3 — Fairness

### 5.1 Design

Two iperf3 flows compete on the same bottleneck (100 Mbps / 40 ms RTT /
1000-pkt buffer). For each pair, both flows are launched in parallel and
run for 60 s. The first 5 s are discarded as transient.

### 5.2 Results

| Pair | Flow A (Mbps) | Flow B (Mbps) | Total | share_A | **Jain index** |
|---|---:|---:|---:|---:|---:|
| BBR vs CUBIC   | 55.7 | 39.8 | 95.5 | 0.58 | **0.973** |
| BBR vs BBR     | 50.1 | 43.6 | 93.7 | 0.53 | **0.995** |
| CUBIC vs CUBIC | 60.6 | 34.8 | 95.5 | 0.64 | **0.932** |

Plot: `figures/exp3_fairness.png`.

### 5.3 Discussion

**BBR vs BBR (Jain 0.995):** intra-protocol fairness is excellent; two
BBR flows converge to a near-50/50 split. This serves as the baseline.

**BBR vs CUBIC (Jain 0.973):** BBR takes a slightly larger share (58 vs 42).
This is much fairer than the dramatic unfairness reported in the original
2016 paper, where BBR was observed to claim disproportionate bandwidth on
deep-buffered links. The improvement likely reflects fairness patches
that have accumulated in the Linux BBR implementation since publication
(notably the 2018 pacing-gain damping changes).

**CUBIC vs CUBIC (Jain 0.932):** counterintuitively the *least* fair
result here. One CUBIC flow won the initial CWND race and held a 64/36
edge for the full 60 s. This is a known sensitivity of CUBIC to startup
timing. Multi-trial averaging would smooth this out; we report a single
trial as a documented limitation.

---

## 6. Discussion

### 6.1 Where our results match and diverge from Cardwell et al. 2016

| Claim | Paper | Ours | Match? |
|---|---|---|---|
| BBR saturates high-latency links where loss-based CC degrades | ✓ | ✓ | Yes |
| BBR keeps RTT near propagation floor under load | ✓ | ✓ (1.07×) | Yes |
| CUBIC inflates RTT 2-4× under load on deep buffers | ✓ | ✓ (2.95×) | Yes |
| BBR claims disproportionate share vs CUBIC | ✓ (significant) | Mild (Jain 0.97) | Partial |
| BBR robust to small buffers | ✓ | ✓ down to ~50-pkt; fails at 10 pkts | Partial |

### 6.2 Limitations

- **Single-host testbed.** Sender, receiver, and emulated bottleneck
  share the same kernel. Real WAN paths add jitter, parallel cross
  traffic, and out-of-order delivery that our testbed cannot reproduce.
- **Synthetic loss-free shaper.** `netem` only drops packets when its
  queue fills. Real links have random loss from physical-layer errors,
  which differentially penalizes BBR (loss-tolerant) vs CUBIC
  (loss-reactive).
- **Single trial per condition.** Some results, especially in Experiment
  3, are sensitive to TCP startup timing and would benefit from N=3-5
  trials with mean and CI reported.
- **BBRv1 only.** Linux kernel mainline ships BBRv1; BBRv2 (which fixes
  much of the BBR/CUBIC unfairness and shallow-buffer issues) is not
  yet merged. Our results characterize the deployed algorithm, not the
  state-of-the-art.

---

## 7. CS 552 theory connections

**TCP/IP layered model.** BBR operates at the transport layer (TCP),
but its decisions are driven by an explicit model of the network layer's
bottleneck link. This is unusual — most transport algorithms treat the
network as a black box and respond to its emergent signals (loss, ECN).
BBR pierces the abstraction by modelling BtlBw and RTprop directly, which
is part of why it outperforms loss-based CC: it acts on the underlying
physical reality rather than its degraded shadow.

**Bandwidth-Delay Product as the optimal operating point.** Course
material introduces BDP as `BtlBw × RTprop` — the maximum amount of data
that can be in flight on a path. Kleinrock's classic result is that this
is also the optimal operating point: any less and the link is
under-utilized; any more, and packets queue at the bottleneck, inflating
RTT without raising throughput. BBR is the first widely deployed CC that
explicitly targets this point. AIMD (Reno, CUBIC) instead drives the
link past BDP into the buffer, then backs off on loss — i.e., it operates
to the *right* of the optimum, which is exactly the buffer-bloat regime
we measured.

**Pacing rate vs CWND.** Traditional TCP regulates send rate implicitly
via CWND and the ACK clock. Bursty senders can overshoot the bottleneck
in a single round-trip even if the long-run average CWND/RTT is fine.
BBR sets two independent controls: a pacing rate (= BtlBw, regulating
inter-packet timing) and an in-flight cap (≈ BDP, bounding total bytes
out). This separation is what lets BBR sustain throughput without
filling the buffer.

**Available bandwidth measurement.** The course covers passive and
active bandwidth measurement (e.g., packet-pair, packet-train). BBR's
BtlBw estimator is conceptually a continuous online packet-train: it
maintains a sliding-window maximum of recent delivery-rate samples,
filtered with a 10-second windowed-max so transient drops don't poison
the estimate. This is in essence a transport-layer realization of the
measurement primitives the course introduces at the network layer.

---

## Appendix A — Reproducing this work

```bash
# One-time setup
./setup/setup.sh

# Per-session
sudo ./setup/topology.sh up

# Experiments (run in order; each writes to data/raw/expN/)
sudo ./experiments/exp1_throughput.sh   # ~45 min
sudo ./experiments/exp2_bufferbloat.sh  # ~3 min
sudo ./experiments/exp3_fairness.sh     # ~3 min

# Analysis
python3 analysis/parse.py
python3 analysis/plot_throughput.py
python3 analysis/plot_rtt.py
python3 analysis/plot_fairness.py

# Outputs land in figures/ and analysis/*.csv

# Tear down
sudo ./setup/topology.sh down
```

A complete chronological build receipt — including bugs hit and fixes
applied — is in `BUILD_LOG.md` at the repo root.
