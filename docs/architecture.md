# Architecture Decision Record

This document tracks the architectural choices made for the AXI4 Manager/Subordinate implementation.
Update this file as decisions are made or revised during development.

---

## Protocol

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Protocol | AXI5 (full) | Full burst support, out-of-order transactions, atomics, and poison/trace signals |
| Version | AXI5 (AMBA 5, IHI0022H+) | Latest ARM standard; adds atomic transactions, poison, wake-up signals over AXI4 |
| Variant | Not AXI5-Lite, not AXI5-Stream | Full AXI5 required for burst transfers, transaction IDs, and atomic operations |

---

## AXI5 Additions Over AXI4

These are the signals and features AXI5 introduces that do not exist in AXI4. All are 🔲 pending implementation.

| Feature | Signals | Notes |
|---------|---------|-------|
| Atomic transactions | `AWATOP[5:0]` | Encodes atomic operation type (load, store, swap, compare). On AW channel only. |
| Poison | `AWPOISON`, `WPOISON`, `BPOISON`, `ARPOISON`, `RPOISON` | 1-bit per channel. Marks data as corrupted/invalid without raising an error response. |
| Trace | `AWTRACE`, `WTRACE`, `BTRACE`, `ARTRACE`, `RTRACE` | 1-bit per channel. Used for debug/trace infrastructure. |
| Wake-up signals | `AWAKEUP` | Optional. Allows manager to wake a subordinate before a transaction. |
| Write data poison | `WPOISON` | Per-beat poison on write data channel. |
| MECID (Memory Encryption Context ID) | `AWMECID`, `ARMECID` | Optional. For memory encryption tagging. |
| MPAM (Memory Partitioning and Monitoring) | `AWMPAM`, `ARMPAM` | Optional. For QoS memory partitioning. |

> **Priority for this project:** `AWATOP` (atomics) and poison signals are the most impactful AXI5 additions. Wake-up, MECID, and MPAM are optional and can be deferred.

---

## Bus Topology

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Topology | Shared bus (single manager, single subordinate) | Simplest starting point; interconnect/crossbar can be added later |
| Interface style | SystemVerilog `interface` with modports | Enforces direction at compile time, reduces wiring errors |
| Interface name | `axi_if` | Renamed from `axi_lite_if` to reflect full AXI4 |

> **Future:** A crossbar or interconnect module can be inserted between manager and subordinate to support multiple managers/subordinates without changing the interface definition.

---

## Bus Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| `ADDR_W` | 32 bits | Standard 32-bit address space. Parameterized — can be widened to 64-bit. |
| `DATA_W` | 32 bits | 32-bit data bus. AXI4 allows 32–1024 bits in powers of 2. Parameterized. |
| `ID_W` | 8 bits | Supports up to 256 outstanding transaction IDs per channel. Parameterized. |

---

## Reset

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Reset polarity | Active-low (`ARESETn`) | Required by AXI4 spec |
| Reset style | Asynchronous assert, synchronous deassert | Standard practice for metastability safety |

---

## Transaction Support

| Feature | Supported | Notes |
|---------|-----------|-------|
| Single transfers | ✅ | Burst length of 1 (AWLEN/ARLEN = 0) |
| Burst transfers | 🔲 | INCR, FIXED, WRAP burst types |
| Out-of-order responses | 🔲 | Enabled by ID signals; requires ID tracking in subordinate |
| Exclusive access | 🔲 | AWLOCK/ARLOCK signals present; logic not yet implemented |
| Narrow transfers | 🔲 | AWSIZE/ARSIZE < data bus width |
| Unaligned transfers | 🔲 | Start address not aligned to beat size |

---

## Subordinate Memory Model

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage type | Register array (`logic [DATA_W-1:0] regs[DEPTH]`) | Simple, synthesizable, easy to verify |
| Memory size | Parameterized via `MEM_BYTES` (default 256 B) | Kept small for synthesis; increase for simulation |
| Write strobes | Supported (`WSTRB`) | Byte-lane granularity writes already implemented |
| Address decode | Word-indexed (`addr[IDX_W+1:2]`) | Drops byte offset bits, indexes into word array |

---

## Testbench

| Decision | Choice | Rationale |
|----------|--------|-----------|
| TB style | OOP SystemVerilog (driver, monitor, scoreboard) | Inherited from AXI-Lite project; extensible for AXI4 |
| Simulator | Verilator | Open-source, fast, good C++ integration |
| TB language | SystemVerilog + C++ (Verilator harness) | Matches toolchain choice |

---

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Module names | `snake_case` | `axi_mgr`, `axi_sub` |
| Signal names | `UPPER_CASE` | `AWVALID`, `RDATA` |
| Parameters | `UPPER_CASE` | `ADDR_W`, `DATA_W` |
| Local variables | `snake_case` | `saved_awaddr`, `aw_sent` |
| State enums | `S_` prefix | `S_IDLE`, `S_W_SEND` |
| File names | `snake_case.sv` | `axi_mgr.sv`, `axi_if.sv` |

---

## Open Decisions

Items not yet decided — update this section as choices are made.

| Item | Options | Notes |
|------|---------|-------|
| Max outstanding transactions | 1, 4, 16, ... | Currently 1 (single-outstanding). Needs decision before implementing ID tracking. |
| Burst types to support | INCR only vs INCR+WRAP+FIXED | INCR is mandatory; WRAP needed for cache-line ops |
| Interconnect | None (point-to-point) vs simple crossbar | Depends on whether multiple managers/subordinates are needed |
| Formal verification | None vs SVA assertions | SVA properties for handshake rules would strengthen correctness |
