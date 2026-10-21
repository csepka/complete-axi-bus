# RTL sources

| Module | Responsibility |
|---|---|
| `axi_if` | Implemented AXI signals, directions and width checks |
| `axi_interconnect` | Per-manager queues, head decode, structural crossbar and per-target arbitration |
| `axi_request_queue` | Bounded accepted-address storage and strict ordered head issue |
| `axi_target_arbiter` | Baseline round-robin arbitration, burst ownership and local DECERR service |
| `axi_register_slice` | Optional independent target-boundary stages on five channels |
| `axi_channel_fifo` | Two-entry registered channel stage with occupancy-based READY |
| `axi_ram` | Flat-port full-width burst RAM, validation and byte strobes |
| `axi_sub` | Interface wrapper for RAM |
| `axi_mgr` | Single-beat command adapter |
| `axi_top` | Serial command-port integration example |
| `axi_protocol_checker` | Simulation SVA; not a complete AXI VIP |

Use the source order in `files.f`. Detailed behavior is in
[architecture](../docs/architecture.md) and [mastery](../ENGINEERING_MASTERY.md).
