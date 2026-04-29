# BBR Congestion Control — 10-Minute Presentation Outline

**Team:** Mihir Kulkarni, Chaitanya Ranaware, Piyoosha Gadi
**Course:** CS 552 — Computer Networks (Prof. Minsung Kim, Spring 2026)
**Date:** 2026-04-30
**Format:** 10 min hard stop + 3 min Q&A. ~9 slides at ~60–75 s each.

The audience is *not* assumed to remember the BBR paper. Lead with the
problem, then BBR's idea, then what we measured. Bias slides toward
**figures over text** — the three plots are the load-bearing artifacts.

---

## Slide 1 — Title (10 s)

- **Title:** Reproducing BBR: A Controlled Study of Bottleneck-Based Congestion Control
- Names, course, date.
- **Say:** "We empirically reproduced Google's BBR algorithm against CUBIC and RENO on a controlled Linux testbed. Three experiments, one finding: BBR trades a small throughput gap for dramatically lower latency."

---

## Slide 2 — The Problem (60 s)

**Visual:** Cartoon of a router with a deep buffer; two arrows — packets in, queue building up.

- TCP congestion control decides how fast a sender can send.
- For 30+ years the standard answer was **loss-based**: keep sending faster until packets drop, then back off (RENO, CUBIC).
- That worked when buffers were small. Modern buffers are huge → **bufferbloat**.
- A loss-based sender fills the buffer before it gets a signal, so latency balloons even though throughput looks fine.
- **Question:** can we do congestion control without using loss as the signal?

**Say:** "Loss-based CC misuses buffers as the congestion signal. The result is high throughput *and* high latency. BBR was Google's answer to that."

---

## Slide 3 — BBR's Idea (75 s)

**Visual:** The classic Kleinrock optimal-operating-point diagram — throughput plateaus at BDP, RTT rises after that. Mark "loss-based operates here" past the knee, "BBR operates here" at the knee.

- BBR estimates two physical quantities of the path:
  - **BtlBw** — bottleneck bandwidth (max delivery rate observed).
  - **RTprop** — round-trip propagation delay (min RTT observed).
- Their product, **BDP = BtlBw × RTprop**, is the optimal amount of in-flight data.
- BBR paces at BtlBw and keeps in-flight ≈ BDP. No queue, full link.
- It cycles through four phases: **STARTUP → DRAIN → PROBE_BW → PROBE_RTT** to keep both estimates fresh.
- In the Linux kernel since 4.9 (2016). Used by Google's WAN, YouTube, QUIC.

**Say:** "BBR doesn't react to loss. It builds a model of the path and runs *at* the optimal point instead of past it."

---

## Slide 4 — What We Built (60 s)

**Visual:** Topology diagram — `ns2 (client) ── veth ── ns1 (server)` with a "tc tbf + netem" box on the link.

- Two Linux network namespaces on one host (CachyOS, kernel 6.19), connected by a veth pair.
- Bottleneck emulated with `tc`:
  - `tbf` (root qdisc) — rate limit
  - `netem` (child qdisc) — one-way delay + queue limit (in packets)
  - Applied **symmetrically** on both veths so RTT = 2 × one-way delay.
- TSO/GSO/GRO disabled on veths so the packet-count queue limit means real packets.
- Traffic: `iperf3 -C <bbr|cubic|reno>` to pick the CC per flow. JSON output, 100 ms intervals.
- Same kernel for sender and receiver → identical BBR behavior across runs, no virtualization noise.

**Say:** "One host, two namespaces, a shaped link in the middle. Cheap, deterministic, reproducible."

---

## Slide 5 — Experiment 1: Throughput Sweep (75 s)

**Visual:** `figures/exp1_throughput.png` (3×3 grid: rows = delay 5/20/80 ms, cols = bandwidth 10/50/100 Mbps, x-axis = buffer size).

- Sweep: 3 CCs × 3 bandwidths × 3 delays × 3 buffer sizes = **81 runs**, 30 s each.
- Question: how close does each CC get to the bottleneck cap?
- **Result:**
  - At shallow buffers (10 packets) and high RTT (80 ms), CUBIC/RENO collapse — they need a deep buffer to fill the pipe.
  - BBR holds near link capacity across **every** condition.
  - The advantage grows with delay, exactly as the paper predicted.

**Say:** "BBR's throughput is roughly buffer-independent. CUBIC's isn't. That's the headline."

---

## Slide 6 — Experiment 2: Bufferbloat (75 s)

**Visual:** `figures/exp2_bufferbloat.png` — top panel RTT vs time, bottom panel throughput vs time. One line per CC.

- Single 60 s flow, 100 Mbps, 40 ms base RTT, 1000-packet buffer (≈ 3× BDP).
- All three CCs achieved ~94–96 Mbps throughput. The interesting axis is **latency**.
- Result table:

  | CC    | Throughput | Mean RTT | RTT inflation | Retransmits |
  |-------|------------|----------|---------------|-------------|
  | BBR   | 93.4 Mbps  | 42.7 ms  | **1.07×**     | 0           |
  | CUBIC | 95.7 Mbps  | 120.3 ms | 2.95×         | 92          |
  | RENO  | 95.6 Mbps  | 104.2 ms | 2.56×         | 888         |

- BBR keeps latency at the propagation floor. CUBIC and RENO inflate RTT ~3×.
- Bonus: BBR has **zero** retransmits because it never overfills the queue.

**Say:** "Same throughput, three times the latency. This is bufferbloat in one figure."

---

## Slide 7 — Experiment 3: Fairness (75 s)

**Visual:** `figures/exp3_fairness.png` — three rows, two flows per row.

