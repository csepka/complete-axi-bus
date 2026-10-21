# Direct-AXI performance measurements

Run from the repository root (Python standard library, Verilator, C++ compiler):

```sh
python3 benchmarks/benchmark_runner.py --revision 2ec5059cf00b51b40ee441fab273f5a2d1d8f462 --label baseline --config 2x2x64 --config 4x4x128 --config 8x8x256
python3 benchmarks/benchmark_runner.py --label current --config 2x2x64 --config 4x4x128 --config 8x8x256
```

The baseline RTL is materialized from Git into ignored `build/` without changing
checkout state. The same current testbench/checker drives both implementations.
Every simulation checks response codes, IDs, RLAST, read data and final written
memory contents. SVA monitors every external manager and subordinate channel.
Fixture memory is explicitly preloaded outside measurement; reads and writes use
disjoint regions, avoiding undefined application-level read/write races.

Default scenarios include single-manager read/write/both, independent targets,
a hotspot, response backpressure (45% READY probability), sparse arrivals (25%),
and 1/16/64/maximum legal INCR burst lengths. Maximum is min(256, 4096/beat_bytes).
Each active manager issues 32 transactions **per enabled direction**. IDs repeat
0/1/2 and overlap across managers. All writes assert every strobe; therefore useful
and transferred bus bytes coincide. The default is full-duplex saturated traffic. Modes 0/1/2 select reads/writes/both.
For a custom case, `--read-percent 75` divides a total quota of twice
`--transactions` into 75% reads and 25% writes; streams are independently paced.

Custom example:

```sh
python3 benchmarks/benchmark_runner.py --label custom --config 3x2x64 --addr-width 40 --depth 3 --burst 8 --mode 2 --distribution 2 --ready 60 --arrival 40 --seed 42
```

The bench supports 1–8 managers, independent subordinate counts, power-of-two
widths, address widths sufficient for the map, legal INCR lengths and deterministic
LCG seeds. Distribution 0 fixes manager m to m%NS, 1 targets zero, 2 rotates by
transaction and seed. Arrival percentage controls a Bernoulli opportunity to
present a new address; once presented, VALID/payload remain stable. The write
source streams accepted requests in order. READY pacing affects B/R; the retained
burst regression separately exercises subordinate AW/W/AR stalls.

## Metric definitions

- Cycles: first possible request through last response, including startup/drain;
  this finite-run average approaches sustained throughput for longer runs.
- Data beats: successful WVALID&WREADY and RVALID&RREADY, never VALID alone.
- GB/s = accepted bytes / cycles * assumed MHz / 1000; Gb/s = GB/s * 8.
  Default 100 MHz is an assumption, **not timing-verified performance**.
- Physical full-duplex peak: two directions * min(NM,NS) * bytes/beat * clock;
  baseline has one path per direction. Per-direction utilization uses that bound.
- Accepted transaction latency: AW handshake to B handshake, AR to final R.
  Offered latency also includes waiting from first VALID assertion. Queuing changes
  admission time, so compare both, not accepted latency alone.
- AW/AR waits: source-visible VALID&&!READY cycles (includes admission/arbitration);
  these are not a pure internal arbiter service-time measurement. Separate
  `arb_aw_wait` / `arb_ar_wait` count VALID&&!READY at dispatch into target arbitration.
- W stalls and R stalls: corresponding VALID&&!READY cycles summed over managers.
- Average outstanding occupancy: post-handshake accepted-minus-completed work
  accumulated over the measured cycles; utilization divides by active-manager
  capacity (or one global baseline slot).
- Peak outstanding: accepted addresses minus completed responses; queued work is
  included and must not be confused with concurrently executing target requests.
- `ports.csv`: per-manager/per-target beats and aggregate bandwidth. CSV includes
  average/worst latency, counts, stalls, peak concurrent beats and outstanding work.

Raw build/run logs, metadata, CSV and Markdown live under `results/<label>/`;
portable SVG charts are under `plots/`. Functional check counts are not coverage.

## Optional registered target channels

Use `--pipeline 1` with current RTL. It enables two-entry FIFOs on all five target
channels, adding latency and a full-buffer recovery bubble while cutting paths
across that boundary. `pipelined-d4` results use this setting; baseline does not.
Compare the complete cycle and storage costs before deciding on a timing benefit.
