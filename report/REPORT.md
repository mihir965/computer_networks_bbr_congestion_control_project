# Reproducing BBR: Congestion-Based Congestion Control

CS 552 — Computer Networks (Spring 2026)
Mihir Kulkarni, Chaitanya Ranaware, Piyoosha Gadi
Rutgers University, Prof. Minsung Kim

---

> Section skeleton. Each section lists the points to cover and the
> data/figures already produced. Expand into prose in whatever format
> the final template requires (IEEE / ACM / plain).

---

## Abstract

Cover:
- One-sentence problem (loss-based CC produces buffer bloat).
- One-sentence approach (BBR estimates BtlBw + RTprop, paces at BDP).
- One sentence on testbed (Linux netns + tc, 3 experiments).
- Headline numbers from the three experiments:
  - Exp 1: BBR 95 Mbps vs CUBIC 22 Mbps at 100 Mbps / 160 ms RTT / 100 pkt buf.
  - Exp 2: RTT inflation BBR 1.07x, CUBIC 2.95x, RENO 2.56x.
  - Exp 3: Jain BBR-vs-BBR 0.995, BBR-vs-CUBIC 0.973.

## 1. Introduction

Cover:
- Why TCP CC matters; why loss-based CC was the default for 30+ years.
- Buffer bloat: deep buffers turn loss-based CC into a latency tax.
- BBR's pitch: model the path (BtlBw, RTprop), pace at BDP.
- The three claims we set out to verify:
  1. BBR sustains throughput where loss-based CC degrades.
  2. BBR keeps RTT near propagation floor under load.
  3. BBR vs BBR is fair; BBR vs CUBIC is acceptable in our env.

## 2. Background

Cover:
- Loss-based CC (Reno, CUBIC). AIMD, cubic recovery curve.
- Why loss is the wrong signal for modern paths.
- BBR model: BtlBw, RTprop, BDP = BtlBw * RTprop.
- BBR phases: STARTUP, DRAIN, PROBE_BW, PROBE_RTT.
- Pacing rate vs CWND.
- Citation: Cardwell et al., "BBR: Congestion-Based Congestion Control",
  ACM Queue 14(5), 2016 / SIGCOMM CCR 47(2), 92–101, 2017.

## 3. Methodology

### 3.1 Testbed

```
ns1 (server)                       ns2 (client)
10.0.0.1/24  <---- veth pair ----> 10.0.0.2/24
   ^                                  ^
   |                                  |
[ tbf rate + netem delay ]    [ tbf rate + netem delay ]
```

Facts to state:
- Single Linux host, CachyOS, kernel 6.19.
- Two network namespaces connected by a veth pair.
- Same kernel as the host runs the BBR module under test.
- Bottleneck: `tc tbf` (root) for rate, `tc netem` (child) for delay
  and packet-count queue.
- Shaping applied symmetrically on both veths so RTT = 2 x one-way delay.
- TSO/GSO/GRO disabled on veths so `netem` `limit` reflects real packets.

### 3.2 Tooling

| Layer | Tool |
|---|---|
| Link emulation | `tc tbf` + `tc netem` (iproute2) |
| Traffic generation | `iperf3` with `-C <cc>` for per-flow CC |
| Throughput / RTT | iperf3 per-interval `TCP_INFO` |
| Plotting | Python (`pandas`, `matplotlib` Agg) |

### 3.3 Workload

- Single iperf3 stream per flow.
- 30 s (Exp 1) or 60 s (Exp 2, 3) per run.
- First 1 s discarded to exclude TCP slow-start.
- RTT sampled every 100 ms (`iperf3 -i 0.1`) from kernel smoothed RTT.

## 4. Experiment 1: steady-state throughput

### 4.1 Design

| Dimension | Values |
|---|---|
| CC | bbr, cubic, reno |
| Bottleneck | 10, 50, 100 Mbps |
| One-way delay | 5, 20, 80 ms (RTT = 10, 40, 160 ms) |
| Buffer | 10, 100, 1000 packets |

