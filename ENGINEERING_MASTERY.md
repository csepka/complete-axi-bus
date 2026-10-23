# Engineering mastery: the implemented AXI4 interconnect

This guide describes the code in this repository, including its restrictions.
Read [architecture](docs/architecture.md), [verification](docs/verification.md),
[measured comparison](docs/architecture_comparison.md), and
[100 Gb/s analysis](docs/performance_100g.md) alongside it. The original design is
preserved at `v1.0.0` (`2ec5059cf00b51b40ee441fab273f5a2d1d8f462`).

## 1. First principles

A bus transaction transfers information between independently paced components.
A manager initiates a request; a subordinate accepts it and returns a response.
An interconnect must preserve information, select the correct destination, return
the response to its origin, and avoid granting resources in inconsistent orders.

AXI separates a write into address (AW), data (W), and completion (B), and a read
into address (AR) and data/completion (R). A burst has one address transaction and
multiple data beats. `AxLEN+1` is the beat count; `AxSIZE` encodes bytes per beat as
`2^AxSIZE`; `AxBURST` specifies address progression. WLAST/RLAST mark final beats.
A write response describes the whole write burst, not each beat. Read status is
present on every R beat.

A transfer occurs only at a rising ACLK edge with both VALID and READY high.
VALID alone is an offer, not a transfer. A source must retain VALID and payload
while waiting. A sink may withhold READY. Ownership changes and counters advance
only on handshakes; sampling an offer twice must not duplicate a transaction.

Channels are independent. W may be offered before AW, but this fabric legally
withholds WREADY until it has an accepted and dispatched AW. AXI4 has no WID in
this interface: a manager's W sequence must follow its accepted AW order. Reads
and writes have independent progress and no implied ordering across directions.

An **outstanding** request has been accepted but has not completed at the manager
interface. An **executing** request has been dispatched toward a target. A **queued**
request can be outstanding without executing. Confusing these concepts leads to
incorrect performance and ordering claims.

## 2. Architectural decisions

The baseline had one read and one write arbiter globally. A read from RAM 0 could
block a different manager's read from RAM 1 even though the memories were independent.
The upgrade reuses that arbiter per subordinate, removing the global bottleneck.
Per-manager address queues accept bursts of requests independently of target service.

The central restriction is one executing head per manager per direction. The
manager's next request cannot issue until the current response is consumed. This
conservatively preserves all response ordering, including same-ID ordering across
different targets. Different managers can still use different targets concurrently.

This policy deliberately trades some single-manager parallelism for smaller state
and a tractable correctness argument. It avoids a global ID remap table, per-ID
reorder logic and response arbitration among several simultaneously active targets
for one manager. `MAX_OUTSTANDING=4` is real acceptance capacity, not a claim of four
simultaneously executing transactions from that manager.

An optional registered boundary decouples the target's combinational paths. It is
disabled by default because simulation shows latency/throughput cost and no
technology-specific timing improvement has been measured.

## 3. Module-by-module understanding

### `axi_if`: the signal contract

**Purpose/interfaces:** parameterized bundles for AW/W/B/AR/R and manager/subordinate
modports. Address, data and ID widths propagate to every attached block. The strobe
width is DATA_W/8. There is no storage, arbitration or timing element.

**Design decisions/corners:** interface assertions reject unsupported widths. LOCK,
CACHE, QOS, REGION and USER are absent. PROT exists and is transported, but the RAM
does not enforce it. An interface describes wiring directions; it does not make a
connected design protocol-correct. Verification attaches separate checkers.

### `axi_request_queue`: acceptance and ordered execution

**Purpose/interfaces:** one instance per manager, with upstream subordinate and
downstream manager interfaces. Independent AW/AR FIFOs store address, PROT, ID,
LEN, SIZE and BURST. There is no W or R burst-sized data store.

**State:** `wq/rq`, head/tail pointers `wh/wt/rh/rt`, counts `wc/rc`, address-dispatched
flags `w_sent/r_sent`, write-data-complete flag `w_done`, and 9-bit `wleft`.
Pointers explicitly wrap at MAX_OUTSTANDING-1, including non-power-of-two depths.

**Datapath/control:** AxREADY depends on reset and available slots. Accepted requests
write the tail. The head's address payload is continuously presented, with VALID
only when occupied and not sent. W passes through only for a sent, incomplete head.
After AWLEN+1 W handshakes, W is blocked until B retirement. B is visible only for a
sent/data-complete head. R is visible only after AR dispatch. Retirement advances
the head and releases the slot; concurrent push/pop leaves occupancy unchanged.

