# Speaker notes

10-minute presentation, 12 slides. Targets are spoken-aloud time (~115 wpm).
Don't read the slide. The points below are what to actually say —
the slide is the visual support behind you.

If you're running long, the easiest cuts are: shorten Slide 6 (Exp 1
figure), shorten Slide 8 (Exp 2 figure), trim the BBRv2 sentence on
Slide 9. Don't cut Slide 7 — that's the headline.

---

## Slide 1 — Title (10 s)

"Hi, I'm Mihir. This is joint work with Chaitanya and Piyoosha. We
reproduced Google's BBR congestion control algorithm on a controlled
Linux testbed and compared it against CUBIC and RENO. The headline:
BBR gives up a small amount of throughput in exchange for dramatically
lower latency under load."

Then click to next slide.

---

## Slide 2 — The Problem (60 s)

"For about thirty years, TCP congestion control has used one signal:
packet loss. Algorithms like RENO and CUBIC speed up until packets
drop, then back off. That logic worked fine in the 1990s when router
buffers were small.

The problem is that modern routers ship with megabytes of buffering.
A loss-based sender will fill that buffer all the way to the top
before it gets a loss signal. Throughput looks great, but every
packet is now sitting in a queue for a hundred-plus extra milliseconds
on the way through. This is called *bufferbloat* — high throughput
and high latency at the same time.

So the question the BBR authors asked was: can we do congestion
control without using loss as the signal at all?"

---

## Slide 3 — BBR's Idea (75 s)

"BBR's answer is: model the path. Don't react to symptoms — measure
the underlying physics.

BBR estimates two things continuously. *BtlBw*, the bottleneck
bandwidth, which is the highest delivery rate it has seen. And
*RTprop*, the propagation RTT, which is the lowest round-trip time
it has seen with no queuing. Multiply those two and you get the
bandwidth-delay product, or BDP. That's the optimal amount of data
to have in flight on the path.

So BBR sets two controls. It paces packets out at BtlBw to keep the
link full, and it caps in-flight data at roughly BDP so the queue
stays empty. It cycles through four states — STARTUP, DRAIN,
PROBE_BW, and PROBE_RTT — to keep both estimates fresh as the path
changes.

This is in the Linux kernel since 4.9, deployed across Google's
WAN, YouTube, and QUIC."

---

## Slide 4 — Testbed (60 s)

"Here's what we built. Two Linux network namespaces on one host —
ns1 is the iperf3 server, ns2 is the client — connected by a veth
pair. We use tc on each veth to emulate a bottleneck: tbf controls
the rate, netem adds one-way delay and a packet-count queue limit.

Three things worth knowing. First, we apply the shaping symmetrically
on both veths so the round-trip delay is twice the configured
one-way delay. Second, we disable TSO, GSO, and GRO on the veths so
the kernel doesn't merge packets — that way netem's queue limit
counts real packets. Third, we use iperf3's `-C` flag so we can pick
the congestion control algorithm per flow.

The big advantage of namespaces over VMs is that everything runs in
the same kernel — so the BBR module under test is exactly the
production Linux implementation, no virtualization quirks."

---

## Slide 5 — Exp 1 table (45 s)

"Experiment one is a sweep. Three CCs, three bandwidths, three RTTs,
three buffer sizes — eighty-one runs, thirty seconds each.

Here are the numbers at the 100 Mbps bottleneck. At 10 ms RTT, all
three algorithms hit roughly 95% of capacity — congestion control
choice doesn't matter on short links.

But look at the middle two rows: 100-packet buffer, 40 and 160 ms
RTT. CUBIC and RENO collapse to 13–26% of capacity. They need a deep
buffer to recover from each loss event without crashing their
window. BBR holds at 49 and 24% — also degraded, but still leading.

On the deep-buffer high-RTT case at the bottom, BBR gets 89%, CUBIC
gets 79%, RENO never recovers — only 48%."

Click to figure.

---

## Slide 6 — Exp 1 figure (30 s)

"This plot shows the same data across the whole grid. Rows are RTT,
columns are bandwidth. X-axis is buffer size on a log scale, y-axis
is throughput. The blue line is BBR, red is CUBIC, green is RENO.
The takeaway: as you go down and right — higher RTT, deeper pipe —
BBR's lead gets bigger. The bottom-right cell is the worst case for
loss-based CC."

---

## Slide 7 — Exp 2 table (60 s)

"Experiment two is the headline. Same conditions for all three
algorithms — 100 Mbps, 40 ms base RTT, 1000-packet buffer, which is
about three times the BDP. We let one flow run for sixty seconds and
measured RTT.