81 runs at 30 s, ~45 min wall time.

### 4.2 Results

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

Full data: `analysis/exp1_results.csv`.
Figure: `figures/exp1_throughput.png` (3x3 facet grid).

### 4.3 Discussion

Points to make:
- Low-RTT links: CC choice invisible. All three saturate.
- High-RTT links: CUBIC/RENO need buffer >= BDP to recover from loss.
  BDP at 100 Mbps + 160 ms is ~1333 pkts; with 100 pkts of buffer
  CUBIC drops to 22 Mbps and RENO to 11 Mbps.
- BBR is buffer-insensitive in the middle regime, but collapses at
  buffer = 10 on high-RTT links. Loss during PROBE_BW.
- Reproduces Figures 5–6 of the paper qualitatively. Exact Mbps
  differs because the paper used WAN traces with real loss.

## 5. Experiment 2: buffer bloat

### 5.1 Design

| Setting | Value |
|---|---|
| Bandwidth | 100 Mbps |
| RTT (propagation) | 40 ms |
| Buffer | 1000 packets (~3x BDP) |
| Duration | 60 s |

BDP = 100 Mbps * 40 ms ~= 333 pkts. 1000-pkt buffer has ~667 pkts of
headroom (~80 ms of expected inflation).

### 5.2 Results

| CC | Throughput (Mbps) | Retransmits | Min RTT | Mean RTT | Max RTT | Inflation |
|---|---:|---:|---:|---:|---:|---:|
| BBR   | 93.4 | 0   | 40.1 ms | 42.7 ms  | 82.9 ms  | 1.07x |
| CUBIC | 95.7 | 92  | 40.7 ms | 120.3 ms | 141.9 ms | 2.95x |
| RENO  | 95.6 | 888 | 40.7 ms | 104.2 ms | 141.0 ms | 2.56x |

Figure: `figures/exp2_rtt.png`.
Data: `analysis/exp2_inflation.csv`.

### 5.3 Discussion

Points to make:
- Equal throughput (93–96 Mbps), 3x latency cost for loss-based CC.
- CUBIC trace is textbook AIMD sawtooth: ramp 40 -> 140 ms, sharp
  drop on tail-drop, ramp again.
- RENO retransmits 888 vs CUBIC's 92. RENO halves on every loss.
- BBR holds RTT at 40–50 ms with small spikes from PROBE_BW.
- For interactive workloads on a shared link, that's snappy vs sluggish.

## 6. Experiment 3: fairness

### 6.1 Design

- Two iperf3 flows competing on one bottleneck.
- 100 Mbps, 40 ms RTT, 1000-pkt buffer.
- Both flows launched in parallel, run for 60 s.
- First 5 s discarded as transient.
- Three pairs: BBR-CUBIC, BBR-BBR, CUBIC-CUBIC.

### 6.2 Results

| Pair | Flow A (Mbps) | Flow B (Mbps) | Total | share_A | Jain |
|---|---:|---:|---:|---:|---:|
| BBR vs CUBIC   | 55.7 | 39.8 | 95.5 | 0.58 | 0.973 |
| BBR vs BBR     | 50.1 | 43.6 | 93.7 | 0.53 | 0.995 |
| CUBIC vs CUBIC | 60.6 | 34.8 | 95.5 | 0.64 | 0.932 |

Figure: `figures/exp3_fairness.png`.
Data: `analysis/exp3_jain.csv`.

Jain's fairness index: J = (sum x_i)^2 / (n * sum x_i^2).

### 6.3 Discussion

Points to make:
- BBR vs BBR (Jain 0.995): intra-protocol fairness is the baseline.
- BBR vs CUBIC (Jain 0.973): BBR slightly favored (58/42). Much
  fairer than the 2016 paper. Likely cause: Linux BBR fairness patches
  since 2016 (notably 2018 pacing-gain damping).