**Timing/arbitration:** request acceptance is registered, adding a startup cycle.
The queue itself does not arbitrate among targets. A queued successor removes the
empty-queue admission bubble after retirement, but cannot bypass its predecessor.
A full queue does not accept a same-cycle replacement on pop, avoiding a
response-to-address READY combinational path.

**Tradeoffs/corners:** retaining the slot through B/R consumption pins its address,
so target selection and return routing stay stable during backpressure. Payload
RAMs are unreset, with counts/pointers reset. Equal IDs do not collapse entries.
Malformed WLAST does not change the declared beat count; endpoint validation
reports the error. The raw payload representation uses packed vectors because a
stock-Yosys frontend misinterpreted an unpacked array of packed structs.

**Verification/performance:** full queues, wraparound depths 1/3/4/5, overlapping IDs,
changing targets, errors and reset are directed-tested. SVA checks bounds and
retirement ownership. Synthesized queue netlists run in the same testbench. More
depth improves admission and removes some bubbles, but raises buffering and queue
latency; it does not change target bandwidth.

### `axi_interconnect`: topology and routing

**Purpose/interfaces:** NM manager interfaces and NS target interfaces. It instantiates
manager queues, decodes their head addresses, builds manager-to-target links, and
instantiates NS real arbiters plus one error arbiter.

**State/datapath/control:** its ownership state lives in child modules. Per-manager
`wselect/rselect` choose which target receives address/data/response-ready signals
and which target supplies return channels. Payload fields fan out structurally;
VALID and READY routing gates determine the actual participant. The selected
address remains the queue head until completion.

**Timing/decisions:** per-target arbitration replaces global serialization. Crossbar
fanout and return selection grow with NM and NS; this is not a constant-cost
architecture. Decode subtracts BASE_ADDR, shifts by the window size, bounds-checks
the slot, and maps misses to index NS. Widened arithmetic validates map extent.

**Corners/verification:** nonzero base, below-base and above-map errors, asymmetric
port counts, overlapping IDs and same-target contention are exercised. Independent
target progress is explicitly asserted by observed simultaneous data handshakes.
Only legal supported parameter combinations are claimed as tested.

### `axi_target_arbiter`: scheduling and route ownership

**Purpose/interfaces:** reused baseline arbitration block, with NM inputs and one
real output per instance. A FORCE_DECERR instance consumes/generates local errors.
The inherited generic endpoint-array form is retained for incremental reuse.

**State:** write FSM `W_IDLE/W_DATA/W_RESP`, read FSM `R_IDLE/R_DATA`, independent
round-robin pointers, owners, selected targets, decode-error flags/IDs, beat counters,
and held-address-grant state. These are independent per target and direction.

**Datapath/control:** idle arbiters scan from their RR pointers. A selected stalled
address retains its owner and route. Address handshake records ownership and advances
the fairness pointer. W is selected exclusively from its owner until the declared
beat count finishes. B goes only to that owner. R follows its recorded owner until
an accepted RLAST. With decode failure, the same lifecycle services local DECERR.

**Timing/decisions:** fairness is transaction-granular, not byte-granular. A 256-beat
burst occupies a target longer than a single beat. Pointer advancement on address
acceptance avoids repeatedly selecting the last winner at the next idle opportunity.
Ownership extends through response acceptance, so a slow sink holds the target.

**Corners/verification:** held grants prevent payload changes when new contenders
arrive under stall. Conditional fairness requires cooperating sources/sinks/targets;
there is no finite bound if any owner stalls forever. The retained burst tests and
new directed/saturated hotspot tests verify observable routing, integrity and
bounded completion under the test environment's finite delays.

### `axi_channel_fifo`: a registered channel boundary

**Purpose/interfaces:** generic WIDTH-bit ready/valid payload channel with two entries.
This is not AXI-specific and does not interpret IDs, lengths or LAST.

**State/datapath/control:** two payload entries, one-bit head/tail pointers, two-bit
occupancy. Push/pop toggle the corresponding pointer; occupancy changes only when
exactly one occurs. Output payload is selected from stored head data. In-ready
requires count<2; out-valid requires count>0. Reset clears only control.

**Timing/decisions:** there is no combinational in-valid/payload to output path and
no out-ready to in-ready path. At occupancy one, enqueue and dequeue can happen
simultaneously every cycle. At occupancy two, the first pop cannot also push; this
recovery bubble buys a READY boundary without lookahead. Empty insertion costs one
cycle. FIFO ordering is independent of the transaction ordering implemented above.

**Corners/verification:** empty pop and full push are prevented by handshakes.
Payload is stable under output stall even while the spare slot accepts another
item. Reset discards buffered values. A separate seeded scoreboard compares 5,455
payloads and requires observations of empty/full/both/stall/reset-full cases. SVA
checks occupancy and output stability.