- Two flows competing on the same shaped bottleneck (100 Mbps / 40 ms / 1000 pkt).
- Three pairings, Jain's index for steady state:

  | Pair             | Share split | Jain J |
  |------------------|-------------|--------|
  | BBR vs CUBIC     | 0.58 / 0.42 | 0.973  |
  | BBR vs BBR       | 0.53 / 0.47 | 0.995  |
  | CUBIC vs CUBIC   | 0.64 / 0.36 | 0.932  |

- BBR vs BBR converges almost perfectly. BBR vs CUBIC: BBR takes a modest extra share — milder than the 2016 paper, partly because we only ran one trial per pair and our buffer was 3× BDP rather than huge.
- Note: BBRv2 was created specifically to address BBR-vs-CUBIC fairness in deeper buffers.

**Say:** "Intra-protocol fairness is excellent. Cross-protocol, BBR is slightly greedier — a known issue the paper authors later fixed in v2."

---

## Slide 8 — What Lined Up With the Paper, What Didn't (60 s)

**Reproduced cleanly:**
- BBR matches link capacity regardless of buffer size.
- CUBIC/RENO under-utilize on shallow buffers + high RTT.
- BBR keeps RTT at the propagation floor; loss-based CCs inflate RTT 2.5–3×.
- BBR has zero retransmits in steady state.

**Where our results were milder than the paper:**
- BBR vs CUBIC unfairness was small (~58/42), not the dramatic split the paper showed for deep buffers. Most likely cause: buffer size and number of trials. A single host with namespaces also has lower jitter than the Google WAN traces.

**What we didn't do:**
- Lossy-link experiments (random loss via netem `loss`).
- Multi-flow scaling beyond 2 flows.
- BBRv2.

**Say:** "Qualitatively the paper reproduces. The fairness gap was smaller than expected — we'd want more trials and deeper buffers to push on that."

---

## Slide 9 — Conclusions (45 s)

- Loss-based CC is a latency tax. BBR removes most of it.
- BBR's win is biggest on **high-RTT, shallow-buffer** paths and on **deep-buffer** paths where bufferbloat dominates.
- Tradeoff: BBR is mildly unfair to loss-based flows in deep buffers — motivated BBRv2.
- A controlled netns + `tc` testbed is more than enough to reproduce the paper's qualitative claims on a laptop.

**Say:** "If you take one thing away: throughput isn't the whole story. Latency under load is what BBR actually fixes."

---

## Slide 10 — (Optional buffer) Backup Slides for Q&A

Have these ready but don't show unless asked:

- The four BBR phases (STARTUP/DRAIN/PROBE_BW/PROBE_RTT) with a brief diagram.
- Kleinrock 1979 optimal operating point — why pacing at BtlBw with cwnd ≈ BDP is provably optimal.
- Why we used network namespaces instead of VMs (same kernel, no NIC virtualization, instant teardown).
- Where in the kernel BBR lives (`net/ipv4/tcp_bbr.c`), and the `-C` flag's interaction with `tcp_allowed_congestion_control`.
- Jain's fairness index formula.

---

## Speaker Timing Cheat Sheet

| Slide | Topic                    | Target | Cumulative |
|-------|--------------------------|--------|------------|
| 1     | Title                    | 0:10   | 0:10       |
| 2     | Problem (bufferbloat)    | 1:00   | 1:10       |
| 3     | BBR's idea               | 1:15   | 2:25       |
| 4     | Testbed                  | 1:00   | 3:25       |
| 5     | Exp 1 — throughput       | 1:15   | 4:40       |
| 6     | Exp 2 — bufferbloat      | 1:15   | 5:55       |
| 7     | Exp 3 — fairness         | 1:15   | 7:10       |
| 8     | Paper comparison         | 1:00   | 8:10       |
| 9     | Conclusions              | 0:45   | 8:55       |
| —     | Buffer / breath          | 1:00   | 9:55       |

Leaves ~5 s slack before the hard stop. If you're running long, **cut from Slide 8** (paper comparison) first — Slides 5–7 are the "what you did" content the assignment asks for.

---

## Solo Delivery Tips

- Rehearse end-to-end **at least twice** with a stopwatch. The first run will overshoot; trim filler from the spots that ran long.
- Mark the 5:00 mid-point in your notes (should be mid-Slide 6). If you're past Slide 6 at 5:30, skip the "Bonus: zero retransmits" line and move on.
- Don't read the slide. Each slide has one **say:** line — that's the spoken thesis. Everything else is reference for the audience to look at.
- Keep water nearby. 10 minutes of solo talking is longer than it sounds.

---

## Anticipated Q&A

- **"Why didn't you test BBRv2?"** — BBRv2 isn't mainline in the kernel we used; v1 is the default. v2 was Google's response to the fairness issues we discussed on Slide 7.
- **"Why netns instead of two machines?"** — Same kernel = identical BBR implementation, no NIC virtualization, deterministic. Tradeoff: no real wireless effects.
- **"Did you account for TSO/GSO?"** — Yes, disabled on the veths so netem's packet-count queue limit reflects real packets.
- **"How did you measure RTT?"** — From iperf3's per-interval `TCP_INFO` on the data socket (not `ss`, which we found grabs the control socket).
- **"Single trial — is that enough?"** — For Exp 1 and 2 the effect sizes are large; for Exp 3 single trials are a real limitation we'd repeat with more runs.
- **"Why is BBR's throughput slightly lower than CUBIC's in Exp 2?"** — BBR deliberately keeps the queue empty, so it occasionally underestimates BtlBw during PROBE_RTT. CUBIC fills the buffer, so it sustains slightly higher peak rate at the cost of latency.
