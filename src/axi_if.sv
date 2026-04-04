interface axi_lite_if #(parameter ADDR_W=32, DATA_W=32) (input logic ACLK, input logic ARESETn);
    // AW
    logic AWVALID;
    logic AWREADY;
    logic [ADDR_W-1:0] AWADDR;
    logic [2:0] AWPROT;

    // W
    logic WVALID;
    logic WREADY;
    logic [DATA_W-1:0] WDATA;
    logic [DATA_W/8-1:0] WSTRB;

    // B
    logic BVALID;
    logic BREADY;
    logic [1:0] BRESP;

    // AR
    logic ARVALID;
    logic ARREADY;
    logic [ADDR_W-1:0] ARADDR;
    logic [2:0] ARPROT;

    // R
    logic RVALID;
    logic RREADY;
    logic [DATA_W-1:0] RDATA;
    logic [1:0] RRESP;

    modport mgr (
        output AWVALID, AWADDR, AWPROT,
        output WVALID, WDATA, WSTRB,
        output BREADY,
        output ARVALID, ARADDR, ARPROT,
        output RREADY,
        input AWREADY, WREADY, BVALID, BRESP,
        input ARREADY, RVALID, RDATA, RRESP
    );

    modport sub (
        input AWVALID, AWADDR, AWPROT,
        input WVALID, WDATA, WSTRB,
        input BREADY,
        input ARVALID, ARADDR, ARPROT,
        input RREADY,
        output AWREADY, WREADY, BVALID, BRESP,
        output ARREADY, RVALID, RDATA, RRESP
    );

endinterface