### `axi_register_slice`: five independent channel stages

**Purpose/interfaces:** upstream AXI subordinate interface and downstream manager
interface, optional ENABLE. AW/W/AR flow downstream; B/R flow upstream.

**State/datapath/control:** ENABLE=1 instantiates five channel FIFOs. AW/AR pack all
implemented address fields; W packs DATA/STRB/LAST; B packs RESP/ID; R packs
DATA/RESP/ID/LAST. ENABLE=0 is direct structural wiring. The slice does not own or
interpret transactions and does not remap IDs.

**Timing/tradeoffs:** stages isolate both directions at the target boundary.
Independent channels can advance at different times. The target arbiter still owns
the transaction while responses reside in buffers. The extra address/response
latency particularly penalizes short bursts. Default bypass avoids that cost when
no technology timing requirement justifies it.

**Corners/verification:** AW buffered ahead of W, W buffered before target acceptance,
stalled B/R, and simultaneous reset of ownership and buffers are legal cases. The
directed outstanding bench and randomized benchmark run enabled. A Yosys-lowered
slice is substituted into the same directed test. Storage is measured separately
from any unmeasured full-fabric area/timing.

### `axi_ram`: burst validation and memory service

**Purpose/interfaces:** flat AXI ports, one read and one write concurrently, byte
strobes and per-burst validation. `axi_sub` provides its interface wrapper.

**State/datapath:** write-active/address/ID/length/size/burst/error/remaining-beats;
read-active/address/length/size/burst/error/remaining-beats; registered B and R outputs;
unreset memory. Byte merging combines WDATA with preserved bytes where WSTRB=0.
Read data is registered and held while stalled.

**Control/arbitration:** independent read/write processes; no multi-manager arbitration
inside RAM. AW is accepted only if no write/B is pending; AR only if no read/R is
pending. W is accepted after AW. Address generation implements FIXED, INCR and WRAP.
Widened extent calculations preserve carries that a bare ADDR_W sum could lose.

**Corners/decisions:** supported size equals the bus width; addresses must be aligned.
INCR cannot cross 4 KiB; WRAP must have legal power-of-two length; all bytes must
fit MEM_BYTES. Invalid requests still complete with SLVERR. WLAST errors may leave
partial modifications, so they are not transactional rollback. Simulated same-edge
read/write to one word observes old data; a physical macro wrapper needs a matched
contract. Simulation zero initialization is not hardware memory reset.

**Verification/performance:** retained burst, strobe, error, carry and randomized
models test it. Coarse Yosys synthesis retains memory and separately reports control
FF bits. No SRAM macro, ECC, timing closure or physical area is supplied.

### `axi_sub`: interface adaptation

This module contains no transaction state. It wires an `axi_if.sub` to `axi_ram`'s
flat ports and propagates dimensions, memory capacity and local address width.
PROT is not connected to a RAM protection mechanism. It adds no cycles and performs
no arbitration. The integration and direct-AXI benches verify its wiring; RAM
synthesis is possible independently because RAM itself has flat ports.

### `axi_mgr`: demonstration command adapter

It accepts one command while IDLE, saves its address/data, and emits a single-beat
INCR transaction with fixed MANAGER_ID. For writes, separate aw_sent/w_sent flags
track the independent address and data handshakes before waiting for B. Reads move
through READ_ADDR/READ_DATA. Outputs are driven from saved values so external
command changes cannot change a stalled AXI transfer.

The adapter is intentionally not a high-throughput source and does not exercise
multiple outstanding requests. `tb_top` checks command behavior. Performance tests
bypass it and directly drive AXI ports.

### `axi_top`: serial subsystem demonstration

It instantiates NM demonstration managers, the interconnect and NS RAM wrappers.
`command_active/active_mgr` pin the selected command manager until completion, so
changes in mgr_sel cannot redirect a pending result. Invalid manager selection is
rejected by cmd_ready. Read/write commands share the single command interface.

Consequently, fabric concurrency cannot be inferred from command throughput.
The original integration bench remains valuable for wiring/selection correctness;
direct benchmark benches measure the actual interconnect.

### `axi_protocol_checker`: assertions, not certification

This stateless monitor uses sampled history to check channel VALID/payload stability
under backpressure and known LAST fields. It is attached externally and, under
AXI_INTERNAL_CHECKS, to internal dispatch/target links. It does not prove address
legality, ordering, ownership, fairness or end-to-end data integrity; independent
scoreboards and directed tests cover those properties by simulation. Two-state
simulation also limits the significance of unknown-value assertions.

## 4. Transaction walkthroughs and timing

