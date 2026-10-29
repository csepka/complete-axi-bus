# Engineering audit — baseline

Baseline: `2ec5059cf00b51b40ee441fab273f5a2d1d8f462`, preserved by existing `v1.0.0`.
Working tree was clean. Local `make ci` passed before RTL changes on 2026-10-20
(America/Los_Angeles). Verilator 5.044; Yosys 0.57. Raw logs are in
`synthesis/reports/baseline-ci.log` and `baseline-ram-yosys.log`.

## Findings

| Severity | Finding / evidence | Recommendation |
|---|---|---|
| High (performance) | `axi_interconnect` has one W and one R FSM globally; unrelated targets serialize. | Reuse the existing route-locking arbiter per target. |
| High (verification) | 418 integration + 1,346 burst checks are comparisons, not coverage points. Burst checker checks stability, not full AXI compliance. | Retain tests; add independent concurrency, queue, ordering, reset and parameter tests. |
| High (evidence) | Original `synth -run begin:coarse` stops before the coarse label. Logs retain 5 RAM processes: this is elaboration, not coarse synthesis. Discovered while validating the new queue. | Correct to `begin:fine`, require `check -assert`, and distinguish corrected evidence. |
| High (integration) | `axi_top` serializes its command port; it cannot expose fabric throughput. | Benchmark direct AXI manager interfaces. |
| Medium | IDs are preserved, but no outstanding storage exists. | Bounded address queues; retain ownership through completion, enforce strict per-manager ordering. |
| Medium | Decode subtract/shift, linear RR scan, dynamic muxes and READY propagation are combinational. | Measure structure and simulations; do not assert timing without STA. |
| Medium | No full-fabric synthesis; stock Yosys frontend lacks interface-array support and installed slang plugin is absent. | Provide reproducible frontend-capable flow; report RAM-only results separately. |
| Medium | Address-space fit assertion uses a host-sized shift and ignores BASE_ADDR extent. | Use widened arithmetic for map validation. |
| Medium | Width/count support is asserted but existing tests cover primarily 2x2/32 and 3x3/32. | Simulate 2x2/64, 4x4/128, 8x8/256 and non-power-of-two dimensions. |
| Medium | RAM zero initialization is simulation-only; concurrent same-address RAM read/write behavior needs explicit contract. | Initialize benchmark memory explicitly and avoid read/write collisions; document read-before-write behavioral model. |
| Medium | Invalid WLAST can modify earlier/current memory beats before error detection. | Document non-atomic error behavior; do not promise rollback. |
| Medium | Reset cancels in-flight state; no reset-under-load regression. | Reset queues and ownership together with endpoints; test restart. |
| Low | CI prose says package versions are unpinned, but workflow pins the EDA suite date and action commit. | Correct stale documentation. |

## Existing evidence and scope

Read all six functional RTL modules, protocol checker, all three testbenches,
stall shim, Makefile, file list, CI workflow, synthesis configuration and architecture/
verification documentation. The feature matrix matches implementation: FIXED <=16,
INCR <=256 subject to 4-KiB and RAM extent, WRAP 2/4/8/16, byte strobes,
full-width aligned only, ID preservation, independent reads/writes. Decode errors
consume AWLEN+1 or emit ARLEN+1 DECERR beats. Target validation emits SLVERR.
Optional AXI sidebands and exclusives are absent.

The 1,764 checks are 418 command checks (including 250 seeded commands) plus
1,346 response/data/ID/RLAST comparisons. The parameter regression separately
checks endpoint carry at minimum address width. They are not 1,764 unique scenarios,
functional coverage, code coverage, or proof of conformance. Existing maximum burst,
WRAP, strobe, negative, stall and competing-manager tests passed.

Original RAM elaboration-only statistics (the advertised coarse pass did not execute): 599 wires, 9,803 wire bits, 215 generic cells,
one 32,768-bit memory. This is neither full-interconnect area nor mapped ASIC area.
No Liberty library, STA executable or place-and-route evidence was found. No Fmax
or timing-closed bandwidth is claimed.


## Final engineering audit and disposition

