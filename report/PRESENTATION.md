# BBR presentation outline

10 minutes hard stop, 3 min Q&A. Nine main slides plus a backup.

The audience does not know the BBR paper. Lead with the problem, then
BBR's idea, then what we measured. Bias the slides toward figures.

## Slide 1: title (10 s)

- Title: Reproducing BBR: a controlled study of bottleneck-based
  congestion control.
- Names, course, date.
- Say: "We empirically reproduced Google's BBR algorithm against CUBIC
  and RENO on a controlled Linux testbed. Three experiments, one
  finding: BBR trades a small throughput gap for much lower latency."

## Slide 2: the problem (60 s)

Visual: cartoon of a router with a deep buffer, arrows in, queue
building.

- TCP congestion control decides how fast a sender can send.
- For 30+ years the standard answer was loss-based: keep sending
  faster until packets drop, then back off (RENO, CUBIC).
- That worked when buffers were small. Modern buffers are huge, which
  produces buffer bloat.
- A loss-based sender fills the buffer before it gets a signal, so
  latency balloons even though throughput looks fine.
- Question: can we do congestion control without using loss as the
  signal?

Say: "Loss-based CC misuses buffers as the congestion signal. The
result is high throughput and high latency. BBR was Google's answer."

## Slide 3: BBR's idea (75 s)

Visual: Kleinrock optimal-operating-point diagram. Throughput plateaus
at BDP, RTT rises after that. Mark "loss-based operates here" past the
knee, "BBR operates here" at the knee.

- BBR estimates two physical quantities of the path:
  - BtlBw: bottleneck bandwidth (max delivery rate observed).
  - RTprop: round-trip propagation delay (min RTT observed).
- Their product, BDP = BtlBw * RTprop, is the optimal amount of
  in-flight data.
- BBR paces at BtlBw and keeps in-flight near BDP. No queue, full link.
- Cycles through four phases: STARTUP, DRAIN, PROBE_BW, PROBE_RTT, to
  keep both estimates fresh.
- In the Linux kernel since 4.9 (2016). Used by Google's WAN, YouTube,
  QUIC.

Say: "BBR doesn't react to loss. It builds a model of the path and
runs at the optimal point instead of past it."

## Slide 4: what we built (60 s)

Visual: topology diagram. `ns2 (client) -- veth -- ns1 (server)` with
a "tc tbf + netem" box on the link.

- Two Linux network namespaces on one host (CachyOS, kernel 6.19),
  connected by a veth pair.
- Bottleneck emulated with `tc`:
  - `tbf` (root qdisc): rate limit.
  - `netem` (child qdisc): one-way delay and packet-count queue.
  - Applied symmetrically on both veths so RTT = 2 x one-way delay.
- TSO/GSO/GRO disabled on veths so the packet-count queue limit means
  real packets.
- Traffic: `iperf3 -C <bbr|cubic|reno>` to pick CC per flow. JSON
  output, 100 ms intervals.
- Same kernel for sender and receiver. Identical BBR behavior across
  runs, no virtualization noise.

Say: "One host, two namespaces, a shaped link in the middle. Cheap,
deterministic, reproducible."

## Slide 5: Exp 1, throughput sweep (75 s)

Visual: `figures/exp1_throughput.png` (3x3 grid: rows = delay 5/20/80
ms, cols = bandwidth 10/50/100 Mbps, x-axis = buffer size).

- Sweep: 3 CCs x 3 bandwidths x 3 delays x 3 buffer sizes = 81 runs,
  30 s each.
- Question: how close does each CC get to the bottleneck cap?
- Result:
  - At shallow buffers (10 packets) and high RTT (80 ms), CUBIC and
    RENO collapse. They need a deep buffer to fill the pipe.
  - BBR holds near link capacity across every condition.
  - The advantage grows with delay, as the paper predicted.

Say: "BBR's throughput is roughly buffer-independent. CUBIC's isn't.
That's the headline."

## Slide 6: Exp 2, buffer bloat (75 s)

Visual: `figures/exp2_rtt.png`. Top panel RTT vs time, bottom panel
throughput vs time. One line per CC.

- Single 60 s flow, 100 Mbps, 40 ms base RTT, 1000-packet buffer
  (~3x BDP).
- All three CCs reached 94-96 Mbps. The interesting axis is latency.

| CC    | Throughput | Mean RTT | Inflation | Retransmits |
|-------|------------|----------|-----------|-------------|
| BBR   | 93.4 Mbps  | 42.7 ms  | 1.07x     | 0           |
| CUBIC | 95.7 Mbps  | 120.3 ms | 2.95x     | 92          |
| RENO  | 95.6 Mbps  | 104.2 ms | 2.56x     | 888         |

- BBR keeps latency at the propagation floor. CUBIC and RENO inflate
  RTT by ~3x.
- BBR has zero retransmits because it never overfills the queue.

Say: "Same throughput, three times the latency. Buffer bloat in one
figure."

## Slide 7: Exp 3, fairness (75 s)

Visual: `figures/exp3_fairness.png`. Three rows, two flows per row.

- Two flows competing on the same shaped bottleneck (100 Mbps, 40 ms,
  1000 pkt).