The tables use rising-edge numbers. Assume reset is released, no contention or
backpressure, READY high, one-beat transactions, and no previously queued work.
Payload becomes visible after the preceding edge's sequential updates. These are
architectural examples, not STA waveforms.

### Read: queue, target and response

| Edge | Pipeline off | Pipeline on |
|---:|---|---|
| E0 | Manager AR accepted into queue | Manager AR accepted into queue |
| E1 | Queue head AR accepted by target; owner recorded | Head AR accepted into AR slice; owner recorded |
| E2 | Manager accepts RAM R; queue/owner retire | Target accepts AR from slice; produces R |
| E3 | Next queued head may issue | R slice accepts RAM response |
| E4 | — | Manager accepts buffered R; queue/owner retire |

For a full-rate N-beat read, pipeline-off final completion is E(N+1); the optional
address/response stages add two cycles in this uncontented case. READY stalls move
completion later without changing RID/data/LAST for an already presented beat.

### Write: AW order controls a channel without WID

| Edge | Pipeline off | Pipeline on |
|---:|---|---|
| E0 | Manager AW accepted | Manager AW accepted |
| E1 | Target AW handshake; write owner acquired | AW enters slice; arbiter owner acquired |
| E2 | W accepted by RAM; B becomes valid | Target takes AW; W enters its independent slice |
| E3 | Manager accepts B; head retires | Target accepts W; RAM produces B |
| E4 | Next queued head may issue | B enters response slice |
| E5 | — | Manager consumes B; head retires |

Even if AW for transaction B was accepted at the manager port while transaction A
was active, W for B cannot pass until A's response retires. This is conservative
but removes ambiguity about which downstream target consumes each W beat.

### Stalled grant and unrelated target progress

```text
Manager 0:  AR(target 0) accepted -> target 0 stalled ........ -> completes
Manager 0:  AR(target 1) accepted -> waits behind same head ... -> issues later
Manager 1:  AR(target 1) accepted -> issues -> completes
Manager 2:  AW(target 2) accepted -> W burst -> B completion
```

A held target-0 address grant is immutable while stalled. The queued manager-0
request cannot bypass it, but managers 1/2 use independent target/direction state.
The directed test deliberately completes unrelated work while manager 0's queues
are full and verifies those completions do not release manager 0's slots.

### FIFO elasticity

```text
Before edge    Input offer  Sink ready  Push  Pop  After edge
empty (0)          1           1         1     0     one (1)
one (1)            1           1         1     1     one (1)
one (1)            1           0         1     0     full (2)
full (2)           1           1         0     1     one (1)
one (1)            1           1         1     1     one (1)
```

The full-to-one cycle has an input bubble even though the sink is ready. Output
still transfers. This is not data loss: the input source keeps its offer stable.

### Decode miss and reset

A missed AW still creates an outstanding write. The error arbiter drains the
specified number of beats, then emits BID/AWID with DECERR. A missed AR emits the
specified number of zero-data DECERR beats. Errors obey the same queue ordering.

Reset clears queue occupancy, dispatched flags, arbiter ownership and pipeline
occupancy. Responses for canceled requests do not appear later. Memory writes
that already happened are not undone; data buffered but not written is discarded.
Software/system logic must reinitialize transaction state after reset.

## 5. Reasoning about performance and implementation

For DATA_W bits, bytes per beat are DATA_W/8. One path at clock f can theoretically
carry DATA_W*f bits/s. The useful-direction fabric ceiling is min(NM,NS) such paths.
Full-duplex aggregate adds read and write rates; it must not be compared directly
to a single-direction link requirement without explaining the distinction.

Measured bandwidth counts successful data handshakes over a finite interval that
includes startup/drain. Address and response bubbles reduce sustained rate,
especially for short bursts. Backpressure reduces it further. Queuing moves waiting
inside the fabric, so accepted-request latency can increase even while total work
finishes faster. Compare offered latency, accepted latency, occupancy and total
completion cycles together.

At 8x8/256 with 16-beat independent full-duplex traffic and 32 requests per manager
per direction, baseline/depth1/depth4/pipelined-depth4 take 4608/608/577/641 cycles.
At an assumed 100 MHz, the default improved fabric produces 45.432 GB/s aggregate.
This is cycle-accurate simulated performance scaled by a clock assumption. It is
not achieved hardware Fmax. See the dedicated 100 Gb/s report for direction-specific
values and required-frequency calculations.

Coarse synthesis counts operators, FF bits and memory bits; it does not give
technology area. A request queue's storage and a target slice's storage are measured
in isolation. The entire fabric still requires an interface-capable synthesis
frontend. Critical paths through decode, RR selection, routing and READY are
architectural candidates, not measured STA paths. Adding register slices removes
cross-boundary combinational dependence but does not prove timing closure.

