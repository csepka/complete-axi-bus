# MUX X-pessimism diagnosis (2026-10-27)

The original 8x8/256 mapped and routed Icarus tests both failed at 28,430 ns
on `s4_awvalid=X`. A first-transaction target-4 write reproduced it at 101 ns.
This occurs before physical clock-tree construction as well as after routing.

The retained trace observes mapped cell `_115231_` (MUX2_X1) with A=1, B=1,
S=X. Its raw sum-of-products Liberty model returned X. S is derived from
uninitialized **idle** queue payloads; Boolean synthesis may use those bits in
an equivalent decomposition whose output is independent of their binary values.
The X propagates through decode logic into `w_decode_error` and the AW slice.

The refinement returns a known value only when all binary completions agree.
It is localized to MUX2_X1/X2 and leaves the physical circuit and RTL unchanged.
`verification/check_cell_models.py` exhaustively checks the abstraction, including
an explicit reproduction of the original model's pessimism. Original failure
logs are retained here; passing results belong under `verification/reports/`.
The diagnostic trace is a bounded excerpt with original line numbers and the full
trace SHA-256. Long hierarchical-array dumps are omitted; the full trace remains
locally under ignored `build/diagnostic/`. The excerpt includes cell `_115231_`
at 91 ns. It is diagnostic evidence, not a passing test.
