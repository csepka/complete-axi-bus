# Codex Prompt: High-Performance AXI4 Interconnect — ASIC/SoC Engineering

## Mission and execution commitment

Act as a senior ASIC microarchitecture, RTL, and verification engineer. Work in my existing repository: https://github.com/csepka/complete-axi-bus.

**Take as long as it takes to get the job done properly. Do not rush, impose an artificial time limit, or stop merely because a phase is difficult.** Work autonomously through the plan, iterating on implementation, tests, debugging, performance analysis, and documentation until the deliverables are complete and validated. Do not claim success without evidence. If a fundamental blocker, missing tool, or environment limitation prevents completion, report exactly what is blocked, what was verified, and what remains; never fabricate results or silently weaken correctness requirements.

The goal is an exceptional, technically credible ASIC/SoC portfolio project relevant to MatX, Eridu AI, NVIDIA, and OpenAI. Prioritize correctness, synthesizability, rigorous verification, architectural judgment, reproducibility, and measurable performance over feature count. **Improve the existing project incrementally; do not rewrite it from scratch.**

## Phase 1 — Audit the repository

Inspect all RTL, testbenches, SVA, build scripts, CI, synthesis flows, architecture documents, README, and limitations. Verify rather than assume existing claims:

| Feature | Current documented state |
|---|---|
| AXI channels | AW, W, B, AR, R |
| VALID/READY | Backpressure; payload stability monitored with SVA |
| Transaction IDs | Routed end-to-end |
| FIXED bursts | Up to 16 beats |
| INCR bursts | Up to 256 beats; 4-KiB rule checked |
| WRAP bursts | Legal lengths 2, 4, 8, 16 |
| Write strobes | Per-byte lane updates |
| Read/write concurrency | Independent read and write arbitration |
| Multiple outstanding | Unsupported; one read and one write active globally |
| Out-of-order responses | Unsupported |
| Narrow transfers | Unsupported |
| Unaligned transfers | Rejected with SLVERR |
| Exclusives/atomics | Unsupported |
| CACHE/QOS/REGION/USER | Outside current interface |
| AXI5 extensions | Outside scope |

The README reports 1,764 self-checking regression checks; validate what they cover. Identify correctness risks, bottlenecks, timing paths, parameterization gaps, synthesis portability problems, and missing verification. Write `docs/engineering_audit.md` with findings, severity, and recommendations. Run and record the existing regression suite before modifying RTL.

## Phase 2 — Preserve a reproducible baseline

Record the initial commit hash and test results. If safe and appropriate, create `v1.0-single-outstanding` only if no equivalent tag exists. **Do not overwrite tags or destroy uncommitted changes.** Work on a dedicated feature branch, make logical incremental commits, and preserve a known-good baseline.

## Phase 3 — Benchmark the current design

Create a reproducible performance benchmark suite, adapting paths to repository conventions:

```text
benchmarks/
  README.md
  benchmark_runner.py
  results/
  plots/
```

Parameterize manager/subordinate count, data/address widths, legal burst lengths, read/write mix, backpressure, traffic arrival rate, target distribution, and contention. Test single-manager reads, writes, simultaneous reads/writes, multiple managers to one target, independent-target requests, backpressure stress, burst scaling, and supported width scaling.

Measure successful VALID/READY data handshakes, useful payload bytes versus bus bytes, cycles, sustained read/write and aggregate bandwidth, utilization, average/worst transaction latency, arbitration waits, stalls, and per-manager/per-target throughput. Report GB/s and Gb/s. Clearly distinguish theoretical peak, simulated throughput at an assumed clock, and timing-verified throughput. Export CSV, Markdown summaries, and useful plots. Use deterministic seeds and document test conditions.

## Phase 4 — Synthesis and timing evidence

Check installed tools and use appropriate open-source RTL lint, simulation, synthesis, and timing tools where available. Supply reproducible scripts, constraints, tool versions, and documentation. Test supported configurations such as 2x2/64-bit, 4x4/128-bit, and 8x8/256-bit only when they elaborate and verify successfully.

Measure generic logic/register counts and technology-mapped cell area/timing only where suitable libraries and constraints exist. Distinguish elaboration, generic synthesis, mapped synthesis, static timing analysis, and place-and-route. **Never invent ASIC area, Fmax, or timing closure.** Document any unavailable tooling and provide scripts for later execution.

Suggested structure:

```text
synthesis/
  README.md
  scripts/
  reports/
```

## Phase 5 — Concurrent independent-subordinate access

The existing global read and write arbiters each permit only one globally active transaction. Design and implement safe concurrency so independent targets can progress simultaneously, for example manager 0 reading RAM 0 while manager 1 reads RAM 1 and manager 2 writes RAM 2.

