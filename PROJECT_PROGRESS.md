# AXI4 project progress

## Preserved state

- Repository: `complete-axi-bus`; branch: `feat/concurrent-axi4`.
- Original requirements: [docs/project_requirements.md](docs/project_requirements.md).
- Baseline: `2ec5059cf00b51b40ee441fab273f5a2d1d8f462`, existing `v1.0.0` tag.
- Original working tree was clean; no tag was overwritten and no remote was pushed.
- Audit/baseline commit: `1298295`; benchmark commit: `b2e5968`;
  verified concurrency milestone: `f917937`.

## Last verified milestone

`python3 tools/validate_upgrade.py` completed successfully before beginning the
continuation's optional target pipeline. Exact commands, exit codes and source
hashes: `synthesis/reports/validation.json`.

Implemented per-target read/write arbitration using the retained baseline arbiter,
per-manager accepted-address queues (default depth 4), strict head issue and
response ordering, local DECERR service, and address map extent checks. IDs may
overlap across managers; ownership prevents ambiguity. At most one request per
manager per direction executes at a time, with up to depth accepted requests.

Verified: 418 integration checks, 1,618 burst checks, parameter carry regression,
525 default outstanding checks; depths 1/3/5; asymmetric 1x1/3x2/2x3 configurations;
40-bit address operation; seeded randomized stress; queue netlist simulations at
depths 3/4; 30 scenarios each for baseline, concurrent depth 1 and queued depth 4.
At 8x8/256, 16-beat independent full-duplex traffic takes 4,608 baseline cycles,
608 depth-1 cycles and 577 depth-4 cycles. 100 MHz is assumed, not achieved by STA.

Corrected original synthesis evidence: `begin:coarse` stopped before process
lowering. Current RAM/queue flows use `begin:fine`, structural/latch/process checks,
and JSON storage sanity checks. A stock-Yosys struct-array interpretation issue
was resolved with explicit packed vectors and verified using synthesized queues.

## Highest-priority unfinished work

1. Add optional target register slices with directed/random/reset verification and
   measured latency/throughput/storage costs; do not claim Fmax improvement.
2. Complete final engineering audit and fix remaining practical technical debt.
3. Update architecture/verification/README and before/after comparison.
4. Analyze 100 Gb/s with explicit aggregate versus single-direction assumptions.
5. Create `ENGINEERING_MASTERY.md`, detailed walkthroughs/timing diagrams and >=50
   implementation-grounded interview questions with answers.
6. Run final complete validation, commit verified milestones, update this file.

## Environment limitations

Verilator 5.044 and Yosys 0.57 are available. No `read_slang` command/plugin,
OpenSTA executable or suitable technology library is installed. Full-fabric
synthesis and technology-specific area/timing/P&R remain unverified. A flat
external-port wrapper and optional slang flow exist for later execution; RAM and
mechanically flattened queue synthesis are actual executed evidence. No formal
liveness proof, independent commercial VIP, or coverage closure is claimed.

## Resume commands

```sh
cd /Users/christophersepka/Desktop/AXI_proj/complete-axi-bus
git status --short
cat PROJECT_PROGRESS.md
python3 tools/validate_upgrade.py
```

Read current files and recent commits before resuming; preserve any uncommitted
work. Simulation logs and benchmark metadata distinguish runs from plans.
