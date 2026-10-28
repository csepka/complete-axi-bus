# Can this interconnect sustain 100 Gb/s?

**Simulation supports more than 100 Gb/s under specified configurations and an
assumed clock. Hardware operation at that rate has not been demonstrated.**
Full-fabric reference STA/P&R is now being measured separately; remaining
antenna/LVS and endpoint-integration gaps prevent a hardware-ready claim. Decimal 100 Gb/s is 12.5 GB/s.

## Main measured cases at an assumed 100 MHz

16-beat INCR bursts, 32 transactions per active manager in each direction, independent
targets, continuous arrivals, no response stalls, seed 7. Read/write regions are
disjoint; full strobes make useful bytes equal transferred data bytes. The interval
includes startup and drain.

| Configuration | Pipeline | Aggregate Gb/s | Read Gb/s | Write Gb/s | Aggregate >=100? | Each direction >=100? |
|---|---:|---:|---:|---:|---|---|
| 2x2x64 | 0 | 22.716 | 11.358 | 11.358 | no | no |
| 4x4x128 | 0 | 90.864 | 45.432 | 45.432 | no | no |
| 8x8x256 | 0 | 363.458 | 181.729 | 181.729 | yes | yes |
| 2x2x64 | 1 | 20.448 | 10.224 | 10.224 | no | no |
| 4x4x128 | 1 | 81.792 | 40.896 | 40.896 | no | no |
| 8x8x256 | 1 | 327.169 | 163.584 | 163.584 | yes | yes |

These are fabric totals across managers/targets. A single 256-bit direction has
only a 25.6 Gb/s theoretical ceiling at 100 MHz; an 8-target total must not be
advertised as one port's bandwidth. Hotspot and single-manager cases do not receive
the independent-target multiplier.

## Required-clock calculation, not achieved timing

For a fixed measured handshake-per-cycle workload:

`required_MHz = assumed_MHz * 100 / measured_Gb_per_s`.

| 8x8/256 case | Aggregate rate at 100 MHz (Gb/s) | Required MHz for 100 Gb/s aggregate | Required MHz for 100 Gb/s in each direction |
|---|---:|---:|---:|
| baseline, independent | 45.511 | 219.727 | 439.453 |
| queued-d4, independent | 363.458 | 27.514 | 55.027 |
| pipelined-d4, independent | 327.169 | 30.565 | 61.131 |
| queued-d4, hotspot | 45.501 | 219.774 | 439.548 |
| queued-d4, backpressure | 174.763 | 57.220 | 114.441 |

The frequency requirements extrapolate the same cycle-level traffic conditions;
they are not Fmax estimates. Different endpoint latency, traffic patterns, width,
burst size or clock-domain structure changes the result. The backpressure row uses
45% response-ready probability, not a worst-case arbitrary-stall guarantee.

Longer bursts amortize overhead: the 4x4/128 maximum-length independent case exceeds
100 Gb/s aggregate at the assumed 100 MHz, while its 16-beat case does not. Its
per-direction rate remains below 100 Gb/s. Reproduce exact values from the CSV;
avoid treating aggregate and single-direction thresholds as interchangeable.

## What remains to demonstrate hardware 100 Gb/s

Run full-fabric synthesis using an interface-capable frontend, map to a specified
library/PVT corner, constrain I/O/clock/load/reset assumptions, and close setup/hold
after place-and-route with extraction. Verify the selected memory macro and
endpoint bandwidth/latency contracts. Combine the achieved clock with the observed
useful bytes/cycle under the intended traffic, including stalls and arbitration.

The repository now supplies full-fabric reference synthesis and physical evidence
in addition to the simulation results. The 2x2/64 pipelined implementation meets
100 MHz extracted timing, but its measured 20.448 Gb/s aggregate traffic does not
meet 100 Gb/s. Larger configurations require their own timing evidence; do not
transfer the small-block result to the 8x8 design. See
[reference results](../synthesis/physical/README.md).

The initial full 8x8/256 pipelined physical implementation is now archived with
325,000 um² standard-cell area, +6.13827 ns setup slack, **-0.030555 ns hold slack**,
2,660 hold violations and 80 capacitance violations at the same 100-MHz constraint.
Its routed-netlist independent functional test passes, but its timing acceptance
fails. Functional correctness and setup margin cannot compensate for failing
hold/electrical checks. A separate repair-margin trial preserves this failed
layout for comparison; no improved result is claimed before final extraction.
