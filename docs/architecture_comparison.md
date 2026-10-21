# Architecture and performance comparison

## Reproduction and conditions

Baseline RTL: `2ec5059cf00b51b40ee441fab273f5a2d1d8f462` (`v1.0.0`).
The same direct-AXI benchmark/checker drives immutable baseline RTL and the current
fabric. Unless a row says otherwise: 32 INCR transactions per manager per direction,
16 beats, all strobes, independent targets, ready sinks, continuous arrivals,
seed 7, finite-run cycle interval including startup/drain, assumed 100 MHz.
Memory is explicitly preloaded; read and write regions are disjoint.

```sh
python3 tools/validate_upgrade.py
```

Raw inputs, source hashes, logs, CSV, per-port metrics and summaries:
[baseline](../benchmarks/results/baseline/summary.md),
[concurrent depth 1](../benchmarks/results/concurrent-d1/summary.md),
[queued depth 4](../benchmarks/results/queued-d4/summary.md),
[pipelined depth 4](../benchmarks/results/pipelined-d4/summary.md).

## Measured independent-target throughput

All rates are simulated cycle throughput at the stated assumed clock; none is
technology-timing verified. Aggregate includes simultaneous reads and writes.

| Configuration | Baseline cycles / GB/s | Concurrent d1 cycles / GB/s | Queued d4 cycles / GB/s | Pipelined d4 cycles / GB/s | d4 speedup |
|---|---:|---:|---:|---:|---:|
| 2x2x64 | 1152 / 1.422 | 608 / 2.695 | 577 / 2.840 | 641 / 2.556 | 2.00x |
| 4x4x128 | 2304 / 2.844 | 608 / 10.779 | 577 / 11.358 | 641 / 10.224 | 3.99x |
| 8x8x256 | 4608 / 5.689 | 608 / 43.116 | 577 / 45.432 | 641 / 40.896 | 7.99x |

## Bounded concurrency and latency (8x8/256)

| Metric | Baseline | Concurrent d1 | Queued d4 | Pipelined d4 |
|---|---:|---:|---:|---:|
| Peak W beats/cycle | 1 | 8 | 8 | 8 |
| Peak R beats/cycle | 1 | 8 | 8 | 8 |
| Peak accepted writes | 1 | 8 | 32 | 32 |
| Peak accepted reads | 1 | 8 | 32 | 32 |
| Average accepted transaction latency, cycles | 16.50 | 17.50 | 65.66 | 73.28 |
| Worst accepted latency, cycles | 17 | 18 | 71 | 79 |
| Average offered transaction latency, cycles | 154.07 | 35.45 | 81.03 | 90.41 |
| Worst offered latency, cycles | 161 | 37 | 89 | 99 |
| Average outstanding writes | 0.94 | 7.58 | 29.98 | 30.03 |
| Average outstanding reads | 0.89 | 7.16 | 28.28 | 28.51 |
| Write outstanding-slot utilization | 0.944 | 0.947 | 0.937 | 0.938 |
| Read outstanding-slot utilization | 0.889 | 0.895 | 0.884 | 0.891 |

Accepted occupancy includes waiting entries. Executing heads remain at most one
per manager per direction and one per target per direction. Increased accepted
latency is expected: the fabric admits requests sooner and queues them internally.
Offered latency and completion cycles help interpret that tradeoff.

## Unfavorable and scaling cases (8x8/256, aggregate GB/s)

| Scenario | Baseline | Concurrent d1 | Queued d4 | Pipelined d4 |
|---|---:|---:|---:|---:|
| single-mixed | 5.689 | 5.389 | 5.679 | 5.112 |
| hotspot | 5.689 | 5.688 | 5.688 | 5.119 |
| backpressure | 2.833 | 21.365 | 21.845 | 20.855 |
| sparse | 5.688 | 42.145 | 44.431 | 40.083 |
| burst-1 | 2.133 | 12.800 | 16.891 | 10.176 |
| burst-64 | 6.206 | 48.907 | 49.625 | 48.166 |
| burst-max | 6.302 | 50.027 | 50.400 | 49.637 |

The hotspot remains limited by one target. Independent targets scale; buffer depth
cannot multiply a single target's data rate. Short bursts expose per-transaction
bubbles. At 256 bits, the maximum legal tested INCR burst is 128 beats (4096 bytes),
not 256: the 4-KiB rule still applies. Backpressure results include reproducible
45% response READY probability. See CSV for per-direction utilization, admission
waits, dispatch arbitration waits, data stalls and per-manager/target throughput.

## Storage, logic and timing

The baseline synthesis command produced elaboration-only statistics; it did not
lower processes. Corrected generic synthesis gives the unchanged 32-bit RAM 275
coarse cells, 162 explicit FF bits and 32,768 memory bits. This RAM evidence is
common to both architectures and is not a full-fabric area comparison.

A manager's depth-4 address queues retain 416 payload bits at ADDR=32/ID=4, plus
26 control FF bits. A target's enabled 256-bit five-channel slice retains 1324
payload bits plus 20 control FF bits. Actual coarse operator counts and depths
are in [synthesis evidence](../synthesis/README.md). Small memories may map to FFs.

Full-fabric generic logic/register area remains unmeasured because the installed
frontend cannot synthesize its interface arrays. Mapped area, critical paths,
Fmax and place-and-route remain unavailable. No technology-weighted cost or timing
claim is inferred from simulation or isolated module counts.

## Pipeline decision and scalability

Input address queuing breaks source admission READY dependence on target response
paths, while allowing a queued successor to issue without a refill cycle.
Per-target optional channel stages remove combinational dependence across that
boundary. They reduce throughput at the same clock because address/response
latency and full-buffer recovery add cycles; they remain disabled by default.
Their retention is justified as a selectable registered boundary, not as a proven
Fmax optimization. Select them using actual physical critical-path evidence.

For AI accelerator scratchpads or networking memory banks, the measured gain
requires distributed traffic and enough independent managers. Hot banks and a
manager's blocked head still limit service. More aggressive issue would need
per-ID ordering, W issue queues and response arbitration/storage; the current
bounded policy avoids those hazards. The architecture's crossbar routing grows
with NM*NS, so these simulation results do not imply arbitrary physical scaling.

## Verification comparison

The original 418 integration and 1,346 burst comparisons remain; burst cases now
produce 1,618 comparisons. New default directed queues add 525 comparisons; the
FIFO test adds 5,455 payload comparisons. Separate parameter/page checks,
queue-depth/pipeline matrices, netlist simulation and seeded benchmark scoreboards
expand evidence without claiming coverage closure or full AXI compliance.
