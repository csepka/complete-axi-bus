// src/axi_lite_sub_top.sv
`timescale 1ns/1ps

module axi_lite_sub_top #(
    parameter int ADDR_W    = 32,
    parameter int DATA_W    = 32,
    parameter int ID_W      = 1,     // keep 1 for tool friendliness
    parameter int MEM_BYTES = 256    // smaller for PnR feasibility
)(
    input  logic                 ACLK,
    input  logic                 ARESETn,

    // Write address channel
    input  logic                 AWVALID,
    output logic                 AWREADY,
    input  logic [ADDR_W-1:0]    AWADDR,

    // Write data channel
    input  logic                 WVALID,
    output logic                 WREADY,
    input  logic [DATA_W-1:0]    WDATA,
    input  logic [DATA_W/8-1:0]  WSTRB,

    // Write response channel
    input  logic                 BREADY,
    output logic                 BVALID,
    output logic [1:0]           BRESP,

    // Read address channel
    input  logic                 ARVALID,
    output logic                 ARREADY,
    input  logic [ADDR_W-1:0]    ARADDR,

    // Read data channel
    output logic                 RVALID,
    input  logic                 RREADY,
    output logic [DATA_W-1:0]    RDATA,
    output logic [1:0]           RRESP
);

    // Tie-off / dummy ID signals (since AXI-Lite typically ignores IDs)
    logic [ID_W-1:0] awid_tie, arid_tie;
    logic [ID_W-1:0] bid_unused, rid_unused;

    assign awid_tie = '0;
    assign arid_tie = '0;

    axi_lite_sub #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .MEM_BYTES(MEM_BYTES)
    ) dut (
        .ACLK     (ACLK),
        .ARESETn  (ARESETn),

        .AWVALID  (AWVALID),
        .AWREADY  (AWREADY),
        .AWADDR   (AWADDR),
        .AWID     (awid_tie),

        .WVALID   (WVALID),
        .WREADY   (WREADY),
        .WDATA    (WDATA),
        .WSTRB    (WSTRB),

        .BREADY   (BREADY),
        .BVALID   (BVALID),
        .BRESP    (BRESP),
        .BID      (bid_unused),

        .ARVALID  (ARVALID),
        .ARREADY  (ARREADY),
        .ARADDR   (ARADDR),
        .ARID     (arid_tie),

        .RVALID   (RVALID),
        .RREADY   (RREADY),
        .RID      (rid_unused),
        .RDATA    (RDATA),
        .RRESP    (RRESP)
    );

endmodule