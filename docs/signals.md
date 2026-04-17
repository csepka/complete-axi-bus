# AXI4 Signal Reference

Full signal reference for the AXI4 Manager/Subordinate implementation.

**Direction** is always from the Manager's perspective:
- `M→S` = Manager drives, Subordinate receives
- `S→M` = Subordinate drives, Manager receives

**Status** column tracks implementation progress:
- ✅ = Present in current AXI-Lite implementation
- 🔲 = Needs to be added for full AXI4

---

## Global Signals

| Signal | Width | Dir | Status | Description |
|--------|-------|-----|--------|-------------|
| `ACLK` | 1 | — | ✅ | Rising-edge clock. All signals sampled on rising edge. |
| `ARESETn` | 1 | — | ✅ | Active-low reset. All outputs must be driven LOW while asserted. |

---

## AW — Write Address Channel

| Signal | Width | Dir | Status | Description |
|--------|-------|-----|--------|-------------|
| `AWVALID` | 1 | M→S | ✅ | Manager asserts to indicate write address is valid. |
| `AWREADY` | 1 | S→M | ✅ | Subordinate asserts when ready to accept write address. Handshake completes when both HIGH. |
| `AWADDR` | `ADDR_W` | M→S | ✅ | Start address of the write transaction. |
| `AWPROT` | 3 | M→S | ✅ | Protection type. `[2]` = instruction/data, `[1]` = secure/non-secure, `[0]` = privileged/unprivileged. |
| `AWID` | `ID_W` | M→S | 🔲 | Transaction ID. Subordinate must return matching `BID`. Enables out-of-order completion. |
| `AWLEN` | 8 | M→S | 🔲 | Burst length minus 1. Number of beats = `AWLEN + 1`. Range: 0–255 (1–256 beats). |
| `AWSIZE` | 3 | M→S | 🔲 | Bytes per beat. Encoded as `2^AWSIZE`. Must not exceed data bus width. |
| `AWBURST` | 2 | M→S | 🔲 | Burst type. `2'b00`=FIXED, `2'b01`=INCR, `2'b10`=WRAP. INCR is most common. |
| `AWLOCK` | 1 | M→S | 🔲 | Exclusive access. `0`=normal, `1`=exclusive. Used for atomic operations. |
| `AWCACHE` | 4 | M→S | 🔲 | Memory attributes. Controls bufferable, cacheable, read/write-allocate hints. |
| `AWQOS` | 4 | M→S | 🔲 | Quality of Service. Higher value = higher priority. `4'b0000` = no QoS. |
| `AWREGION` | 4 | M→S | 🔲 | Region identifier. Allows one physical interface to address multiple logical regions. |
| `AWUSER` | `USER_W` | M→S | 🔲 | User-defined sideband. Width is implementation-defined. Optional. |

---

## W — Write Data Channel

| Signal | Width | Dir | Status | Description |
|--------|-------|-----|--------|-------------|
| `WVALID` | 1 | M→S | ✅ | Manager asserts to indicate write data is valid. |
| `WREADY` | 1 | S→M | ✅ | Subordinate asserts when ready to accept write data. |
| `WDATA` | `DATA_W` | M→S | ✅ | Write data. Width must be 32, 64, 128, 256, 512, or 1024 bits. |
| `WSTRB` | `DATA_W/8` | M→S | ✅ | Write strobes. One bit per byte lane. `1`=byte is valid, `0`=byte should be ignored. |
| `WLAST` | 1 | M→S | 🔲 | Indicates the last beat of a burst. **Must** be asserted on the final data beat. |
| `WUSER` | `USER_W` | M→S | 🔲 | User-defined sideband. Optional. |

> **Note:** `WID` existed in AXI3 but was **removed in AXI4**. Do not add it.

---

## B — Write Response Channel

| Signal | Width | Dir | Status | Description |
|--------|-------|-----|--------|-------------|
| `BVALID` | 1 | S→M | ✅ | Subordinate asserts when write response is valid. |
| `BREADY` | 1 | M→S | ✅ | Manager asserts when ready to accept write response. |
| `BRESP` | 2 | S→M | ✅ | Write response. `2'b00`=OKAY, `2'b01`=EXOKAY, `2'b10`=SLVERR, `2'b11`=DECERR. |
| `BID` | `ID_W` | S→M | 🔲 | Must match the `AWID` of the corresponding write transaction. |
| `BUSER` | `USER_W` | S→M | 🔲 | User-defined sideband. Optional. |

