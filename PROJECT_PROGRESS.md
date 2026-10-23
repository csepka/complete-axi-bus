# AXI4 project progress

## Hardware-reference continuation (2026-10-22, in progress)

Continue on `feat/concurrent-axi4`. The physical/independent-verification milestone was committed and pushed as
`8753a97` after the prior architecture commits. Further CI compatibility and large
physical-trial work is in progress. No functional RTL was changed during this continuation. Open reference technology
was explicitly selected by the user; Docker must remain running.

Verified evidence already obtained:

- `make ci` and all 17 stages of `tools/validate_upgrade.py` passed again. Original
  RTL/source hashes are recorded in `synthesis/reports/validation.json`.
- Pinned official ORFS image supplies native read_slang, Yosys, OpenROAD/OpenSTA,
  KLayout and Nangate45. Full 2x2/64 and 8x8/256 synthesis passed structural/SCC
  checks. Baseline is extracted from immutable `v1.0.0` revision, not rewritten.
- Upgraded 2x2/64 depth4/pipeline1 and original 2x2/64 layouts complete routing,
  extraction and STA at 100 MHz, 1.1 V/25 C typical. Their standard-cell areas are
  31,245.4 and 2,891.15 um². Setup slacks are +7.27049/+7.08936 ns; hold slacks
  +0.0278701/+0.0308236 ns. Both have zero router errors.
- KLayout finds **four antenna markers in each** small layout. ORFS's raw counter
  says 28 because it counts marker values rather than XML items. No other geometry
  markers occur. Antenna violations remain unresolved; router LEF lacks the needed
  antenna rules/gate-area collateral. No rules were invented or waived.
- LVS cannot run: the pinned platform names but omits `lvs/FreePDK45.lylvs`.
  Collector archives failures and returns nonzero for incomplete physical acceptance.
- Independent cocotbext-axi tests passed on four RTL configurations, 2x2 generic,
  mapped and routed four-state netlists, original routed baseline, and 8x8 generic
  netlist. The final nine-run matrix and provenance audit now pass. An accidentally
  removed `math` import caused a harness failure; it was restored and all nine
  cases were rerun successfully. No stale passing manifests were retained.
- FIFO WIDTH=8 arbitrary-input safety proof passes temporal induction. Scope is
  sampled reset/occupancy/order/stall stability, not full-fabric formal/liveness.
- Engineering guide expanded to **70 answered questions**. README, architecture,
  audit, verification and reference-flow documentation now distinguish functional
  evidence, extracted timing, antenna failures and unavailable LVS.

The initial 8x8/256 layout completed: setup slack +6.13827 ns, hold slack
-0.030555 ns with 2,660 hold violations and 80 capacitance violations; standard-cell
area 325,000 um². This is a failed timing result, not accepted closure. KLayout DRC
is running on that preserved layout. A separate `8x8x256-d4-p1-repair` trial uses
0.10 ns repair margin and 15% capacitance repair margin with the same SDC. Both
logs live under `build/physical/<label>/flow.log`. The repair trial starts with
fresh synthesis and preserves the original trial. Do not quote the simulated
327.169 Gb/s aggregate rate as physically timing-supported yet.

GitHub CI's newer Verilator 5.053 reports CMPCONST on the two queue-bound
assertions at depths whose counter maximum equals the queue depth (1, 3, ...).
A control-file waiver limited to those exact assertion lines now passes all
17 native validation stages and all nine independent tests; RTL and runtime
assertions are unchanged. CI run `39895799384` predates this fix. Do not claim
GitHub CI passes until a subsequent fixed commit completes there.

Next: finish and inspect large implementation, run final-netlist tests and DRC,
collect actual results/limits, complete evidence audit, update this file and the
100-Gb/s discussion, and commit verified work. The original environment limits
below are historical and superseded by the pinned reference flow.

## Preserved state

- Repository: `complete-axi-bus`; branch: `feat/concurrent-axi4`.
- Original requirements: [docs/project_requirements.md](docs/project_requirements.md).
- Baseline: `2ec5059cf00b51b40ee441fab273f5a2d1d8f462`, existing `v1.0.0` tag.
- Original working tree was clean; no tag was overwritten and no remote was pushed.
- Audit/baseline commit: `1298295`; benchmark commit: `b2e5968`;
  verified concurrency milestone: `f917937`; bounded queues and corrected
  synthesis evidence: `16b8698`; verified optional channel pipeline, additional
  burst/page-boundary tests and synthesis-adapter cleanup: `2be4402`.

## Last verified milestone

The optional target pipeline, expanded verification, performance comparison and
engineering mastery documentation are implemented. On 2026-10-21, all 17 stages of
`python3 tools/validate_upgrade.py` passed. All 29 recorded source hashes match the
verified implementation. Exact commands, exit codes and source hashes are recorded
in `synthesis/reports/validation.json`. Tests ran before the implementation commit,
so metadata records parent HEAD `16b8698` and a dirty worktree; the source hashes
identify the tested content now committed as `2be4402`. Check hashes before treating
this evidence as evidence for a newly edited source tree.

