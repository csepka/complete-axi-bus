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

Generic coarse RAM synthesis: 599 wires, 9,803 wire bits, 215 generic cells,
one 32,768-bit memory. This is neither full-interconnect area nor mapped ASIC area.
No Liberty library, STA executable or place-and-route evidence was found. No Fmax
or timing-closed bandwidth is claimed.
