# Independent AXI verification

This suite uses pinned **cocotbext-axi** manager and RAM models, an independent
byte-level oracle, and handshake/order monitors. It tests the fabric directly,
with third-party RAM endpoints. It does not replace the original RTL RAM tests.

## Reproduce

```sh
python3 -m venv build/verification-venv
build/verification-venv/bin/pip install -r verification/requirements.txt
build/verification-venv/bin/python verification/run_matrix.py

# After full-fabric reference synthesis (see synthesis/physical/README.md):
build/verification-venv/bin/python verification/run_independent.py --sim icarus \
  --netlist build/physical/2x2x64-d4-p1/generic.v
python3 synthesis/physical/prepare_models.py
python3 verification/check_cell_models.py
build/verification-venv/bin/python verification/run_independent.py --sim icarus \
  --netlist build/physical/2x2x64-d4-p1/orfs/results/nangate45/2x2x64-d4-p1/base/6_final.v \
  --cells build/physical/nangate45_models.v --netlist-kind routed
```

The default test is 2x2/64 bits, depth 4, pipeline enabled, seed 23. The RTL matrix
also covers bypass, depth 1, depth 3, and asymmetric 3x2/128 ports with distinct
seeds. `--nm`, `--ns`, `--width`, `--depth`, `--pipeline` and `--seed` specify the
configuration. A supplied netlist must have exactly the matching parameters;
parameter overrides cannot change an already synthesized netlist.

## What is checked

- Successful VALID/READY transfers and stable payloads during stalls, on all five
  channels at every manager and target.
- Address/response accounting, W beat counts/WLAST, R beat counts/RLAST, response
  IDs and the fabric's strict per-manager response order.
- Independent target-memory inspection after writes and independent byte-array
  expectations for reads, preventing a symmetric routing bug from self-masking.
- FIXED 1/16 beats, WRAP 2/4/8/16 (read and write), INCR lengths including the
  maximum allowed full-width page-contained burst, partial strobes, narrow and
  unaligned INCR forwarding, and legal BFM splitting at 4-KiB boundaries.
- Deterministic random stalls on each channel, overlapping IDs, changing targets,
  queue exhaustion, simultaneous reads/writes, and decode errors.
- Reset with full queues and stalled responses, cancellation of old work, then
  fresh traffic. Reset is coordinated across the fabric and external BFMs.

W may arrive at a target before AW when the independently buffered channels see
different backpressure. The monitor retains W beats and pairs them with addresses
in order; it does not impose an invalid AW-before-W arrival requirement.

`coverage.json` records named observed bins and peak outstanding counts. Required
bins cause failures if absent. These are functional observations, not a claim of
full code, assertion, cross coverage or AXI conformance closure. XML and simulation
logs report pass/fail; manifests identify sources and test code by SHA-256.

## Formal scope

`prove_fifo.py` runs Yosys temporal induction on the actual `axi_channel_fifo` at
WIDTH=8 with arbitrary input data/VALID and output READY. A shift-register oracle
checks order, occupancy, output validity/readiness and stalled payload stability.
Read-only observation ports are mechanically added in a generated copy to expose
ring-pointer and stored-second-word invariants; functional source is unchanged.
The proof assumes reset on the first sampled cycle and allows subsequent sampled
resets. It proves these FIFO safety properties, **not** full-fabric equivalence,
analog asynchronous reset behavior, metastability or liveness.

## Simulation scope and known warnings

Verilator tests RTL in two-state simulation. Icarus runs the complete generic,
mapped or routed netlist in four-state simulation. Valid/READY and meaningful
payloads must resolve; uninitialized idle payload bits are intentionally ignored.
Standard-cell models generated from Liberty are **zero delay**. Routed timing is
an independent extracted-parasitic STA result, not SDF-annotated simulation.

Generated Yosys vectors can trigger Verilator's vector-level UNOPTFLAT diagnostic
for acyclic bit-level chains. Only generated-netlist tests waive that diagnostic;
reference synthesis requires `scc -expect 0`. RTL lint remains unchanged. The
pinned BFM emits cocotb deprecation notices and expected flush notices during
reset; neither is counted as a test pass or silently used to ignore assertions.

The fabric can forward narrow/unaligned requests to capable external endpoints.
The project's demo RAM still rejects them. Optional sidebands/exclusives remain
outside the interface. These tests therefore do not establish full AXI4 compliance.