Look at throughput first: 92.9, 95.3, 95.3 Mbps. All three are at
the link cap. So if you only looked at throughput you'd say they're
the same.

Now look at the RTT column. BBR is at 43 ms — 3 ms above the 40 ms
propagation floor. CUBIC is at 120 ms. RENO is at 103 ms. CUBIC and
RENO inflate latency by roughly three times.

And the retransmits column on the right: BBR has zero. CUBIC has 92.
RENO has 860 — RENO halves its window on every loss, so it's
constantly cycling.

Same throughput, three times the latency. That's bufferbloat in one
table."

Click to figure.

---

## Slide 8 — Exp 2 figure (30 s)

"This is the time-series. Top panel is RTT, bottom is throughput.
Watch the red line — that's CUBIC. You can see the textbook AIMD
sawtooth: linear ramp from 40 up to 140 ms as the buffer fills, then
a sharp drop when a packet finally gets dropped, then ramp again.
RENO does the same thing more aggressively in green.

The blue line is BBR. It sits at the propagation floor with small
spikes — those spikes are PROBE_BW, where BBR briefly speeds up to
re-measure the bottleneck bandwidth, then drains back down."

---

## Slide 9 — Exp 3 table (60 s)

"Experiment three is fairness. Two flows competing on the same
bottleneck. Same link as before. We tried three pairings.

BBR versus BBR — the intra-protocol baseline — splits 52/48 with a
Jain index of 0.999. Almost perfect.

CUBIC versus CUBIC — also fair, 0.997.

The interesting one is BBR versus CUBIC: 55/45, Jain 0.990. BBR
takes slightly more, but it's much fairer than what the original
2016 paper reported. The paper showed BBR claiming a much bigger
share against CUBIC on deep buffers. Our result is mild.

The likely reason is that the Linux BBR implementation has had
several fairness patches since 2016. We're testing the current
kernel, not the original BBRv1."

Click to figure.

---

## Slide 10 — Exp 3 figure (30 s)

"Here are the time-series. Top panel is BBR vs CUBIC — they trade
positions for the first ten seconds, then settle into a slightly
asymmetric split for the rest of the run. Middle is BBR vs BBR —
both flows oscillate around the 50 Mbps fair share line. Bottom is
CUBIC vs CUBIC — same picture, two flows hovering at 50."

---

## Slide 11 — Comparison (60 s)

"How does this compare to the paper. On the left side: we cleanly
reproduced the main claims. BBR beats loss-based CC across the
board, shallow buffers hurt CUBIC and RENO more, BBR keeps RTT at
the propagation floor, and BBR has zero steady-state retransmits.

On the right: two things were milder than the paper. First, the
fairness gap I just mentioned. Second, our buffer was three times
BDP — the paper's deep-buffer experiments used much larger buffers
where the unfairness is more pronounced.

And to be transparent: we didn't test lossy links, we only ran two
flows at a time, and we didn't evaluate BBRv2."

---

## Slide 12 — Conclusions (45 s)

"Four takeaways.

One: loss-based congestion control is a latency tax. BBR removes
most of it.

Two: BBR's win is biggest on high-RTT shallow-buffer paths and on
deep-buffer paths where bufferbloat dominates.

Three: in modern Linux, BBR vs CUBIC fairness is much better than
the 2016 paper suggested — kernel patches matter.

Four: a controlled netns plus tc testbed is enough to reproduce the
paper's qualitative claims on a laptop. You don't need a cloud
account or a real WAN.

The one-line takeaway: throughput isn't the whole story. Latency
under load is what BBR actually fixes.

Thank you — happy to take questions."

---

## Pacing checkpoints

| Time | Should be on |
|---|---|
| 1:00 | Slide 3 (BBR's idea) |
| 3:00 | Slide 5 (Exp 1 table) |
| 5:00 | Slide 7 (Exp 2 table) — middle of deck |
| 7:30 | Slide 10 (Exp 3 figure) |
| 9:00 | Slide 12 (conclusions) |
| 9:45 | Wrapping the conclusion |

If you're more than 30 seconds behind these checkpoints, skip the
figure-only slides (6, 8, 10) faster — you can summarize them in
one sentence each.

## Things to never say

- "Um, basically..." — kills authority. Pause instead.
- "I think" or "I guess" when stating data. The numbers are measured.
  Say "we measured" or "the data shows."
- Apologizing for limitations. State them flatly. "We did not test
  lossy links" is fine. "Unfortunately we didn't get to..." is weak.
- Don't read out Jain index numbers to three decimals out loud.
  "Around 0.99" is enough; the slide has the precision.
