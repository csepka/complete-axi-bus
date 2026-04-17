interface axi_if #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter ID_W   = 8
) (
    input logic ACLK,
    input logic ARESETn
);

    // AW — Write Address Channel
    logic                 AWVALID;
    logic                 AWREADY;
    logic [ADDR_W-1:0]    AWADDR;
    logic [2:0]           AWPROT;
    logic [ID_W-1:0]      AWID;
    logic [7:0]           AWLEN;
    logic [2:0]           AWSIZE;
    logic [1:0]           AWBURST;

    // W — Write Data Channel
    logic                 WVALID;
    logic                 WREADY;
    logic [DATA_W-1:0]    WDATA;
    logic [DATA_W/8-1:0]  WSTRB;
    logic                 WLAST;

    // B — Write Response Channel
    logic                 BVALID;
    logic                 BREADY;
    logic [1:0]           BRESP;
    logic [ID_W-1:0]      BID;

    // AR — Read Address Channel
    logic                 ARVALID;
    logic                 ARREADY;
    logic [ADDR_W-1:0]    ARADDR;
    logic [2:0]           ARPROT;
    logic [ID_W-1:0]      ARID;
    logic [7:0]           ARLEN;
    logic [2:0]           ARSIZE;
    logic [1:0]           ARBURST;

    // R — Read Data Channel
    logic                 RVALID;
    logic                 RREADY;
    logic [DATA_W-1:0]    RDATA;
    logic [1:0]           RRESP;
    logic [ID_W-1:0]      RID;
    logic                 RLAST;

    modport mgr (
        // AW
        output AWVALID, AWADDR, AWPROT, AWID, AWLEN, AWSIZE, AWBURST,
        input  AWREADY,
        // W
        output WVALID, WDATA, WSTRB, WLAST,
        input  WREADY,
        // B
        output BREADY,
        input  BVALID, BRESP, BID,
        // AR
        output ARVALID, ARADDR, ARPROT, ARID, ARLEN, ARSIZE, ARBURST,
        input  ARREADY,
        // R
        output RREADY,
        input  RVALID, RDATA, RRESP, RID, RLAST
    );

    modport sub (
        // AW
        input  AWVALID, AWADDR, AWPROT, AWID, AWLEN, AWSIZE, AWBURST,
        output AWREADY,
        // W
        input  WVALID, WDATA, WSTRB, WLAST,
        output WREADY,
        // B
        input  BREADY,
        output BVALID, BRESP, BID,
        // AR
        input  ARVALID, ARADDR, ARPROT, ARID, ARLEN, ARSIZE, ARBURST,
        output ARREADY,
        // R
        input  RREADY,
        output RVALID, RDATA, RRESP, RID, RLAST
    );

endinterface