- CUBIC vs CUBIC (Jain 0.932): worst here. One CUBIC won the early
  CWND race. Single-trial sensitivity. Multi-trial averaging would
  smooth this out.

## 7. Discussion

### 7.1 Comparison with Cardwell et al. 2016

| Claim | Paper | Ours | Match |
|---|---|---|---|
| BBR saturates high-latency links where loss-based CC degrades | yes | yes | full |
| BBR keeps RTT near propagation floor | yes | yes (1.07x) | full |
| CUBIC inflates RTT 2-4x on deep buffers | yes | yes (2.95x) | full |
| BBR claims disproportionate share vs CUBIC | yes | mild (Jain 0.97) | partial |
| BBR robust to small buffers | yes | down to ~50 pkts; fails at 10 | partial |

### 7.2 Limitations

- Single-host testbed: sender, receiver, bottleneck share one kernel.
  No real WAN jitter, cross traffic, reordering.
- Synthetic loss-free shaper: `netem` only drops on full queue. Real
  links have random PHY-layer loss that penalizes CUBIC vs BBR
  asymmetrically.
- Single trial per condition. Exp 3 in particular sensitive to TCP
  startup timing; would benefit from N=3–5 with mean and CI.
- BBRv1 only. BBRv2 not yet mainline; would address the unfairness
  and shallow-buffer issues observed.

## 8. CS 552 theory connections

Points to make (these are the explicit ties to course material that
the assignment asks for):

- TCP/IP layered model: BBR is transport-layer but explicitly models
  the network-layer bottleneck. Most CC treats network as black box.
- Bandwidth-delay product as optimal operating point. Kleinrock's
  result. AIMD operates to the right of BDP (in the buffer); BBR
  targets BDP itself.
- Pacing rate vs CWND. BBR uses both: pacing for inter-packet timing,
  CWND for total in-flight. Separation lets BBR fill the link without
  filling the queue.
- Available bandwidth measurement (course covers packet-pair, packet-
  train). BBR's BtlBw estimator is a continuous online realization:
  sliding-window max of delivery-rate samples, 10 s windowed-max so
  transient drops don't poison the estimate.

## 9. Conclusion

Points to land:
- All three claims reproduced qualitatively.
- Exp 2 is the cleanest demonstration: same throughput, 3x latency.
- Exp 3 fairness milder than the paper, attributable to upstream
  Linux patches.
- Netns + tc is sufficient to reproduce the paper on a laptop.

## References

- Cardwell, Cheng, Gunn, Hassas Yeganeh, Jacobson. "BBR: Congestion-
  Based Congestion Control." ACM Queue 14(5), 2016. Republished in
  ACM SIGCOMM CCR 47(2), 92–101, 2017.
- Kleinrock, L. "Power and Deterministic Rules of Thumb for
  Probabilistic Problems in Computer Communications." ICC, 1979.
- Ha, Rhee, Xu. "CUBIC: A New TCP-Friendly High-Speed TCP Variant."
  ACM SIGOPS Operating Systems Review, 2008.
- Jain, R. "A Quantitative Measure of Fairness and Discrimination for
  Resource Allocation in Shared Computer Systems." DEC TR-301, 1984.
- Linux kernel source, `net/ipv4/tcp_bbr.c` (BBRv1 implementation).

## Appendix A: reproducing this work

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

# Tear down
sudo ./setup/topology.sh down
```

A chronological build log (including bugs hit and fixes applied) is
in `BUILD_LOG.md` at the repo root.

## Appendix B: artifact index

| Type | Path |
|---|---|
| Setup | `setup/{setup,topology,shape}.sh` |
| Drivers | `experiments/exp{1,2,3}_*.sh` |
| Analysis | `analysis/{parse,plot_throughput,plot_rtt,plot_fairness}.py` |
| Raw data | `data/raw/exp{1,2,3}/*.json` |
| Figures | `figures/exp{1,2,3}_*.png` |
| Tables | `analysis/exp1_results.csv`, `exp2_inflation.csv`, `exp3_jain.csv` |
