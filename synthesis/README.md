# Synthesis and timing evidence

## Executed evidence and remaining limits

| Stage | Status |
|---|---|
| Full-interface elaboration/lint | Executed with Verilator 5.044, including benchmark configurations |
| Original baseline `make synth` | Elaboration only: its `begin:coarse` endpoint excluded the coarse stage |
| Corrected RAM coarse synthesis | Executed with Yosys 0.57 at 32/64/128/256 bits |
| Queue coarse synthesis | Executed after mechanical interface-port expansion, depths 1/3/4 |
| Enabled register-slice coarse synthesis | Executed after port expansion at 64/256 data bits |
| Generic queue/slice netlist simulation | Executed with directed outstanding tests |
| Entire fabric generic synthesis | Executed using native read_slang in pinned container Yosys; 2x2/64 and 8x8/256 plus preserved baseline |
| Technology-mapped area / STA / P&R | Executed Nangate45 reference flow; see [physical reports](physical/README.md) |
| Physical signoff | Incomplete: KLayout antenna markers and missing reference LVS deck |

The supplied flat fabric top exposes all manager/target signals, preventing the
serial demonstration command interface from hiding connectivity. It is linted.
It does not by itself remove internal SystemVerilog interfaces; an appropriate
frontend is still required.

## Actual coarse results

Counts below are coarse generic operator cells, explicit FF bits, and retained
memory capacity. A multi-bit mux/ALU is one generic cell: these are not gate counts,
ASIC area, SRAM macro area or comparable library-weighted costs.

| Block | Configuration | Generic cells | FF bits | Memory bits |
|---|---|---:|---:|---:|
| RAM | 32-bit, 4096 bytes | 275 | 162 | 32768 |
| RAM | 64-bit, 4096 bytes | 287 | 194 | 32768 |
| RAM | 128-bit, 4096 bytes | 311 | 258 | 32768 |
| RAM | 256-bit, 4096 bytes | 359 | 386 | 32768 |
| One manager's AW+AR queues | depth 1, ADDR=32/ID=4 | 71 | 14 | 104 |
| One manager's AW+AR queues | depth 3, ADDR=32/ID=4 | 93 | 24 | 312 |
| One manager's AW+AR queues | depth 4, ADDR=32/ID=4 | 93 | 26 | 416 |
| One target's five-channel slice | DATA=64, ADDR=32/ID=4 | 115 | 20 | 508 |
| One target's five-channel slice | DATA=256, ADDR=32/ID=4 | 115 | 20 | 1324 |

Small inferred FIFO memories can become flip-flops during later mapping; retaining
memory bits here is not a promise of macro inference. Queue payload capacity at
depth 4 is 416 bits per manager; the control FFs are separate. Slice storage is
508 payload bits at DATA=64 or 1324 at DATA=256, plus 20 control bits per target.
Do not sum these with RAM counts and call the result full-fabric area: crossbar
and arbitration have their own mapped cost; see the separate complete-fabric reports.

## Reproduce

```sh
make synth
python3 synthesis/scripts/run_synthesis.py --queue --depth 4 --width 64 --label queued
python3 synthesis/scripts/run_synthesis.py --slice --width 256 --label pipeline
python3 synthesis/scripts/check_queue_netlist.py --depth 3
python3 synthesis/scripts/check_queue_netlist.py --slice
python3 synthesis/scripts/make_flat_top.py
# Requires an interface-capable frontend; intentionally fails clearly if absent:
python3 synthesis/scripts/run_synthesis.py --fabric --nm 8 --ns 8 --width 256 --depth 4 --label fabric
```

`run_synthesis.py` records commands (`.ys`), logs, tool version, exit code and JSON
statistics. `begin:fine` includes process lowering, optimization and memory
collection while stopping before fine mapping. It rejects remaining processes,
latches and structural check failures. Queue storage capacity is sanity-checked.
It then technology-independently expands logic and emits a Verilog netlist for
simulation. Generated netlists are ignored by Git and recreated by the commands.

The queue and slice expansion scripts change interface port syntax/names only;
state-machine and datapath source is copied. `axi_ports.py` centralizes the signal
schema. Netlist simulations substitute the resulting modules into the same
independent directed testbench used for RTL, rather than accepting parse success
as evidence of functional synthesis.

## Reference technology flow and integration constraints

The [pinned container flow](physical/README.md) supplies native
[sv-elab / yosys-slang](https://github.com/povik/sv-elab), OpenROAD/OpenSTA and the
Nangate45 reference library. It records executed constraints separately. `scripts/constraints.sdc` is an **unexecuted integration
example**: 10 ns requested clock, 0.2 ns uncertainty and 1 ns I/O delays. Adapt the
PVT corner, input drivers, output loads, SRAM models, reset recovery/removal and
clock assumptions before use. A requested 10 ns clock is not achieved timing.

The existing `subordinate/config.json` remains an unexecuted OpenLane exploration;
the executed reference flow is under `physical/`. Its final timing reports include
extracted setup/hold paths. Standard-cell area includes timing repair, while die
area is reported separately. Antenna/LVS limitations prevent a physical-signoff
claim. Endpoint integration and manufacturing evidence are still required before
claiming hardware bandwidth. No measured silicon Fmax is supplied.

The first complete 8x8/256 pipelined physical run is retained under
`physical/reports/8x8x256-d4-p1/`, including the failing hold/capacitance counts and
incomplete memory-limited DRC attempt. Its full routed-netlist functional test
passes with the exhaustively checked zero-delay MUX models; this does not clear
timing failures. Request-queue order/accounting now also has inductive proofs at
depths 1/3/4/5, with negative mutation checks, under `verification/`.
