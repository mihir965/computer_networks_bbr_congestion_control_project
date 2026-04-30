# Gamma AI input

Paste everything below the next horizontal rule into Gamma's "Generate
from text" / "Paste in text" flow. Gamma treats `---` as a slide break.

For the figures: Gamma will not pull images from your local disk. After
generation, manually upload these PNGs to the slides marked
"INSERT FIGURE":

- Slide 5: `figures/exp1_throughput.png`
- Slide 6: `figures/exp2_rtt.png`
- Slide 7: `figures/exp3_fairness.png`

Settings to choose in Gamma:
- Number of cards: 9 (matches the slide breaks below)
- Tone: academic / formal
- Audience: technical
- Image style: minimal or none (we provide our own figures)

---

# Reproducing BBR: A Controlled Study of Bottleneck-Based Congestion Control

CS 552 — Computer Networks (Spring 2026)

Mihir Kulkarni · Chaitanya Ranaware · Piyoosha Gadi

Rutgers University · Prof. Minsung Kim

Speaker note: We empirically reproduced Google's BBR algorithm against CUBIC and RENO on a controlled Linux testbed. Three experiments, one finding: BBR trades a small throughput gap for much lower latency.

---

# The Problem: Loss-Based Congestion Control

- TCP congestion control decides how fast a sender can send.
- For 30+ years the standard was loss-based: send faster until packets drop, then back off (RENO, CUBIC).
- That worked when buffers were small. Modern routers ship with megabytes of buffering.
- A loss-based sender fills the buffer before it gets a signal, so latency balloons even though throughput looks fine. This is buffer bloat.
- Question: can we do congestion control without using loss as the signal?

Visual suggestion: a router icon with a deep queue filling up; arrows in from the left, packets stacking in the queue, slow trickle out the right.

---

# BBR's Idea: Model the Path

- BBR estimates two physical quantities of the path:
  - BtlBw: bottleneck bandwidth (max delivery rate observed).
  - RTprop: round-trip propagation delay (min RTT observed).
- Their product, BDP = BtlBw x RTprop, is the optimal amount of in-flight data.
- BBR paces at BtlBw and keeps in-flight near BDP. No queue, full link.
- It cycles through four phases to keep both estimates fresh: STARTUP, DRAIN, PROBE_BW, PROBE_RTT.
- Linux kernel since 4.9 (2016). Used by Google's WAN, YouTube, QUIC.

Visual suggestion: Kleinrock optimal-operating-point diagram. X-axis = data in flight. Two curves: throughput plateaus at BDP, RTT rises sharply past BDP. Mark "BBR operates here" at the knee, "loss-based operates here" past the knee.

---

# What We Built

- Two Linux network namespaces on one host (CachyOS, kernel 6.19), connected by a veth pair.
- Bottleneck emulated with `tc`:
  - `tbf` (root qdisc): rate limit.
  - `netem` (child qdisc): one-way delay and packet-count queue.
  - Applied symmetrically on both veths so RTT = 2 x one-way delay.
- TSO/GSO/GRO disabled on veths so the packet-count queue limit reflects real packets.
- Traffic: `iperf3 -C <bbr|cubic|reno>` to pick CC per flow. JSON output, 100 ms intervals.
- Same kernel for sender and receiver: identical BBR behavior, no virtualization noise.

Visual suggestion: topology diagram. Two boxes labeled "ns1 (server) 10.0.0.1" and "ns2 (client) 10.0.0.2" connected by a line labeled "veth pair". A box on the line labeled "tc tbf + netem".

---

# Experiment 1: Throughput Sweep

INSERT FIGURE: figures/exp1_throughput.png

- Sweep: 3 CCs x 3 bandwidths x 3 delays x 3 buffer sizes = 81 runs at 30 s each.
- Question: how close does each CC get to the bottleneck cap?

Selected results at 100 Mbps bottleneck:

| One-way delay | Buffer | BBR | CUBIC | RENO |
|---|---|---|---|---|
| 5 ms (10 ms RTT) | any | 95 | 95 | 95 |
| 20 ms (40 ms RTT) | 100 pkt | 95 | 22 | 11 |
| 80 ms (160 ms RTT) | 100 pkt | 95 | 22 | 11 |
| 80 ms (160 ms RTT) | 1000 pkt | 95 | 95 | 48 |

Headline: at shallow buffers and high RTT, CUBIC and RENO collapse. BBR holds near link capacity across nearly every condition. The advantage grows with delay, exactly as the paper predicted.

---

# Experiment 2: Buffer Bloat

INSERT FIGURE: figures/exp2_rtt.png

- Single 60 s flow per CC. 100 Mbps, 40 ms base RTT, 1000-packet buffer (~3x BDP).
- All three CCs reached 94-96 Mbps. The interesting axis is latency.

| CC | Throughput | Mean RTT | Inflation | Retransmits |
|---|---|---|---|---|
| BBR | 93.4 Mbps | 42.7 ms | 1.07x | 0 |
| CUBIC | 95.7 Mbps | 120.3 ms | 2.95x | 92 |
| RENO | 95.6 Mbps | 104.2 ms | 2.56x | 888 |

- BBR keeps latency at the propagation floor. CUBIC and RENO inflate RTT ~3x.
- BBR has zero retransmits because it never overfills the queue.

Headline: same throughput, three times the latency. Buffer bloat in one figure.

---

# Experiment 3: Fairness

INSERT FIGURE: figures/exp3_fairness.png

- Two iperf3 flows competing on the same shaped bottleneck (100 Mbps, 40 ms, 1000 pkt).
- Three pairings, Jain's index for steady state:

| Pair | Share split | Jain |
|---|---|---|
| BBR vs CUBIC | 0.58 / 0.42 | 0.973 |
| BBR vs BBR | 0.53 / 0.47 | 0.995 |
| CUBIC vs CUBIC | 0.64 / 0.36 | 0.932 |

- BBR vs BBR converges almost perfectly: intra-protocol fairness baseline.
- BBR vs CUBIC: BBR takes a modest extra share, milder than the 2016 paper. Likely cause: Linux BBR has accumulated fairness patches since publication.
- BBRv2 was created specifically to address BBR-vs-CUBIC fairness in deeper buffers.

---

# Paper Comparison

Reproduced cleanly:

- BBR matches link capacity regardless of buffer size.
- CUBIC and RENO under-utilize on shallow buffers + high RTT.
- BBR keeps RTT at the propagation floor; loss-based CCs inflate RTT 2.5-3x.
- BBR has zero retransmits in steady state.

Milder than the paper:

- BBR vs CUBIC unfairness was small (~58/42), not the dramatic split the paper showed for deep buffers.
- Likely cause: 3x-BDP buffer (vs the paper's much deeper BDP multiples), single trial per pair, and lower jitter than Google's WAN traces.

What we did not do:

- Lossy-link experiments (random loss via netem `loss`).
- Multi-flow scaling beyond 2 flows.
- BBRv2.

---

# Conclusions

- Loss-based CC is a latency tax. BBR removes most of it.
- BBR's win is biggest on high-RTT shallow-buffer paths, and on deep-buffer paths where buffer bloat dominates.
- Tradeoff: BBR is mildly unfair to loss-based flows in deep buffers. This motivated BBRv2.
- A controlled netns + tc testbed is enough to reproduce the paper's qualitative claims on a laptop.

Headline: throughput isn't the whole story. Latency under load is what BBR fixes.

Speaker note for closing: thank the audience, invite questions. Have backup slides ready on BBR's four phases, Kleinrock's optimal point, why netns over VMs, and Jain's index formula.