## 6. Debugging methodology

1. Reproduce the exact seed/configuration and locate the first failed handshake,
   not merely the final mismatched value.
2. Track an accepted AW/AR from manager queue slot to target grant and owner.
3. Confirm W routing uses AW order and that counters change only on handshakes.
4. Compare B/R ID, target and owner; inspect stalled payload stability.
5. Distinguish queue-full waits, target arbitration waits and endpoint stalls.
6. For reset failures, inspect occupancy/ownership on both sides of every buffer.
7. For synthesis anomalies, inspect storage widths and remaining processes; parsing
   successfully is insufficient. Substitute the generated netlist into a scoreboard.
8. Preserve the first failing log and rerun the smallest relevant case before the
   broader suite. Never hide a warning globally just to obtain a green run.

## 7. ASIC/SoC interview questions and grounded answers

### 1. Why can the upgraded design complete independent reads concurrently?
Each real target has its own read owner and FSM. Requests from different managers
to different targets do not contend for a global read state machine.

### 2. Does MAX_OUTSTANDING=4 mean four executing reads per manager?
No. It permits four accepted, uncompleted reads, including the one executing head.
The remaining entries wait until earlier responses are consumed.

### 3. Why are equal IDs from different managers safe?
The target arbiter records a manager owner independently of the external ID. Return
routing uses ownership, while RID/BID retain the original ID.

### 4. How is same-ID ordering across different targets enforced?
A manager's next head cannot dispatch until the current response retires. This
serializes different targets for that manager and direction regardless of ID.

### 5. What opportunity does strict head issue sacrifice?
A slow target blocks that manager's later requests even if they use another target
or a different ID. The policy simplifies correctness at the cost of that parallelism.

### 6. Why is write ordering harder than read ordering here?
W has no ID field. A downstream W stream must be associated with accepted AW order,
so arbitrary address dispatch or data interleaving would misroute write beats.

### 7. Why retain an AW queue entry after its final W beat?
The retained head pins the target until B is consumed and preserves write response
order. Releasing it earlier would require separate response tracking.

### 8. What event frees a read slot?
An upstream RVALID&RREADY&RLAST handshake. Merely producing RLAST or placing it in
a pipeline buffer does not complete the manager-visible transaction.

### 9. What happens when a full queue pops and a new address is offered together?
AxREADY remains low for that cycle because occupancy was full. The next cycle can
accept the offer; this avoids combinational dependence on the returning response.

### 10. How do non-power-of-two queue depths work?
Pointers compare against MAX_OUTSTANDING-1 and explicitly wrap to zero. Natural
binary overflow alone would visit invalid entries for depth three or five.

### 11. Why is a 9-bit beat counter required?
AxLEN is eight bits but encodes length minus one. AxLEN=255 represents 256 beats,
which cannot be represented as an eight-bit remaining count.

### 12. Why can a manager offer W before AW?
Channels are independent. This fabric waits to assert WREADY until the matching AW
head has dispatched, so an early W offer is held without ambiguity.

### 13. Why lock an address grant under backpressure?
A newly arriving requester must not change AW/AR payload while the existing VALID
is stalled. The held-grant registers preserve the selected owner and route.

### 14. When does the round-robin pointer advance?
On accepted address transfer. The next arbitration opportunity begins after that
winner, while the current owner remains locked through transaction completion.

### 15. Does round-robin guarantee equal byte bandwidth?
No. It is transaction-granular. A long burst consumes more target cycles than a
short burst even when managers receive equal numbers of grants.

### 16. What assumptions are needed for fairness?
Owners must eventually send required W data, targets must respond, and sinks must
eventually accept responses. Indefinite stalls defeat a finite completion bound.

### 17. Can a stalled B response affect reads?
It retains write ownership for that target and manager direction. Independent read
state can still progress, subject to the subordinate's own read capability.

### 18. Can a stalled read affect another manager's different-target read?
There is no shared read owner across real targets, so the other target can progress.
The directed full-queue test specifically exercises unrelated completion.

### 19. Why is a separate DECERR target useful?
It reuses the ownership/completion machinery for misses and prevents erroneous
requests from consuming a real target's arbitration state.

### 20. What is the throughput limitation of that error target?
All decode-miss reads contend with each other, and all decode-miss writes contend
with each other. It is shared service, not one error engine per manager.

### 21. How does a decode-miss write finish without reaching RAM?
The error arbiter consumes AWLEN+1 W handshakes and then returns DECERR with the
captured AWID. It cannot finish if the source never supplies the declared data.

