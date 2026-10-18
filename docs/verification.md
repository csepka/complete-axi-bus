# Verification Strategy

## Regression Structure

The project uses two complementary self-checking SystemVerilog regressions under Verilator.

### `tb_top.sv` — subsystem integration

Exercises the command adapter, all managers, shared interconnect, all subordinates, and memory targets as an integrated subsystem.

- every manager-to-subordinate route
- cross-manager write/read ownership
- endpoint memory isolation
- unmapped read and write DECERR
- mapped but out-of-range SLVERR
- invalid command-port manager selection
- selector changes while accepted commands remain in flight
- 250 deterministic pseudo-random reads and writes
- bounded progress timeouts

Passing result: **418 checks**.

### `tb_axi_burst.sv` — direct AXI protocol behavior

Drives manager interfaces directly and maintains a byte-strobe-aware reference memory.

- four-beat INCR write/read
- four-beat FIXED write/read
- four-beat WRAP write/read beginning at wrap boundary end
- partial-byte write strobes
- simultaneous write requesters
- simultaneous read requesters
- overlapping read and write datapaths
- stalled AW, W, and AR channels through a controllable subordinate shim
- address-grant stability when a second manager requests during a stall
- top-of-memory WRAP behavior
- malformed WLAST and narrow-transfer rejection
- 8-beat, 16-beat, and maximum 256-beat bursts
- randomized W, B, and R pacing/backpressure
- AWID/BID and ARID/RID integrity
- RLAST placement
- burst DECERR generation
- out-of-range, unaligned, and illegal-WRAP SLVERR cases
- bounded per-channel timeouts

Passing result: **1,346 checks**.

## Assertion Set

`axi_protocol_checker.sv` is instantiated at every manager and subordinate interface in the burst test. It asserts:

1. AWVALID and all AW payload fields remain asserted/stable under backpressure.
2. WVALID, WDATA, WSTRB, and WLAST remain asserted/stable under backpressure.
3. BVALID, BRESP, and BID remain asserted/stable under backpressure.
4. ARVALID and all AR payload fields remain asserted/stable under backpressure.
5. RVALID, RDATA, RRESP, RID, and RLAST remain asserted/stable under backpressure.
6. WLAST is known whenever WVALID is asserted.
7. RLAST is known whenever RVALID is asserted.

## Requirement-to-Test Map

| Requirement | Integration TB | Burst TB | SVA |
|---|:---:|:---:|:---:|
| Address routing | ✅ | ✅ | — |
| Round-robin multi-manager service | — | ✅ | — |
| Independent read/write progress | — | ✅ | — |
| FIXED/INCR/WRAP address behavior | — | ✅ | — |
| Transaction ID preservation | — | ✅ | — |
| Byte strobes | — | ✅ | — |
| DECERR completion | ✅ | ✅ | — |
| SLVERR completion | ✅ | ✅ | — |
| Response and payload backpressure stability | — | randomized | ✅ |
| RLAST correctness | — | ✅ | known-value check |
| Command adapter correctness | ✅ | — | — |

## Automation and Determinism

Both randomized phases use fixed seeds. `make ci` runs warning-clean lint, both simulations, and coarse Yosys synthesis. GitHub Actions runs the same target on every push and pull request and reports the installed tool versions. The workflow is automated and deterministic for a given toolchain, but package versions are not claimed to be hermetically pinned.

## Remaining Verification Work

For production use, add formal safety/liveness proofs, mutation testing, parameter-matrix regression (especially 64/128-bit data widths), reset injection during every active state, protocol VIP interoperability, and functional/code coverage closure.
