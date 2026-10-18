# RTL Sources

| File | Purpose |
|---|---|
| `axi_if.sv` | Core AXI4 channel interface and modports |
| `axi_interconnect.sv` | N-to-N shared burst interconnect with independent read/write arbitration |
| `axi_mgr.sv` | Single-beat command adapter used by the integration example |
| `axi_ram.sv` | Flat-port burst RAM core suitable for standalone synthesis |
| `axi_sub.sv` | `axi_if` wrapper around `axi_ram` |
| `axi_protocol_checker.sv` | Simulation-only SVA checker |
| `axi_top.sv` | Parameterized integration example |

Compile synthesizable integration sources in the order listed by the root `files.f`.
