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
