# Verification sources

Retained integration, burst and parameter benches are supplemented by
`tb_axi_outstanding` (ordered queues, errors, concurrency, reset),
`tb_axi_channel_fifo` (independent randomized FIFO scoreboard) and
`tb_axi_benchmark` (parameterized traffic and measured handshakes).

`axi_stall_sub` is a test-only target backpressure fixture. See
[verification](../docs/verification.md) for test counts, scope, limitations and
commands. `make ci` runs default checks; `make extended` adds parameter, pipeline,
netlist and seed matrices.