Models: [cocotbext-axi](https://github.com/alexforencich/cocotbext-axi),
[cocotb runner](https://docs.cocotb.org/en/stable/library_reference.html).

The preserved baseline is tested with `--baseline --depth 1 --pipeline 0` and an
explicit baseline netlist. It has only one accepted transaction globally per
direction when responses are held. Its reset test checks that global capacity;
upgraded tests still require every manager's queues to be full. This exception
is explicit and cannot be selected accidentally for an RTL test.

## Evidence consistency and release gate

`python3 verification/audit_evidence.py` verifies current source hashes, all 17
original validation stages, FIFO proof, required independent test XML/coverage,
and archived physical artifact hashes. It distinguishes consistent evidence from
physical acceptance. Add `--require-physical` for a gate that fails on incomplete
physical signoff; the current antenna/LVS findings intentionally fail that gate.
The runner deletes previous pass artifacts before rebuilding so a failed rerun
cannot leave stale success behind.
The evidence audit also removes its previous success record before validating;
an unfinished test or mismatched hash fails the audit without retaining old success.

## Four-state cell-model semantics

Liberty-to-Verilog conversion expresses MUX as `(S & B) | (~S & A)`. In four-state
simulation this yields X when A=B=1 and S=X, although every binary completion of
S gives 1. ABC can legally use uninitialized idle queue payload bits as selectors
in equivalent Boolean decompositions. The 8x8 target-4 decode cone exposed this
pessimism: MUX `_115231_` had A=1, B=1 and S=X; that X propagated to address VALID.
It reproduced in the mapped netlist before any clock tree or routing.

`refine_mux_models.py` retains all other generated cells and substitutes a
consensus-preserving conditional for MUX2_X1/X2. Selected Z data is treated as an
unknown logic value. It never forces an ambiguous output to a constant: conflicting
possible binary outputs remain X. `check_cell_models.py` exhaustively compares
128 four-state cases against all binary input completions and checks the 16 binary
cases against the original Liberty functions. The original pessimistic behavior
is also reproduced as a regression check. Raw models remain in
`build/physical/nangate45_models_raw.v`; diagnostic evidence is under
`verification/diagnostics/mux-pessimism/`. These are zero-delay functional models,
not timing, metastability, transistor or signoff models.

## Outstanding request-queue induction

`prove_request_queue.py --depth N` proves the real request queue at depths
**1, 3, 4 and 5**, ADDR_W=32, DATA_W=32, ID_W=4. The existing structural interface
expander retains the original functional statements. Read-only observation ports
expose the ring pointers, counts, control state and stored payloads; they add no
functional behavior. An independent shift-list oracle retains every accepted
address until the corresponding B or final R handshake.

The proof establishes occupancy bounds, exact payload/order retention, pointer
wraparound, admission backpressure, head issue, address stability under stalls,
response ownership gating, and output suppression during reset. Ring-to-list
storage and pointer/count relations are asserted as inductive invariants, not
assumed. All traffic inputs are arbitrary; the only environment assumption is
reset on the first sampled cycle. Subsequent sampled resets are allowed. The
proof does not establish endpoint response-ID/beat legality, full-fabric routing,
W payload stability for a nonconforming manager, analog reset behavior or liveness.

`check_queue_mutations.py` deliberately corrupts two generated depth-3 copies:
one overwrites the head instead of the tail on enqueue; the other retires on the
last W handshake instead of B acceptance. Both produce reachable counterexamples
within eight sampled steps. Solver errors or induction failures alone do not count
as detection. Logs and VCD counterexamples are retained under
`diagnostics/request-queue-mutants/`; production RTL is never mutated.

```sh
python3 verification/prove_request_queue.py --depth 1
python3 verification/prove_request_queue.py --depth 3
python3 verification/prove_request_queue.py --depth 4
python3 verification/prove_request_queue.py --depth 5
python3 verification/check_queue_mutations.py
```

The default independent RTL matrix and GitHub CI include these proofs and negative
checks. The evidence audit verifies all four proof source hashes and the retained
counterexample hashes.

## Executed full-fabric matrix

The current evidence audit requires these **12 passing independent runs**:

| Representation | Configurations | Simulator |
|---|---|---|
| RTL | 1x1/32 d1 bypass; 2x2/64 d4 bypass and pipeline; 3x2/128 d3 pipeline | Verilator |
| Generic full fabric | 2x2/64 d4 pipeline; 8x8/256 d4 pipeline | Icarus (2x2), Verilator (8x8) |
| Mapped standard cells | 2x2/64 and 8x8/256 d4 pipeline | Icarus |
| Routed standard cells | 2x2/64 and initial/repair 8x8/256 d4 pipeline | Icarus |
| Original baseline routed | 2x2/64 d1 bypass, explicit global-capacity policy | Icarus |

The initial large mapped/routed cases each complete 498,760 ns of simulated traffic,
including eight random batches and every manager's full-queue/reset checks. These
are zero-delay functional results. In particular, the passing initial 8x8 routed
case still has failing extracted hold/electrical timing. It cannot stand in for a
new repair-layout netlist without separate validation. Exact seeds, sources,
packages and observed bins are in the per-run manifests and coverage JSON files.

The separate repair 8x8 routed netlist passes seed 71 (506,450 simulated ns).
The evidence audit covers 12 completed cases, including both large routed
variants. These remain zero-delay functional tests: both large layouts still
fail extracted hold/electrical checks.