### 22. Why preserve absolute addresses through the fabric?
The targets receive the original request address; RAM extracts the local low bits.
Window-aligned BASE_ADDR makes that extraction consistent with the decode map.

### 23. What arithmetic bug did the audit identify in map validation?
Host-sized shifts could overflow and the old check ignored BASE_ADDR extent.
The interconnect now uses widened arithmetic for the full address map end.

### 24. Why are narrow transfers rejected rather than silently handled?
Correct narrow transfers require lane selection, address/size semantics and
additional verification. This implementation explicitly supports full-width only.

### 25. How are byte strobes different from narrow transfers?
A full-width transaction can update selected bytes using WSTRB. Narrow AxSIZE
changes transfer size/address semantics; the RAM rejects that separate feature.

### 26. Why is WRAP length restricted?
Legal implemented WRAP lengths are 2/4/8/16, producing a power-of-two wrap region.
The RAM validates length before servicing the burst and computes its aligned base.

### 27. How does the scoreboard avoid simply copying the RTL WRAP algorithm?
The original burst model computes the wrap base using division, while RTL uses
masking. Independent formulations help detect implementation mistakes.

### 28. Why is burst endpoint arithmetic wider than ADDR_W?
A legal-width start plus a large burst can overflow ADDR_W. Keeping carry lets
validation reject an out-of-range burst instead of accepting its wrapped endpoint.

### 29. Is SLVERR on malformed WLAST an atomic write abort?
No. Prior beats and potentially the detection beat can already modify memory.
The interface promises error reporting, not rollback.

### 30. What happens if WLAST is early but the source keeps sending declared beats?
The RAM records an error and the fabric continues using AWLEN to determine the
route's data lifetime. The eventual response reports SLVERR for the malformed write.

### 31. Why are payload arrays not reset?
Zero occupancy and reset ownership make their contents invalid. Resetting every
payload bit would add hardware cost and can obstruct memory inference.

### 32. What survives reset?
Previously committed memory writes survive because RAM storage is unreset. Queue,
owner and slice control is canceled; buffered uncommitted data may be discarded.

### 33. Why must reset cover managers, fabric and subordinates consistently?
If one side retains a transaction while another forgets its owner, later data or
responses can be orphaned or misinterpreted. Reset is a system-level contract.

### 34. What is required for reset deassertion?
The integration environment must synchronize it to ACLK. The RTL uses asynchronous
assertion; it does not supply a reset synchronizer or reset-domain signoff.

### 35. Why use two entries for a registered channel boundary?
One entry with READY based only on registered empty/full state would alternate
fill/drain under continuous traffic. Two entries permit simultaneous push/pop at
occupancy one while keeping READY independent of downstream READY.

### 36. Does the two-entry FIFO always accept a beat when the sink does?
No. When full, it pops without pushing on the first recovery cycle. The source
must retain its offer until READY rises again.

### 37. Can a stalled output payload change when the FIFO accepts another input?
No. The head remains fixed until pop; a spare tail slot receives the new item.
The output-stability assertion and independent FIFO scoreboard verify this.

### 38. Why buffer AW and W independently?
AXI channels are independently paced. The target must tolerate their relative
arrival timing using READY; the slice preserves each channel's order separately.

### 39. Can the target finish a response before the manager sees it with pipelining?
Yes. B/R may sit in a return FIFO. The arbiter still retains its owner until that
buffered response is consumed upstream.

### 40. Why is TARGET_PIPELINE disabled by default?
It adds transaction cycles and storage. Its structural timing boundary is useful,
but no technology-specific critical-path result establishes an Fmax benefit yet.

### 41. What measurable effect does the pipeline have on the main 8x8 test?
For the specified 16-beat independent full-duplex run, it increases completion
from 577 to 641 cycles. It remains correct but reduces throughput at the same clock.

### 42. Why is the command demo unsuitable for performance measurement?
`axi_top` allows one command active at a time, and `axi_mgr` emits single-beat
transactions. That source bottleneck hides fabric parallelism and queue capacity.

### 43. How is measured bandwidth computed?
Count successful W/R handshakes, multiply by bytes per beat, divide by elapsed
cycles and scale by an explicitly assumed clock. VALID-only cycles do not count.

### 44. Why distinguish GB/s from Gb/s?
A byte contains eight bits. Network-style 100 Gb/s equals 12.5 GB/s; failing to
convert would overstate or understate the comparison by eight times.

### 45. Why distinguish aggregate from single-direction bandwidth?
Summing read and write rates can exceed 100 Gb/s while neither direction does.
A single-direction requirement must be checked using that direction's own bytes.

### 46. Is simulation at an assumed 100 MHz evidence of 100 MHz timing closure?
No. Cycle-accurate RTL simulation has no technology/path delays. Mapped STA and
physical implementation are needed to establish an achievable clock.

