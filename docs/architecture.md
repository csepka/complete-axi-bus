# AXI4 Interconnect Architecture

## 1. Scope

This repository implements a bounded, synthesizable AXI4 memory interconnect. It is designed as a portfolio-quality example of AMBA microarchitecture, integration, verification, and automation—not as a drop-in, formally certified commercial IP block.

The interface includes the core AXI4 burst and ID signals. Optional AXI4 sidebands (LOCK, CACHE, QOS, REGION, USER) and AXI5 additions are intentionally excluded. Aligned, full-width transfers are supported; malformed, narrow, unaligned, out-of-range, and 4-KiB-crossing requests terminate with an error response.

## 2. Block Responsibilities

| Block | Responsibility |
|---|---|
| `axi_if` | Typed five-channel interface with manager/subordinate modports |
| `axi_interconnect` | Independent read/write arbitration, decode, burst route locking, and DECERR termination |
| `axi_mgr` | Demonstration command adapter that emits one-beat INCR transactions |
| `axi_sub` | Interface wrapper for the flat-port RAM core |
| `axi_ram` | Burst address generation, memory access, request validation, and response generation |
| `axi_protocol_checker` | Backpressure stability and known-last-beat assertions |
| `axi_top` | Parameterized integration example with N adapters and N RAM targets |

## 3. Interconnect Microarchitecture

### Independent datapaths

The write path uses `W_IDLE → W_DATA → W_RESP`. The read path uses `R_IDLE → R_DATA`. Because these state machines are independent, a read burst and a write burst can progress concurrently, including to the same subordinate when the target accepts both channels.

### Arbitration

Read and write address channels each have a round-robin pointer. In an idle state, the arbiter scans managers beginning at that pointer and selects the first valid request. The pointer advances after address acceptance. Route ownership is then held until `BVALID && BREADY` for writes or `RVALID && RREADY && RLAST` for reads.

This policy guarantees transaction integrity and prevents channel interleaving. It is fair under the assumption that every accepted transaction eventually completes. There is one globally active write and one globally active read, so response reordering is unnecessary.

### Address decode

Subordinate `s` owns:

```text
BASE_ADDR + (s << S_ADDR_WIDTH)
    through
BASE_ADDR + ((s + 1) << S_ADDR_WIDTH) - 1
```

The default `BASE_ADDR=0` and `S_ADDR_WIDTH=16` produce 64-KiB contiguous windows. A request outside all configured windows is accepted by the interconnect and completed locally:

- Write: consume the number of W beats declared by AWLEN, then return `BRESP=DECERR` and the original AWID.
- Read: generate `ARLEN+1` zero-data beats with `RRESP=DECERR`, the original ARID, and correctly placed RLAST.

This avoids deadlock on decode misses.

## 4. AXI RAM Behavior

The RAM accepts one write address transaction and one read address transaction concurrently. Write data is accepted after AW; AXI permits this legal backpressure policy. Responses preserve their transaction IDs.

### Burst address generation

- **FIXED:** every beat accesses the starting address.
- **INCR:** each beat advances by `2^AxSIZE` bytes.
- **WRAP:** increment within the aligned `(AxLEN+1) × 2^AxSIZE` boundary and wrap to its base.

The target validates:

- bus-width transfer size
- beat-aligned start address
- legal burst encoding
- FIXED maximum of 16 beats
- WRAP lengths of 2, 4, 8, or 16 beats
- no INCR crossing of a 4-KiB boundary
- complete transaction range inside implemented memory
- WLAST position matching AWLEN

Request validation failures return `SLVERR`. Decode failures remain the interconnect’s responsibility and return `DECERR`.

### Memory inference

Storage writes are isolated in a reset-free clocked process. This allows synthesis to retain the array as a memory (the default configuration reports one 32-Kbit memory) rather than converting it to resettable flip-flops. Simulation initializes the behavioral array to zero for deterministic regression; production SRAM contents after reset are intentionally unspecified.

## 5. Reset

Control and channel-valid state uses active-low asynchronous assertion (`ARESETn`). The environment must deassert reset synchronously to ACLK. Reset cancels in-flight control state and clears generated response valid signals; it does not reset inferred hardware memory contents.

## 6. Parameterization

| Parameter | Default | Meaning |
|---|---:|---|
| `NM` | 3 in `axi_top` | Manager port count |
| `NS` | 3 in `axi_top` | Subordinate port count |
| `ADDR_W` | 32 | Address width |
| `DATA_W` | 32 | Data width; power of two, 32–1024 |
| `ID_W` | 4 | Transaction ID width |
| `S_ADDR_WIDTH` | 16 | Log2 bytes per subordinate decode window |
| `MEM_BYTES` | 4096 | Implemented bytes per RAM target; power of two |

Elaboration assertions reject invalid interface and memory configurations.

## 7. Ordering and Throughput

- At most one active write transaction globally.
- At most one active read transaction globally.
- Reads and writes may overlap.
- Bursts are never interleaved.
- Responses preserve request order because there is only one active transaction in each direction.
- Peak accepted data throughput after arbitration is one W beat and one R beat per cycle when endpoints remain ready.

## 8. Deliberate Limitations

The design does not support multiple outstanding transactions, out-of-order completion, narrow/unaligned transfers, exclusive accesses, cache attributes, QoS, protection-domain enforcement, CDC, ECC, or AXI5 extensions. These are explicitly excluded rather than silently ignored.

A higher-throughput successor would use per-subordinate arbiters, skid buffers, ID widening/remapping, outstanding scoreboards, and independent response arbitration.