- Three pairings:

| Pair             | Share split | Jain |
|------------------|-------------|------|
| BBR vs CUBIC     | 0.58 / 0.42 | 0.973 |
| BBR vs BBR       | 0.53 / 0.47 | 0.995 |
| CUBIC vs CUBIC   | 0.64 / 0.36 | 0.932 |

- BBR vs BBR converges almost perfectly. BBR vs CUBIC has BBR taking
  a modest extra share, milder than the 2016 paper. Single-trial,
  3x BDP buffer.
- BBRv2 was created specifically to address BBR-vs-CUBIC fairness in
  deeper buffers.

Say: "Intra-protocol fairness is excellent. Cross-protocol, BBR is
slightly greedier, a known issue addressed in v2."

## Slide 8: paper comparison (60 s)

Reproduced cleanly:

- BBR matches link capacity regardless of buffer size.
- CUBIC and RENO under-utilize on shallow buffers + high RTT.
- BBR keeps RTT at the propagation floor; loss-based CCs inflate RTT
  2.5-3x.
- BBR has zero retransmits in steady state.

Milder than the paper:

- BBR vs CUBIC unfairness was small (~58/42), not the dramatic split
  the paper showed for deep buffers. Likely cause: buffer size and
  number of trials. A single host with namespaces also has lower
  jitter than the Google WAN traces.

Not done:

- Lossy-link experiments (random loss via netem `loss`).
- Multi-flow scaling beyond 2 flows.
- BBRv2.

Say: "Qualitatively the paper reproduces. The fairness gap was
smaller than expected. More trials and deeper buffers would push on
that."

## Slide 9: conclusions (45 s)

- Loss-based CC is a latency tax. BBR removes most of it.
- BBR's win is biggest on high-RTT, shallow-buffer paths and on
  deep-buffer paths where bufferbloat dominates.
- Tradeoff: BBR is mildly unfair to loss-based flows in deep buffers,
  which motivated BBRv2.
- A controlled netns + `tc` testbed is enough to reproduce the paper's
  qualitative claims on a laptop.

Say: "If you take one thing away: throughput isn't the whole story.
Latency under load is what BBR fixes."

## Backup slides for Q&A

Have ready, do not show unless asked:

- The four BBR phases (STARTUP/DRAIN/PROBE_BW/PROBE_RTT) with a brief
  diagram.
- Kleinrock 1979 optimal operating point; why pacing at BtlBw with
  cwnd ~ BDP is provably optimal.
- Why netns instead of VMs (same kernel, no NIC virtualization,
  instant teardown).
- Where in the kernel BBR lives (`net/ipv4/tcp_bbr.c`), and how
  `iperf3 -C` interacts with `tcp_allowed_congestion_control`.
- Jain's fairness index formula.

## Timing cheat sheet

| Slide | Topic                | Target | Cumulative |
|-------|----------------------|--------|------------|
| 1     | Title                | 0:10   | 0:10       |
| 2     | Problem              | 1:00   | 1:10       |
| 3     | BBR's idea           | 1:15   | 2:25       |
| 4     | Testbed              | 1:00   | 3:25       |
| 5     | Exp 1, throughput    | 1:15   | 4:40       |
| 6     | Exp 2, bufferbloat   | 1:15   | 5:55       |
| 7     | Exp 3, fairness      | 1:15   | 7:10       |
| 8     | Paper comparison     | 1:00   | 8:10       |
| 9     | Conclusions          | 0:45   | 8:55       |
| -     | Buffer / breath      | 1:00   | 9:55       |

Leaves 5 s slack before the hard stop. If running long, cut from Slide
8 first; Slides 5-7 are the "what you did" content the assignment
asks for.

## Solo delivery notes

- Rehearse end-to-end at least twice with a stopwatch. The first run
  will overshoot; trim filler from the spots that ran long.
- Mark the 5:00 midpoint in your notes (mid-Slide 6). If past Slide 6
  at 5:30, skip the zero-retransmits line and move on.
- Don't read the slide. Each slide has one "say:" line, that's the
  spoken thesis. Everything else is reference for the audience.

## Anticipated Q&A

- "Why didn't you test BBRv2?" BBRv2 isn't mainline in the kernel we
  used; v1 is the default. v2 was Google's response to the fairness
  issues from Slide 7.
- "Why netns instead of two machines?" Same kernel = identical BBR
  implementation, no NIC virtualization, deterministic. Tradeoff: no
  real wireless effects.
- "Did you account for TSO/GSO?" Yes, disabled on the veths so
  netem's packet-count queue limit reflects real packets.
- "How did you measure RTT?" From iperf3's per-interval `TCP_INFO` on
  the data socket. Not `ss`, which we found grabs the control socket.
- "Single trial, is that enough?" For Exp 1 and 2 the effect sizes
  are large; for Exp 3 single trials are a real limitation we'd repeat
  with more runs.
- "Why is BBR's throughput slightly lower than CUBIC's in Exp 2?" BBR
  deliberately keeps the queue empty, so it occasionally underestimates
  BtlBw during PROBE_RTT. CUBIC fills the buffer, sustaining a slightly
  higher peak rate at the cost of latency.