### 47. Why can accepted-request latency grow after adding queues?
Addresses are accepted earlier and wait inside the fabric. The accepted-to-complete
interval includes that waiting even if aggregate completion time improves.

### 48. What does offered latency add?
It also includes the wait from the first stable address offer until acceptance.
Comparing both metrics avoids rewarding a design merely for moving backpressure.

### 49. Why measure average outstanding occupancy as well as peak?
Peak proves that capacity can be exercised but says little about sustained use.
Time-averaged accepted-minus-completed occupancy shows how much buffering the
workload actually uses.

### 50. Does an 8x8 crossbar produce an eightfold hotspot speedup?
No. A hotspot still uses one target's read/write service. The measured independent
speedup comes from target parallelism, not multiplying one target's capacity.

### 51. Why were the baseline synthesis counts misleading?
Yosys `synth -run begin:coarse` stopped before the coarse label. Logs still contained
behavioral processes, so the old numbers described elaboration rather than lowered
synthesis. The corrected flow uses `begin:fine` and structural checks.

### 52. What does a generic cell count actually mean?
It counts technology-independent operators, not equivalent NAND gates or physical
area. A wide mux and a small gate can each contribute one coarse cell.

### 53. How was the queue synthesis frontend problem detected?
The apparent synthesized storage was too small for the configured depth. Explicit
packed vectors fixed the struct-array interpretation, and netlist simulations plus
storage-capacity checks verified the result.

### 54. Why simulate the generated netlist in the same directed bench?
It checks whether synthesis preserved observable behavior under ordering, stalls,
errors and reset. Successful parsing or a plausible area number alone cannot do that.

### 55. Why is full-fabric synthesis still a limitation?
The installed Yosys frontend cannot elaborate internal interface arrays and has no
slang plugin. Isolated RAM/queue/slice synthesis must not be presented as complete
fabric synthesis or timing evidence.

### 56. Do 8,016 default numeric checks mean full coverage?
No. They include 418 integration, 1,618 burst, 525 outstanding and 5,455 FIFO payload
comparisons, often repeated conditions. Requirements coverage, code coverage and
formal proofs are separate forms of evidence.

### 57. What can stability SVA fail to detect?
A stable but incorrectly routed or corrupted payload may satisfy the assertions.
End-to-end data/ID/reference-model checks are needed as well.

### 58. What does two-state simulation leave unproven?
It cannot establish robust X-propagation behavior or comprehensive unknown-signal
handling. Known-LAST assertions in Verilator do not replace four-state signoff.

### 59. How would you safely allow several executing targets for one manager?
Introduce issue/ownership records beyond one head, track same-ID ordering domains,
retain an AW-order W issue queue, arbitrate B/R with stalled-output locks, and size
response resources to avoid circular waits. Then add independent reordering and
resource-exhaustion tests before claiming the feature.

### 60. What is the next defensible optimization step?
Use the archived extracted paths and cell-area reports to select an optimization,
then compare equivalent traffic, constraints and configurations. The reference
flow now exists; it does not yet establish a pipeline Fmax benefit. Investigate
hold-buffer cost and manager-to-target routing before changing proven ownership
logic. Retain improvements only after regression and physical remeasurement.

### 61. Why is interface-array synthesis different from flattening external ports?
The flat wrapper only concatenates/splits signals. Internal `axi_if` instances and
modports remain SystemVerilog objects until an interface-capable frontend expands
them. Native `read_slang` performs that elaboration; subsequent Yosys lowering
must leave no processes, latches, blackboxes or combinational SCCs.

### 62. What exactly does the mapped area comparison include?
The reported standard-cell area includes functional gates, queue/slice storage,
clock buffers and timing-repair buffers. It excludes filler and is distinct from
the 250 x 250 um small-design die. The 2x2 upgraded configuration costs about
10.81x the original baseline here; that combines multiple architectural features
and repair costs under these constraints. It is not a universal area multiplier.

### 63. Why can a slow requested clock still require many hold buffers?
Hold checks constrain the earliest data arrival relative to the capture edge.
A longer clock period does not generally cure a same-edge hold failure. Short
feedback paths, clock skew and 0.2 ns hold uncertainty led to substantial buffering
in this flow. The repair budget was enlarged while constraints stayed unchanged.
That cost must appear in the area report.

### 64. What does +7.27049 ns setup slack prove at a 10 ns clock?
For the specific 2x2 layout, typical library corner and stated I/O assumptions,
the extracted setup check passes with that margin. Hold independently passes with
+0.0278701 ns. Neither number proves multi-corner signoff, an optimized Fmax, reset
recovery/removal, or the timing of the larger fabric and attached memories.

