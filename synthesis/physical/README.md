# Full-fabric open reference implementation

This flow synthesizes the actual interface-array fabric with native `read_slang`,
maps it to Nangate45 standard cells, places and routes it, extracts parasitics,
and reports setup/hold timing. It also runs the supplied KLayout DRC deck.
**Physical acceptance is incomplete:** antenna markers remain and the pinned
platform does not supply the LVS deck named by its configuration. No silicon,
foundry signoff, full AXI4 compliance or production readiness is claimed.

## Reproduce

Docker Desktop must remain running. `toolchain.json` pins the official ORFS image
by immutable digest. Containers run without network access and mount only this
repository. Download the pinned image first if it is not cached. The image is
linux/amd64; these runs used Docker's amd64 emulation on an Apple Silicon host.

```sh
python3 synthesis/physical/run_reference.py --stage checks
python3 synthesis/physical/collect_reference.py 2x2x64-d4-p1
python3 synthesis/physical/run_reference.py --baseline --depth 1 --pipeline 0 --stage checks
python3 synthesis/physical/collect_reference.py baseline-2x2x64-d1-p0
python3 synthesis/physical/run_reference.py --nm 8 --ns 8 --width 256 --stage checks
python3 synthesis/physical/collect_reference.py 8x8x256-d4-p1
```

`checks` intentionally exits nonzero when LVS collateral is missing. The collector
archives available evidence even after a failed check, then exits nonzero when
physical acceptance is incomplete. Do not turn these failures into successful
CI by ignoring exit codes. `--stage finish` runs through GDS/extraction/STA without
claiming DRC/LVS acceptance. `--stage generic` and `--stage synth` stop earlier.
`--resume` reuses generic synthesis only after checking RTL hashes and parameters;
ORFS make dependencies determine later-stage reuse. A changed clock or physical
configuration requires regeneration of affected stages.

Outputs, netlists, GDS, DEF and SPEF are under `build/physical/<label>/`. Compact
reports, source/artifact hashes, constraints, tool commands, detailed paths and
layout images are archived under `reports/<label>/`. Generated netlists are not
checked into Git. Use [independent verification](../../verification/README.md) to
reproduce RTL and four-state generic/mapped/routed functional checks.

## Measured 2x2 comparison

Both rows use 64-bit data, 32-bit addresses, 4-bit IDs, the same 250 x 250 um die,
10 ns clock and NangateOpenCellLibrary typical corner (1.1 V, 25 C).

| Fabric | Standard-cell area (um²) | Setup worst slack (ns) | Hold worst slack (ns) | Router DRC | KLayout markers |
|---|---:|---:|---:|---:|---:|
| Original v1.0.0, globally serialized | 2,891.15 | +7.08936 | +0.0308236 | 0 | 4 antenna |
| Concurrent, queue depth 4, target pipeline | 31,245.4 | +7.27049 | +0.0278701 | 0 | 4 antenna |

These are final extracted timing results and standard-cell areas, including clock
and timing-repair cells but excluding filler. The deliberately roomy die is not a
cell-area estimate. The upgraded configuration costs about 10.81 times the cell
area of this small baseline: it adds queues, target slices and concurrency, and
requires substantial hold buffering under the specified uncertainty. This is a
combined configuration comparison, not an isolated estimate of pipeline cost.
Do not extrapolate its ratio to other port counts or constraints.

## Observed critical paths

In the original 2x2 design, the reported worst setup path runs from manager
`m_ARADDR[60]` to target `s_ARADDR[17]`, consistent with combinational address
selection. In the upgraded 2x2 layout it runs from manager 0's read-queue head
pointer `rh[0]` to `m_RDATA[43]`: response selection remains a path worth examining
if a tighter clock is needed. The upgraded worst hold path runs from target 0's
W-slice occupancy bit to its tail pointer. See the complete `6_finish.rpt` reports
for clock latency, uncertainty, cell/wire delay and required-time arithmetic.
The timing paths are implementation observations, not proof that any one module
alone determines Fmax across all configurations.

## Constraints and observed implementation issues

- Clock period 10 ns, clock transition 0.1 ns, setup and hold uncertainty 0.2 ns.
- External data input delay 0.2..1.0 ns, input transition 0.1 ns; output delay
  0.2..1.0 ns and **5 fF** load. Liberty capacitance units are fF, not pF.
- `ARESETn` is false-pathed. The integration contract requires externally
  synchronized deassertion. Reset recovery/removal and reset-domain crossing are
  not signed off. OpenSTA's one input-without-delay warning refers to this reset.
- No endpoint RAM, pads, package, SRAM macro, multi-corner variation, IR-drop or
  electromigration signoff is included. This is the fabric block only.
- The default hold-repair buffer budget was insufficient. A bounded retry hook
  permits a larger budget without relaxing constraints. A 30 ps hold repair
  margin avoids a small extracted hold violation seen in an earlier trial.
- Wide interfaces require many boundary pins. `-min_distance_in_tracks` makes the
  requested one-track spacing explicit; omitting it interprets distance in um.
- Yosys must leave no processes, latches, blackboxes or combinational strongly
  connected components. Full netlists are checked functionally by independent
  BFMs. ORFS's transformation equivalence checks add evidence, but do not prove
  full RTL-to-layout equivalence or AXI protocol compliance.

## DRC and LVS findings

Both small layouts have zero detailed-router errors. The supplied KLayout deck
reports four antenna markers in each layout and no other markers. Its XML stores
seven values for each antenna marker; ORFS's `grep <value>` counter says 28. The
collector counts actual `<item>` records and preserves the complete report.
The upgraded markers are on metal4, metal5 and metal8; baseline markers are on
metal4, metal7 and metal9. They are unresolved, not waived.

The pinned Nangate45 technology LEF has no antenna rules and most cell pins lack
antenna gate-area data, so the router's antenna check does not establish the
KLayout antenna condition. Repair needs validated process/LEF antenna collateral
and a new layout/check cycle. Inventing a rule or disabling the deck would not
establish correctness. The platform config names `lvs/FreePDK45.lylvs`, but that
file is absent from both the pinned image and the inspected upstream platform.
LVS therefore has **not run**. Netlist simulation cannot substitute for LVS.

Nangate45 is explicitly a non-manufacturable educational reference library.
See the [upstream platform description](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master/flow/platforms/nangate45)
and [OpenROAD antenna-repair requirements](https://openroad.readthedocs.io/en/latest/main/src/grt/README.html#repair-antennas).
A production implementation needs a supported process with complete signoff
collateral, all required corners, reset checks, physical closure and integration
verification. Positive slack at one requested period is not a measured Fmax sweep.

## Larger configuration repair experiment

The first 8x8/256 depth-4 pipelined layout completed with 325,000 um² standard-cell
area and +6.13827 ns setup slack, but -0.030555 ns hold slack, 2,660 hold violations
and 80 maximum-capacitance violations. It is **not timing closed**. Its worst
reported hold path is a target-7 R-slice payload flip-flop's enable-feedback path.
The larger experiment retains the same SDC while increasing repair margins:

```sh
python3 synthesis/physical/run_reference.py --nm 8 --ns 8 --width 256 \
  --variant repair --hold-margin 0.10 --cap-margin 15 --stage checks
```

The variant has its own output directory and fresh synthesis; the initial layout
is retained. Margin controls ask the implementation tools to repair beyond the
constraint boundary; they do not relax the clock, load, uncertainty or I/O delays.
Until its final extracted report and checks are complete, this is an experiment,
not evidence of achieved bandwidth.