Evaluate per-subordinate arbitration, decoding, ownership tracking, response routing, independent read/write datapaths, fairness, and backpressure. Preserve AXI4 ordering semantics and write-data non-interleaving. Begin with a precisely documented bounded outstanding policy rather than prematurely promising unrestricted concurrency. If required, implement transaction tracking before enabling concurrency. Verify simultaneous independent-target requests, same-target contention, routing, ID preservation, bursts, stalls, resets, errors, and fairness. Keep existing tests passing.

## Phase 6 — Bounded multiple-outstanding support

Only after Phase 5 is correct, design configurable outstanding depth (for example `MAX_OUTSTANDING = 4`) with real ownership/ID tracking, response routing, resource exhaustion handling, and ordering enforcement. Consider internal ID extension/remapping when managers use overlapping external IDs. Preserve AXI4 same-ID ordering and AXI4 write-data ordering; support different-ID completion flexibility only if fully correct.

Test same/different IDs, different target response timings, table-full stalls, simultaneous traffic, reset with pending work, backpressure, and deadlock/liveness assumptions. **Do not merge partial or protocol-incorrect RTL.** If safe completion is blocked, preserve the last verified milestone and document the issue precisely.

## Phase 7 — Pipeline and optimize

Use measured critical paths to evaluate configurable register slices/pipelines for address decoding, arbitration, crossbar routing, response muxing, and READY paths. Preserve VALID/READY stability and avoid combinational loops. Compare latency, sustained throughput, logic utilization, registers, and timing before and after. Only keep changes with defensible benefits.

## Phase 8 — Strengthen verification

Retain existing tests and extend independent scoreboards/reference models, directed corner cases, randomized stress, reproducible seeds, assertions, and coverage. Test data integrity, response routing, ID ordering, write-data ordering, fairness, stalls, reset, address decode failures, parameterization, and supported bursts. Where practical, use an independent AXI checker. Distinguish check counts, functional coverage, assertion coverage, and code coverage. Never claim full AXI4 compliance without sufficient implementation and verification evidence.

## Phase 9 — Improve GitHub presentation

Make the README quickly useful to experienced ASIC/SoC hiring managers: concise overview, verified features, accurate architecture diagram, measured benchmark and synthesis results, verification methodology, getting-started commands, tradeoffs, known limitations, and future work. Keep unsupported features explicitly labeled. Avoid unsupported claims such as "production-ready," "silicon-proven," or "timing-closed."

## Phase 10 — Compare baseline against improvements

Create `docs/architecture_comparison.md` with reproducible before/after results:

| Metric | Baseline | Improved |
|---|---|---|
| Concurrent reads | 1 globally | Measure |
| Concurrent writes | 1 globally | Measure |
| Outstanding depth | 1 read + 1 write globally | Measure |
| Sustained throughput | Measure | Measure |
| Transaction latency | Measure | Measure |
| Logic utilization/area | Measure where possible | Measure where possible |
| Critical path/timing | Measure where possible | Measure where possible |
| Regression results/coverage | Measure | Measure |

Discuss the cost/benefit of concurrency, buffering, ordering complexity, and scalability to AI accelerator and networking ASIC memory subsystems.

## Working rules and definition of done

1. **Take as long as necessary to finish correctly.** Persist through debugging, refactoring, rerunning regressions, and validating claims; do not optimize for speed or token count at the expense of engineering quality.
2. Proceed autonomously without asking permission for routine engineering decisions. Ask only when essential information, credentials, or a potentially destructive operation requires my input.
3. Maintain a stable baseline and use incremental changes. Do not delete working tests, rewrite the whole project, overwrite tags, or discard user changes.
4. Complete phases in dependency order: audit → baseline → benchmark → synthesis → concurrency → outstanding support → optimization → verification → documentation/comparison.
5. Run all feasible lint, elaboration, simulation, regression, and synthesis checks after meaningful changes. Debug failures rather than ignoring them.
6. Never fabricate tests, benchmark data, synthesis reports, timing results, feature support, or protocol compliance.
7. If tools are missing, provide runnable scripts and document the unverified steps. Do not represent scripts alone as executed evidence.
8. Do not stop at a plan or an audit: **implement, test, measure, iterate, and document the actual improvements.** If the environment imposes a hard limit, leave a precise progress report and next commands so work can resume without loss of context.
9. At completion, summarize architectural changes, changed files, commands and tests executed, actual results, remaining limitations, and recommended next engineering steps.

**Success means a demonstrably better, correct, synthesizable, reproducible AXI4 interconnect—not merely more code or a more impressive README.**
