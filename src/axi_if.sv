interface axi_if #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32,
    parameter int ID_W   = 4
) (
    input logic ACLK,
    input logic ARESETn
);

    localparam int STRB_W = DATA_W / 8;

    // Write address channel
    logic              AWVALID;
    logic              AWREADY;
    logic [ADDR_W-1:0] AWADDR;
    logic [2:0]        AWPROT;
    logic [ID_W-1:0]   AWID;
    logic [7:0]        AWLEN;
    logic [2:0]        AWSIZE;
    logic [1:0]        AWBURST;

    // Write data channel
    logic              WVALID;
    logic              WREADY;
    logic [DATA_W-1:0] WDATA;
    logic [STRB_W-1:0] WSTRB;
    logic              WLAST;

    // Write response channel
    logic              BVALID;
    logic              BREADY;
    logic [1:0]        BRESP;
    logic [ID_W-1:0]   BID;

    // Read address channel
    logic              ARVALID;
    logic              ARREADY;
    logic [ADDR_W-1:0] ARADDR;
    logic [2:0]        ARPROT;
    logic [ID_W-1:0]   ARID;
    logic [7:0]        ARLEN;
    logic [2:0]        ARSIZE;
    logic [1:0]        ARBURST;

    // Read data channel
    logic              RVALID;
    logic              RREADY;
    logic [DATA_W-1:0] RDATA;
    logic [1:0]        RRESP;
    logic [ID_W-1:0]   RID;
    logic              RLAST;

    modport mgr (
        output AWVALID, AWADDR, AWPROT, AWID, AWLEN, AWSIZE, AWBURST,
        input  AWREADY,
        output WVALID, WDATA, WSTRB, WLAST,
        input  WREADY,
        output BREADY,
        input  BVALID, BRESP, BID,
        output ARVALID, ARADDR, ARPROT, ARID, ARLEN, ARSIZE, ARBURST,
        input  ARREADY,
        output RREADY,
        input  RVALID, RDATA, RRESP, RID, RLAST
    );

    modport sub (
        input  AWVALID, AWADDR, AWPROT, AWID, AWLEN, AWSIZE, AWBURST,
        output AWREADY,
        input  WVALID, WDATA, WSTRB, WLAST,
        output WREADY,
        input  BREADY,
        output BVALID, BRESP, BID,
        input  ARVALID, ARADDR, ARPROT, ARID, ARLEN, ARSIZE, ARBURST,
        output ARREADY,
        input  RREADY,
        output RVALID, RDATA, RRESP, RID, RLAST
    );

`ifndef SYNTHESIS
    initial begin
        assert (ADDR_W >= 12) else $fatal(1, "ADDR_W must be at least 12");
        assert (DATA_W >= 32 && DATA_W <= 1024 && (DATA_W & (DATA_W-1)) == 0)
            else $fatal(1, "DATA_W must be a power of two from 32 through 1024");
        assert ((DATA_W % 8) == 0) else $fatal(1, "DATA_W must be byte-addressable");
        assert (ID_W > 0) else $fatal(1, "ID_W must be positive");
    end
`endif
endinterface
