# Technical reference and Q&A prep

A deep-dive into what we built, why each design choice was made, and
the questions most likely to come up in Q&A.

## 1. What we built, end to end

### 1.1 Testbed

A single Linux host (CachyOS, kernel 6.19) with two network namespaces
connected by a `veth` pair.

```
ns1 (server)                       ns2 (client)
10.0.0.1/24  <---- veth pair ----> 10.0.0.2/24
veth-ns1                           veth-ns2
   ^                                  ^
   |                                  |
[ tbf rate + netem delay ]    [ tbf rate + netem delay ]
```

Each namespace has its own network stack — its own routing table,
its own TCP control block, its own socket table. But both run inside
the same kernel, so the BBR module under test is exactly the
production Linux implementation.

The bottleneck is emulated by two `tc` qdiscs chained on each veth:

- `tbf` (token bucket filter) at the root: enforces the rate limit.
- `netem` as a child: adds one-way delay and a packet-count queue.

Shaping is applied symmetrically on both veths so RTT = 2 × one-way
delay.

### 1.2 Why these choices

| Decision | Why |
|---|---|
| Network namespaces over VMs | Same kernel = identical BBR behavior; no virtual NIC interference; instant teardown |
| veth pair instead of loopback | Loopback bypasses qdiscs; veth gives us a real shapeable interface |
| `tbf` then `netem` (this order) | tbf must be root, netem chained as child. Reversed, delay applies before rate-limit and RTT readings are wrong |
| Shape both veths symmetrically | tc only shapes egress. Shaping one direction means ACKs come back unshaped and TCP sees half the configured RTT |
| TSO/GSO/GRO disabled on veths | These offloads coalesce packets into giant segments. With them on, netem's packet-count `limit` would overcount; queue depth becomes meaningless |
| `iperf3 -C <cc>` | Sets congestion control per flow at the socket level. Lets two flows in the same namespace use different algorithms — needed for Exp 3 |
| `iperf3 -O 1` | Discards the first 1 second from steady-state stats so TCP slow-start doesn't pollute the average |
| `iperf3 -i 0.1` | Per-interval reporting at 100 ms resolution. The interval data includes TCP_INFO from the data socket — that's how we get accurate RTT samples |
| RTT from iperf3 (not `ss`) | iperf3 keeps both a control and a data socket on port 5201. An external `ss \| head -1` sampler can grab the idle control socket. iperf3's per-interval RTT comes off the data socket directly |

### 1.3 Why the testbed is reproducible

- One repo, three driver scripts (`exp1`, `exp2`, `exp3`), four
  analysis scripts. End-to-end takes about 50 minutes of wall time.
- All raw data is iperf3 JSON, deterministic to parse.
- Topology setup is two scripts: `topology.sh up` and `shape.sh`.
  Tear-down deletes both namespaces (which auto-removes the veth pair).
- Linux kernel 6.19, BBR v1 (default), no patched/custom kernel
  modules. Anyone running a recent Linux distro can rerun this.

## 2. The three experiments

### 2.1 Experiment 1: throughput sweep

**Goal:** verify BBR's claim that it is robust to buffer size on
high-RTT links, where loss-based CC degrades.

**Sweep:** 3 CCs × 3 bandwidths × 3 RTTs × 3 buffer sizes = 81 runs.
30 seconds per run, ~45 minutes wall time.

**Headline finding:** BBR consistently leads, but is *not* universally
robust. Under shallow buffers at high RTT, all three CCs collapse —
BBR drops to 24% on the 100-pkt / 160 ms RTT cell. The relative
ordering still holds (BBR > CUBIC > RENO) in every loss-prone cell.