---

## AR — Read Address Channel

| Signal | Width | Dir | Status | Description |
|--------|-------|-----|--------|-------------|
| `ARVALID` | 1 | M→S | ✅ | Manager asserts to indicate read address is valid. |
| `ARREADY` | 1 | S→M | ✅ | Subordinate asserts when ready to accept read address. |
| `ARADDR` | `ADDR_W` | M→S | ✅ | Start address of the read transaction. |
| `ARPROT` | 3 | M→S | ✅ | Protection type. Same encoding as `AWPROT`. |
| `ARID` | `ID_W` | M→S | 🔲 | Transaction ID. Subordinate must return matching `RID` on all beats. |
| `ARLEN` | 8 | M→S | 🔲 | Burst length minus 1. Number of beats = `ARLEN + 1`. |
| `ARSIZE` | 3 | M→S | 🔲 | Bytes per beat. Encoded as `2^ARSIZE`. |
| `ARBURST` | 2 | M→S | 🔲 | Burst type. `2'b00`=FIXED, `2'b01`=INCR, `2'b10`=WRAP. |
| `ARLOCK` | 1 | M→S | 🔲 | Exclusive access flag. |
| `ARCACHE` | 4 | M→S | 🔲 | Memory attributes. Same encoding as `AWCACHE`. |
| `ARQOS` | 4 | M→S | 🔲 | Quality of Service priority. |
| `ARREGION` | 4 | M→S | 🔲 | Region identifier. |
| `ARUSER` | `USER_W` | M→S | 🔲 | User-defined sideband. Optional. |

---

## R — Read Data Channel

| Signal | Width | Dir | Status | Description |
|--------|-------|-----|--------|-------------|
| `RVALID` | 1 | S→M | ✅ | Subordinate asserts when read data is valid. |
| `RREADY` | 1 | M→S | ✅ | Manager asserts when ready to accept read data. |
| `RDATA` | `DATA_W` | S→M | ✅ | Read data. |
| `RRESP` | 2 | S→M | ✅ | Read response per beat. Same encoding as `BRESP`. |
| `RID` | `ID_W` | S→M | 🔲 | Must match the `ARID` of the corresponding read transaction. Present on every beat. |
| `RLAST` | 1 | S→M | 🔲 | Indicates the last beat of a read burst. Manager uses this to count beats. |
| `RUSER` | `USER_W` | S→M | 🔲 | User-defined sideband. Optional. |

---

## BRESP / RRESP Encoding

| Value | Name | Meaning |
|-------|------|---------|
| `2'b00` | OKAY | Normal successful completion. |
| `2'b01` | EXOKAY | Exclusive access successful. |
| `2'b10` | SLVERR | Subordinate error. Transfer reached subordinate but failed. |
| `2'b11` | DECERR | Decode error. No subordinate at this address. |

---

## AWBURST / ARBURST Encoding

| Value | Name | Address Calculation |
|-------|------|---------------------|
| `2'b00` | FIXED | Address is the same for every beat. Used for FIFOs. |
| `2'b01` | INCR | Address increments by beat size each beat. Most common. |
| `2'b10` | WRAP | Like INCR but wraps at a power-of-2 boundary. Used for cache lines. |
| `2'b11` | — | Reserved. Do not use. |

---

## AWSIZE / ARSIZE Encoding

| Value | Bytes per Beat |
|-------|---------------|
| `3'b000` | 1 |
| `3'b001` | 2 |
| `3'b010` | 4 |
| `3'b011` | 8 |
| `3'b100` | 16 |
| `3'b101` | 32 |
| `3'b110` | 64 |
| `3'b111` | 128 |

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ADDR_W` | 32 | Address bus width in bits. |
| `DATA_W` | 32 | Data bus width in bits. Must be 32, 64, 128, 256, 512, or 1024. |
| `ID_W` | 4 | Transaction ID width. Determines max outstanding transactions (2^ID_W). |
| `USER_W` | 1 | User sideband width. Set to 0 to disable. |

---

## Reference

- [ARM AXI4 Specification IHI0022H](https://developer.arm.com/documentation/ihi0022/latest)
