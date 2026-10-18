# Implemented AXI Signal Contract

Direction is shown from the manager perspective.

| Channel | Signal | Width | Direction | Implemented behavior |
|---|---|---:|---|---|
| Global | `ACLK` | 1 | — | Rising-edge protocol clock |
| Global | `ARESETn` | 1 | — | Active-low asynchronous assertion; synchronous deassertion required |
| AW | `AWVALID/AWREADY` | 1 | M→S / S→M | Backpressure-safe address handshake |
| AW | `AWADDR` | `ADDR_W` | M→S | Byte address |
| AW | `AWPROT` | 3 | M→S | Routed without interpretation |
| AW | `AWID` | `ID_W` | M→S | Returned as BID |
| AW | `AWLEN` | 8 | M→S | Beats minus one |
| AW | `AWSIZE` | 3 | M→S | Bytes per beat as `log2(bytes)`; only full bus width accepted |
| AW | `AWBURST` | 2 | M→S | FIXED=00, INCR=01, WRAP=10; reserved=11 rejected |
| W | `WVALID/WREADY` | 1 | M→S / S→M | Backpressure-safe data handshake |
| W | `WDATA` | `DATA_W` | M→S | Write payload |
| W | `WSTRB` | `DATA_W/8` | M→S | One enable per byte lane |
| W | `WLAST` | 1 | M→S | Must correspond to AWLEN; mismatch yields SLVERR |
| B | `BVALID/BREADY` | 1 | S→M / M→S | Persistent response handshake |
| B | `BRESP` | 2 | S→M | OKAY, SLVERR, or DECERR |
| B | `BID` | `ID_W` | S→M | Original AWID |
| AR | `ARVALID/ARREADY` | 1 | M→S / S→M | Backpressure-safe address handshake |
| AR | `ARADDR` | `ADDR_W` | M→S | Byte address |
| AR | `ARPROT` | 3 | M→S | Routed without interpretation |
| AR | `ARID` | `ID_W` | M→S | Returned on every R beat |
| AR | `ARLEN` | 8 | M→S | Beats minus one |
| AR | `ARSIZE` | 3 | M→S | Only full bus width accepted |
| AR | `ARBURST` | 2 | M→S | FIXED, INCR, or WRAP |
| R | `RVALID/RREADY` | 1 | S→M / M→S | Backpressure-safe data handshake |
| R | `RDATA` | `DATA_W` | S→M | Read payload; zero for error-generated beats |
| R | `RRESP` | 2 | S→M | Per-beat OKAY, SLVERR, or DECERR |
| R | `RID` | `ID_W` | S→M | Original ARID on every beat |
| R | `RLAST` | 1 | S→M | Asserted on final declared beat |

## Response Encoding

| Value | Name | Use in this design |
|---:|---|---|
| `2'b00` | OKAY | Successful access |
| `2'b01` | EXOKAY | Not generated; exclusive access unsupported |
| `2'b10` | SLVERR | Request reached RAM but violated its contract |
| `2'b11` | DECERR | Address did not decode to a configured subordinate |

Optional AXI4 signals such as LOCK, CACHE, QOS, REGION, and USER are not part of `axi_if`. AXI5 signals such as ATOP, POISON, MPAM, and trace are also intentionally absent.