### 65. Why are router DRC and KLayout results both necessary?
They use different geometry abstractions and rules. The 2x2 router reports zero
errors, while KLayout finds four antenna markers in final GDS. One marker contains
multiple diagnostic values, so counting XML values produced a misleading 28.
The collector counts items. Neither result can replace LVS connectivity checks.

### 66. Why does a passing routed-netlist test not prove layout connectivity?
The simulator reads a logical netlist and zero-delay cell models. It cannot see
an open or short introduced by layout geometry. LVS extracts connectivity from
layout and compares it with the intended circuit. The pinned reference platform
has no configured LVS deck, so that check remains unavailable, not passed.

### 67. Why use an independent byte oracle as well as write/read loopback?
A fabric that consistently routes both writes and reads to the same wrong target
can pass loopback. The independent suite inspects the selected external RAM's
bytes directly after writes and compares reads with separately retained expected
data. Disjoint address regions prevent legitimate concurrent overwrites from
making expected values ambiguous.

### 68. Can W legitimately reach a target before AW in this implementation?
Yes. The target slice buffers AW and W independently. The upstream arbiter has
already accepted the address, but downstream AW backpressure can let buffered W
arrive first. The monitor stores W beat/LAST observations until it can pair them
with AW in issue order. Requiring downstream AW first would falsely reject legal
channel decoupling.

### 69. What makes the FIFO proof inductive rather than just bounded testing?
Yosys proves a base case and an induction step with arbitrary payload/VALID/READY.
The reference queue is related to actual count, ring pointers and second stored
word by invariants. Read-only ports expose state without replacing control logic.
The result is FIFO safety at WIDTH=8 under sampled-reset assumptions. It does not
prove full-fabric liveness, analog reset behavior or every parameter value.

### 70. How should a failed optional physical check affect release claims?
Keep the usable synthesis/timing evidence but preserve the failed check and make
acceptance fail. Here antenna markers and missing LVS collateral prevent physical
acceptance. Do not disable a deck, invent process rules, substitute netlist tests,
or turn missing output into zero violations. A reference educational result can
be valuable without being a manufacturable signoff result.

## 8. What to defend in a design review

Explain the exact acceptance/issue policy before presenting throughput. Show that
responses cannot outlive their ownership records. State the fairness assumptions.
Distinguish behavioral RAM semantics from a technology macro. Present the baseline
and unfavorable hotspot/short-burst cases alongside independent-target gains.

The strongest result is a reproducible improvement with explicit bounds, not a
claim that every AXI feature or physical target has been completed. Remaining
work includes antenna closure, LVS with complete process collateral, multi-corner
signoff, full-fabric formal/coverage closure and, if justified by a workload, more
parallel dispatch per manager. Reference synthesis, extracted STA/P&R and
independent full-netlist functional tests now have archived evidence.

## 9. From RTL to the physical reference

The flow first elaborates the real fabric with a structural flat boundary, then
lowers memories/processes and maps Boolean logic into a specific Liberty library.
Floorplanning allocates a deliberately roomy die and pins; placement locates
cells; clock-tree synthesis distributes ACLK; hold/setup repair changes buffering
and drive strength; routing constructs metal connections; extraction supplies
wire parasitics for final STA. GDS and logical netlist tests answer different
questions and are retained separately.

```text
RTL/interfaces -> read_slang -> generic gates -> Liberty mapping
     |                              |                  |
 RTL BFM test                 generic BFM test    mapped BFM test
                                                        |
 placement -> clock tree + repair -> route -> extracted STA
                                              |         |
                                       routed BFM    setup + hold
                                              |
                                         GDS -> DRC / LVS
```

The BFMs drive the same flattened interface at each logical stage. Four-state
simulation permits idle payload X values but requires definite handshake controls
and meaningful payloads; reset valid/count state masks uninitialized storage.
The independent checker tracks outstanding addresses, W beat counts, response IDs
and order, including buffered W arriving before AW. Final cell models have zero
delay: they verify logic, while STA separately verifies constrained timing.

Physical results are sensitive to units and external assumptions. Nangate45 uses
fF, so a 5-fF load is `5.0`, not `0.005`. External reset is false-pathed under an
explicit synchronized-deassertion contract. The hold uncertainty is applied as
well as setup uncertainty; its buffers are a real cost of that chosen model.
A large bus also needs enough boundary pin tracks even when logic utilization is
low. These are integration decisions, not incidental tool settings.

The [physical report](synthesis/physical/README.md) records actual paths, area and
limitations. A production process would need validated antenna/LVS collateral,
all required PVT/variation corners, power integrity and endpoint integration.
