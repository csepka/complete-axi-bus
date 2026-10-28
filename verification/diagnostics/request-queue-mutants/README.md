# Expected request-queue counterexamples

`verification/check_queue_mutations.py` mutates generated copies of the actual
queue at depth 3. Production RTL is unchanged. Both mutations must produce an
explicit reachable SAT counterexample within eight sampled steps:

- `overwrite-head`: enqueue overwrites the oldest entry instead of the tail.
- `early-release`: the write slot retires on the last W beat instead of B acceptance.

The `.log` and `.vcd` files describe deliberately broken designs and are expected
failures, not failures of the production queue. `summary.json` records detection,
source and counterexample hashes. First run `prove_request_queue.py --depth 3`
to regenerate the unmodified observed source and proof script. Only initial
sampled reset is assumed; the ring-to-list and ownership invariants are asserted.