| Finding | Disposition / evidence | Remaining boundary |
|---|---|---|
| Global serialization | Resolved by per-target retained arbiters; independent traffic records eight W and eight R handshakes per cycle | Hotspots remain bounded by one target |
| No accepted-request tracking | Per-manager AW/AR queues retain identity/target payload through response retirement; depth 1/3/4/5 tests | Strict one executing head per manager/direction |
| ID collisions / cross-target ordering | Owner-based routing and strict head issue; same/different IDs plus queued errors verified | No per-manager out-of-order completion |
| Combinational target boundary | Optional two-entry channel stages, default bypass; directed/random and synthesized-slice verification | No STA proof of Fmax benefit; added cycles documented |
| False coarse-synthesis evidence | Fixed stage endpoint; require process/latch/structural checks; corrected RAM/queue/slice reports | Full-fabric read_slang flow now executed; mapped results archived separately |
| Struct-array synthesis fragility | Explicit packed-vector FIFO arrays; capacity sanity check; actual queue netlist substitution | No generic frontend equivalence proof |
| Reset / exhaustion gaps | Full queues, held grants, partial write, stalled responses, buffered-channel reset and fresh-traffic recovery | Reset must encompass all participants; memory is not rolled back |
| Burst coverage gaps | All legal WRAP lengths, FIXED limit, reserved burst, narrow/unaligned writes and page edges added | Not a complete conformance test suite |
| 4-KiB check confounded by RAM extent | Dedicated 8-KiB RAM test crosses only the page boundary and verifies no data modification | External targets must implement their own validation contract |
| Width/count/seed gaps | 2x2/64, 4x4/128, 8x8/256, asymmetric dimensions, 40-bit addressing and seeded matrices | Not every advertised parameter combination is exhaustively simulated |
| Duplicated synthesis-adapter metadata | Shared signal schema and checked mechanical port expansion; explicit build-directory creation | Interface schema must track axi_if changes |
| Stale waveform paths/counts | Target-arbiter paths updated; queue versus target acceptance distinguished; hard-coded check count removed | Waveform is one illustrative interval, not coverage |
| Misleading performance interpretation | Separate aggregate/directional rates, assumed clock, offered/accepted latency, average/peak occupancy, stalls and target counters | Hardware bandwidth still requires mapped timing and endpoint evidence |
| Physical library / STA / P&R | Pinned Nangate45 flow executes mapping, P&R, extraction and STA | Antenna markers, missing LVS deck, one typical corner; no production signoff |

The baseline arbiter's generic endpoint mapping and decode are intentionally retained
inside each one-target instance. This supports incremental reuse and review. A
future simplification should be justified by full-fabric synthesis/timing evidence
and regression equivalence, rather than replacing proven logic solely for fewer
lines. Current generated wiring uses explicit signals, avoiding opaque protocol
macros or additional RTL package dependencies.

The queue and optional slice separate transaction ownership from channel elasticity.
The demonstration manager/top remain deliberately serial and are labeled as such.
Independent BFMs and four-state full-netlist checks now complement the original
two-state tests. FIFO safety is proven at WIDTH=8; request-queue order/accounting
is proven at depths 1/3/4/5, with two reachable mutation counterexamples checking
the oracle's sensitivity. Full-fabric liveness remains bounded
by endpoint fairness assumptions. No unresolved failing regression is accepted
as a completed milestone; final executed commands and source hashes are in
`synthesis/reports/validation.json`.

## Reference-flow continuation audit

- Native interface synthesis leaves no latches, processes, blackboxes or
  combinational SCCs; independent tests also run on its emitted netlists.
- Liberty load units were verified as fF. Final reports use 5 fF, not the earlier
  exploratory 0.005-fF load. No obsolete trial is reported as final acceptance.
- Hold repair needed more than the default buffer budget; bounded retries preserve
  constraints. Its area cost is included, not hidden.
- The independent monitor allows W to arrive before AW at a buffered target.
  Stored beats are matched in order when AW arrives.
- Reset exhaustion expectations distinguish baseline global capacity from upgraded
  per-manager queues; modern full-queue assertions remain strict.
- KLayout markers are counted as XML items, not metadata values. Router DRC=0 does
  not override antenna errors or a missing LVS result.
- OpenROAD transformation equivalence and zero-delay routed simulation are not
  RTL-to-transistor equivalence or SDF timing simulation.

The large four-state mapped test found MUX reconvergence X pessimism in generated
Liberty functional models. The diagnostic proved A=B=1 with S=X at `_115231_`;
a model refinement now checks all 128 four-state combinations and all 16 binary
equivalence cases across both MUX strengths. Original failure evidence is kept.
No RTL reset behavior or X-checking assertion was weakened. See the detailed
[model semantics](../verification/README.md#four-state-cell-model-semantics).

The large margin-repair variant passes its own independent routed test, but has
2,571 hold, 25 capacitance, one slew and 999 KLayout antenna violations. The
wrapper lost its command completion record while the stage log and DRC XML
survived. The runner now records commands before launch, the collector archives
the stage DRC log, and hard-interruption/trial-isolation tests are part of CI.