Implemented per-target read/write arbitration using the retained baseline arbiter,
per-manager accepted-address queues (default depth 4), strict head issue and
response ordering, local DECERR service, and address map extent checks. IDs may
overlap across managers; ownership prevents ambiguity. At most one request per
manager per direction executes at a time, with up to depth accepted requests.

`TARGET_PIPELINE=1` adds two-entry elastic stages on all five real-target channels;
the default remains bypass. READY derives from registered occupancy, and payload /
VALID derive from stored state. Arbitration ownership lasts through the buffered
response. This adds latency and storage; there is no measured Fmax improvement.

Verified: 418 integration checks, 1,618 burst checks, parameter carry and independent
4-KiB boundary regressions, 525 default outstanding checks and 5,455 FIFO payload
checks. Extended validation covers queue depths 1/3/5, asymmetric 1x1/3x2/2x3
configurations, 40-bit addresses, seeded randomized stress, pipelined burst and
outstanding tests, and queue/slice synthesized-netlist substitutions. Tests cover
overlapping IDs, ordered responses, resource exhaustion, simultaneous targets,
mixed queued errors, partial strobes, held grants, reset with pending work and
recovery. These are comparison counts, not coverage closure or conformance proof.

The performance matrix runs 30 scenarios each for the preserved baseline,
concurrent depth 1, queued depth 4 and pipelined depth 4. At 8x8/256, 16-beat
independent full-duplex traffic takes 4,608 baseline cycles, 608 depth-1 cycles,
577 depth-4 cycles and 641 pipelined cycles. The queued case yields 45.432 GB/s
aggregate, or 181.729 Gb/s in each direction, at an **assumed** 100 MHz. These are
fabric totals across eight targets. No achieved clock or hardware 100 Gb/s result
is claimed. Hotspot traffic remains limited by one target.

Corrected original synthesis evidence: `begin:coarse` stopped before process
lowering. Current RAM/queue flows use `begin:fine`, structural/latch/process checks,
and JSON storage sanity checks. A stock-Yosys struct-array interpretation issue
was resolved with explicit packed vectors and verified using synthesized queues.

## Completed engineering deliverables

- [Architecture](docs/architecture.md): queue acceptance, arbitration, routing,
  strict ordering, optional pipelining, parameter and reset contracts.
- [Verification](docs/verification.md): directed/random/reset tests, assertions,
  independent scoreboards, netlist substitution and unproven boundaries.
- [Engineering audit](docs/engineering_audit.md): baseline findings and final
  dispositions, including synthesis-stage and packed-array frontend fixes.
- [Measured comparison](docs/architecture_comparison.md): throughput, latency,
  utilization, occupancy, stalls, cost and unfavorable traffic cases.
- [100 Gb/s analysis](docs/performance_100g.md): aggregate versus directional rates,
  traffic assumptions and required-clock calculations distinct from achieved Fmax.
- [Engineering mastery](ENGINEERING_MASTERY.md): all major modules, datapath/state/
  control, walkthroughs and cycle tables, tradeoffs, debugging, and 60 answered
  ASIC/SoC interview questions grounded in this implementation.
- [Synthesis](synthesis/README.md): corrected RAM, queue and slice results,
  storage counts, generic netlist simulation, flat fabric wrapper and constraints.
- Reproducible source hashes, raw logs, CSV/Markdown reports, SVG charts and a
  regenerated VCD-derived address-arbitration illustration.

## Historical environment limitations (prior architecture milestone)

Verilator 5.044 and Yosys 0.57 are available. No `read_slang` command/plugin,
OpenSTA executable or suitable technology library is installed. Full-fabric
synthesis and technology-specific area/timing/P&R remain unverified. A flat
external-port wrapper and optional slang flow exist for later execution. The
wrapper passes lint at default parameters and 8x8/256 with pipelining. RAM and
mechanically flattened queue/slice synthesis are actual executed evidence. No
formal liveness proof, independent commercial VIP, four-state verification or
coverage closure is claimed.

The highest-priority external-tool-dependent milestone is full-fabric synthesis
with an interface-capable frontend, followed by mapping/STA using a specified
library/PVT and physical implementation. Do not replace these missing results with
isolated-module counts or an assumed simulation frequency. Future architectural
work could permit multiple executing heads per manager or different-ID bypass,
but needs new routing/ordering machinery and verification; it is not implemented.

## Resume commands

```sh
cd /Users/christophersepka/Desktop/AXI_proj/complete-axi-bus
git status --short
cat PROJECT_PROGRESS.md
python3 tools/validate_upgrade.py
```

Read current files and recent commits before resuming; preserve any uncommitted
work. Simulation logs and benchmark metadata distinguish runs from plans.