**Why CUBIC and RENO collapse:** at 100 Mbps × 160 ms RTT the BDP is
~1333 packets. With a 100-packet buffer, every loss event drops the
window faster than it can recover. CUBIC's faster recovery curve
helps a bit (22% vs RENO's 11%), but neither can fill the pipe.

**Why BBR also drops at 100 pkt / 160 ms:** BBR's STARTUP phase
exponentially probes for BtlBw, and PROBE_BW periodically increases
pacing gain to re-measure. When the buffer is much smaller than BDP,
those probe increases cause loss before BBR has locked onto BtlBw.
The paper acknowledges this regime; our data shows it clearly.

### 2.2 Experiment 2: buffer bloat (the headline)

**Goal:** show that on a deep-buffered link, loss-based CC pays a
large latency cost for the same throughput.

**Conditions:** 100 Mbps, 40 ms base RTT, 1000-pkt buffer (~3× BDP).
Single flow per CC, 60 s.

**Results:**

| CC | Throughput | Mean RTT | Inflation | Retrans |
|---|---|---|---|---|
| BBR | 92.9 Mbps | 43.0 ms | 1.07× | 0 |
| CUBIC | 95.3 Mbps | 120.3 ms | 2.95× | 93 |
| RENO | 95.3 Mbps | 102.9 ms | 2.53× | 860 |

**Why BBR is 1.07× and not 1.00×:** PROBE_BW briefly increases
pacing above BtlBw (gain = 1.25) once per cycle. This temporarily
adds packets to the queue before the next phase drains them. The
small RTT spikes in the figure are these probes.

**Why RENO has 10× more retransmits than CUBIC:** RENO halves cwnd
on every loss event. CUBIC uses a cubic recovery curve that grows
faster post-loss and avoids losing again as quickly. Both fill the
buffer and lose; RENO just loses more often.

**Why throughput is essentially equal:** with 3× BDP of buffer
headroom, all three algorithms have plenty of room to keep the link
full. The buffer absorbs the difference. The cost shows up in
latency, not throughput.

### 2.3 Experiment 3: fairness

**Goal:** measure how BBR shares bandwidth with CUBIC, vs intra-
protocol baselines.

**Conditions:** 100 Mbps, 40 ms RTT, 1000-pkt buffer, two flows in
parallel for 60 s. First 5 s discarded as transient.

**Results:**

| Pair | Share | Jain |
|---|---|---|
| BBR vs CUBIC | 0.55 / 0.45 | 0.990 |
| BBR vs BBR | 0.52 / 0.48 | 0.999 |
| CUBIC vs CUBIC | 0.53 / 0.47 | 0.997 |

**Jain's fairness index:** J = (Σ x_i)² / (n · Σ x_i²). For two
flows, J = 1.0 means perfectly equal share; J = 0.5 means one flow
gets everything.

**Why our BBR vs CUBIC is much fairer than the paper's:** The
original 2016 paper reported BBR claiming disproportionate share
against CUBIC on deep-buffered links — sometimes 80/20 or worse.
Our 55/45 is much milder. Two contributing factors:

1. The Linux BBR implementation has accumulated fairness patches
   since 2016. The 2018 changes to PROBE_BW pacing-gain damping in
   particular reduce BBR's ability to bully other flows.
2. Our buffer is 3× BDP. The paper's pathological cases used much
   deeper buffers (10–20× BDP) where BBR's queue avoidance gives
   it a structural advantage over CUBIC's queue-filling behavior.

## 3. Definitions and concepts

**BtlBw (bottleneck bandwidth):** the highest delivery rate observed
on the path. Measured by the sender as bytes-acked / time-elapsed
over a sliding window. BBR keeps a 10-second windowed-max of these
samples so transient drops don't poison the estimate.

**RTprop (propagation RTT):** the lowest RTT observed on the path,
representing pure propagation delay with no queuing. BBR refreshes
this estimate by entering PROBE_RTT, which briefly drains in-flight
data so the queue empties and the true minimum can be re-measured.

**BDP (bandwidth-delay product):** BtlBw × RTprop. The maximum
amount of data that can be in flight on the path without queuing.
Kleinrock (1979) showed this is the optimal operating point for any
congestion-controlled flow.

**Buffer bloat:** the pathology where a sender fills a router's
buffer to the brim before getting a loss signal. Throughput stays
high but queuing delay inflates by buffer_size / BtlBw.

**Pacing rate vs CWND:** traditional TCP uses CWND (a byte cap on
in-flight data) regulated by the ACK clock. Bursty senders can
overshoot the bottleneck in a single RTT. BBR uses CWND (set to ~BDP)
*and* an explicit pacing rate (set to BtlBw) — the pacing controls
inter-packet timing, the CWND bounds total bytes out.

**Jain's fairness index:** a scalar measure of how equally a
resource is shared among n flows, ranging from 1/n (unfair) to 1.0
(perfectly fair). Standard metric for congestion control fairness.

## 4. Likely Q&A

### About the algorithm

**Q: Why didn't you test BBRv2?**
BBRv2 isn't mainline in the Linux kernel. v1 is the default. v2 was
Google's response to the fairness issues we discussed — it tightens
behavior in deep buffers and on lossy links. To test v2 we'd need to
build a custom kernel or use Google's research patch.

**Q: Why does BBR have any RTT inflation at all (1.07× instead of 1)?**
PROBE_BW. Once per ~8-RTT cycle, BBR increases its pacing gain to
1.25 to re-measure BtlBw. That briefly adds packets to the queue.
The next cycle phase drains it back out. The small spikes in our
RTT plot are exactly those probes.

**Q: How does BBR refresh RTprop without the queue draining?**
PROBE_RTT phase. Every 10 seconds, BBR drops in-flight data to 4
packets for 200 ms, lets the queue empty, and re-measures min RTT.
You can sometimes see this as a small throughput dip in long traces.

**Q: What are the four phases exactly?**
- STARTUP: exponentially ramp pacing rate (gain 2.89) until delivery
  stops growing — this is the BtlBw discovery phase.
- DRAIN: drain the queue created during STARTUP (gain 1/2.89).
- PROBE_BW: steady-state cycling through 8 phases of pacing gain
  [1.25, 0.75, 1, 1, 1, 1, 1, 1] to keep BtlBw fresh.
- PROBE_RTT: every 10s, briefly throttle to 4 pkts for 200ms to
  re-measure RTprop.

### About the testbed

**Q: Why network namespaces and not real machines or VMs?**
Same kernel = identical BBR implementation. No virtual NIC quirks.
Deterministic. Trade-off: no real wireless effects, no WAN jitter,
no parallel cross-traffic. Fine for reproducing the paper's
qualitative claims; not enough for novel claims about real-world
deployment.

**Q: How is `tc tbf` different from `tc htb` for rate limiting?**
tbf is simpler — single rate, single bucket. htb supports
hierarchical class trees. We don't need the hierarchy. tbf is also
the textbook choice for emulating a single bottleneck.

**Q: Why a 1000-packet buffer for Exp 2 and 3?**
BDP at 100 Mbps × 40 ms is ~333 packets. 1000 is roughly 3× BDP —
deep enough to make bufferbloat visible (CUBIC and RENO inflate RTT
by 2.5–3×), but not so deep that the experiments become outliers.

**Q: Did you control for system load?**
We disabled background processes during runs. CachyOS is a
relatively idle distribution. We saw consistent results across
multiple runs. In a serious paper we'd run N=3–5 trials and report
mean ± CI, but for a reproduction project the effect sizes are large
enough that single trials are defensible.

**Q: How did you measure RTT?**
From iperf3's per-interval `TCP_INFO` data on the data socket. We
initially tried external `ss -tin` polling, but iperf3 keeps both a
control socket and a data socket on the same port — `ss \| head -1`
was grabbing the idle control socket and showing flat 40 ms while
the actual data socket was at 120 ms. Switching to iperf3's built-in
interval reporting fixed it.

**Q: Why TSO/GSO/GRO off on the veths?**
TCP segmentation offload coalesces small packets into giant ones
before they hit the qdisc. netem counts packets, not bytes — so
with offloads on, its `limit` parameter would over-count actual
buffer occupancy. Disabling makes the queue depth match what netem
reports.

### About the results

**Q: BBR vs BBR is 0.999, BBR vs CUBIC is 0.990, CUBIC vs CUBIC is
0.997 — why is BBR vs CUBIC the *least* fair pair?**
Because BBR and CUBIC have different reactions to congestion. BBR
keeps the queue empty; CUBIC fills it. When they share a buffer,
BBR's pacing keeps throughput steady while CUBIC's sawtooth gives
up bandwidth during backoff. The asymmetry is small (0.990) but
real. The paper showed it was much larger on deeper buffers.

**Q: Single trial — can you trust the numbers?**
For Experiments 1 and 2, the effect sizes are huge (3× RTT
inflation, 2–10× throughput differences) so single trials are fine.
For Experiment 3, single trials are a real limitation. We saw this
ourselves: an earlier run gave CUBIC vs CUBIC a Jain index of 0.932,
which was a startup-timing artifact. Re-running gave 0.997. With
N=3–5 we'd report mean ± CI.

**Q: Your slide says BBR has zero retransmits but the table for
Exp 1 shows BBR retransmitting at 50 Mbps + 5 ms + 10 pkt buffer.
Explain.**
BBR is loss-tolerant, not loss-free. At very shallow buffers it
will still drop packets during STARTUP probes. The "zero retransmits"
claim is specifically for steady state on a properly-sized buffer
(Exp 2's 3× BDP condition).

**Q: The throughput numbers in your figure show BBR slightly below
CUBIC in Exp 2 (92.9 vs 95.3). Doesn't that contradict your story?**
No, that's the trade-off BBR makes deliberately. By keeping the
queue empty, BBR forgoes the small extra throughput that comes from
filling buffer headroom. CUBIC sustains a 2-3 Mbps higher rate but
pays 80 ms in extra latency. We're arguing that's a bad trade for
interactive workloads.

### About course material

**Q: How does this connect to BDP from class?**
Directly. Course material introduces BDP as the optimal in-flight
quantity. BBR is the first widely deployed CC that explicitly
targets BDP rather than overshooting and reacting. AIMD (CUBIC,
Reno) operates to the right of the BDP knee, in the buffer; BBR
operates *at* the knee.

**Q: How does BBR's BtlBw estimator relate to active bandwidth
measurement?**
The course covers packet-pair and packet-train probing. BBR's BtlBw
is a continuous, in-band realization of the same idea: every ACK is
a delivery-rate sample, and BBR maintains a windowed-max of recent
samples as its bandwidth estimate. No explicit probes needed —
production traffic does the measurement.

**Q: How is BBR's pacing rate different from a CWND?**
CWND is a byte cap on outstanding (unacknowledged) data. Pacing
rate is a target inter-packet send interval. CWND alone allows
bursts: if you have 10 packets of headroom and ACKs all arrive at
once, you can send all 10 back-to-back. Pacing prevents that —
each packet's send time is scheduled. BBR uses both in combination.

**Q: Where does Kleinrock's 1979 result come in?**
Kleinrock showed that for a bottleneck-limited flow, the optimal
operating point is exactly at BDP — any less and the link is
under-utilized, any more and you queue with no throughput gain.
BBR's design is essentially "build a closed-loop controller that
holds the operating point at Kleinrock's optimum."

### Open / honest answers

**Q: What didn't you do that you wish you had?**
- Lossy link experiments (`netem loss 1%`) — would show BBR's
  loss-tolerance more directly.
- N=3–5 trials with confidence intervals.
- BBRv2 evaluation.
- Multi-flow scaling (4, 8, 16 flows).
- A real wireless link with the same testbed methodology.

**Q: What was the hardest bug?**
The asymmetric shaping. Initial runs showed RTT = one-way delay
instead of 2× one-way delay. Took an hour to track down: tc only
shapes egress, so ACKs were returning on an unshaped path. Fix:
apply tbf+netem on both veths.

**Q: What surprised you?**
Two things. First, BBR isn't actually buffer-insensitive — it
collapses at very shallow buffers on high-RTT links, which is not
the headline you usually see. Second, BBR vs CUBIC fairness is much
better in modern Linux than the 2016 paper suggests. The kernel has
clearly evolved.

## 5. Reproducing the work

```bash
# Setup (one time)
./setup/setup.sh

# Bring up testbed
sudo ./setup/topology.sh up

# Run experiments
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

Outputs land in `figures/*.png` and `analysis/*.csv`. Raw iperf3
JSONs stay in `data/raw/exp{1,2,3}/`.
