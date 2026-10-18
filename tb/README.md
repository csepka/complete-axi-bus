# Verification Sources

- `tb_top.sv` drives the integrated command-port example and performs 418 routing, error, and randomized data checks.
- `tb_axi_burst.sv` drives AXI interfaces directly and performs 1,346 burst, ID, strobe, concurrency, backpressure, maximum-length, and negative checks.
- `axi_stall_sub.sv` is a test-only shim that independently stalls AW, W, and AR to verify payload and grant stability.

Run both with `make test`, or the complete lint/test/synthesis flow with `make ci`.
