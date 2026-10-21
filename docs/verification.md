# Verification and reproducibility

## Executed regressions

| Test / flow | Evidence and purpose |
|---|---|
| `tb_top` | 418 checks; retained command-port integration, errors, isolation, 250 seeded commands |
| `tb_axi_burst` | 1,618 checks; original 1,346 retained, plus all legal WRAP lengths, FIXED boundary, invalid encoding, write narrow/unaligned rejection and page-edge accesses |
| `tb_axi_page_boundary` | Isolates 4-KiB rejection using an 8-KiB RAM; rejected crossing write preserves both neighboring words |
| `tb_axi_ram_params` | Retained minimum-address-width endpoint carry regression |
| `tb_axi_outstanding` | 525 checks at depth 4; queue exhaustion, same/different IDs, changing targets, queued errors, parallel traffic, reset and recovery |
| Outstanding depth matrix | Depths 1, 3, 5; 375 / 475 / 575 checks; explicit non-power-of-two wraparound |
| Optional target pipeline | Same 525-check directed bench and complete 1,618-check burst bench, including buffered reset and legal/error burst types |
| `tb_axi_channel_fifo` | 10,000 seeded stimulus cycles, 5,455 accepted payload comparisons; observes empty, full, simultaneous push/pop, output stall and reset while full |
| Generic queue netlist | Directed outstanding bench with Yosys-lowered queue replacing RTL queue, depths 3 and 4 |
| Generic slice netlist | Directed pipelined bench with Yosys-lowered register slice replacing RTL slice |
| Benchmark matrix | 2x2/64, 4x4/128, 8x8/256; 10 scenarios for each configuration and architecture variant |
| Asymmetric/stress matrix | 1x1/32/depth1; 3x2/64/depth3/40-bit address; 2x3/128/depth5; seeds 1/23/97 at 4x4/128; 75% reads and pipelined randomized traffic |

Counts are executed comparisons, not unique requirements, coverage percentages or
proof of protocol compliance. The parameter test has no comparable numeric count.
The benchmark checks every R beat, response identity/status and completed writes,
and asserts beat conservation and expected independent-target concurrency.

## What the outstanding test proves by observation

It fills both queues with a stalled target-0 head and verifies that an additional
request remains backpressured. Managers 1/2 complete unrelated work before the
head is released. Completion of unrelated work must not release manager-0 slots.
Then the overflow requests complete and every response/data burst is checked in
order. This runs with identical IDs and with varying IDs. The test crosses queue
pointer boundaries, changes targets, uses partial strobes, and places valid work
between DECERR/SLVERR transactions. A nonzero BASE_ADDR and 40-bit addresses exercise
decode below/above the map. Three simultaneous independent target transfers are
explicitly required. Persistent same-target writers must all finish within bounds.

Reset tests cover held address grants/full queues, a partially sent W burst,
unconsumed R data, and stalled B plus R responses. After reset there must be no
stale response, and fresh traffic must complete with checked data. With pipelining,
reset also discards target-boundary channel buffers.

## Assertions and reference models

`axi_protocol_checker` monitors stability of VALID and the complete implemented
payload on AW/W/B/AR/R while stalled, plus known WLAST/RLAST. Tests place it on
all external manager/target interfaces. `AXI_INTERNAL_CHECKS` adds dispatch and
per-target link monitors. Queue SVA checks occupancy bounds and ownership on
retirement. Channel FIFO SVA checks occupancy and output stability.

The original burst model generates addresses independently (division-based WRAP
calculation versus RTL masking) and applies byte strobes. The outstanding model
tracks expected memory independently of DUT storage. The performance fixture
preloads a deterministic target/address-dependent pattern, checks incoming read
values and final written memory, and counts target handshakes directly. Read and
write regions are disjoint to avoid ambiguous memory races. A FIFO software queue
checks exact order/data under random stalls and reset.

The test-only stall shim gates target AW/W/AR acceptance. Its downstream VALID is
not intended as standalone AXI source behavior when a stall control changes; the
checker observes the upstream contractual interface. Production RTL contains no
such gating shim.

## Commands

```sh
make ci                         # strict RTL lint, all default tests, RAM synthesis
make extended                   # depth matrix, queue/slice netlists, pipeline, seeded matrix
make benchmark                  # default queued performance matrix
make PIPELINE=1 test-outstanding
make waveform                   # regenerate SVG from passing burst VCD
python3 tools/validate_upgrade.py # full retained before/after validation
```

The full runner writes `synthesis/reports/validation.json` with exit codes and
source SHA-256 values. Benchmark metadata contains the source revision/hashes,
arguments and Verilator version. Raw logs accompany CSV/Markdown results.
CI invokes `make ci` and `make extended` using the EDA-suite date and action commit
pinned in `.github/workflows/ci.yml`.

## Tool issues resolved without weakening checks

Verilator 5.044 could not bind a checker through a hierarchical interface-array
reference; internal checkers are instantiated in the corresponding generated RTL
scope under a test-only define. Its split coroutine output also generated an
undeclared fork synchronization symbol for the directed bench; `--output-split 0`
avoids that compiler defect. Assertions and stimulus remain enabled.

Stock Yosys interpreted an array of packed structs incorrectly in the queue port
expansion. Explicit packed vectors with explicit unpacked bounds fixed it. Storage
sanity checks and queue netlist simulations guard against recurrence. The original
`synth -run begin:coarse` also stopped before process lowering; the corrected flow
runs the coarse stage and checks for remaining processes/latches.

## Remaining assurance gaps

No independent commercial AXI VIP, formal safety/liveness proof, four-state X
coverage closure, code coverage percentage, or assertion coverage percentage is
claimed. Verilator's main simulation is two-state; `$isunknown` checks do not
substitute for a four-state signoff run. Fairness is checked under finite traffic
and bounded delays; indefinite endpoint stalls make unconditional liveness
impossible. Technology-specific SRAM, CDC/reset-domain, gate-level timing and
physical implementation remain separate integration work.
