module axi_sub #(
    parameter int ADDR_W        = 32,
    parameter int DATA_W        = 32,
    parameter int ID_W          = 4,
    parameter int MEM_BYTES     = 4096,
    parameter int ADDR_OFFSET_W = 16
) (
    input logic ACLK,
    input logic ARESETn,
    axi_if.sub axi
);
    axi_ram #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .MEM_BYTES(MEM_BYTES),
        .ADDR_OFFSET_W(ADDR_OFFSET_W)
    ) u_ram (
        .ACLK,
        .ARESETn,
        .AWVALID(axi.AWVALID),
        .AWREADY(axi.AWREADY),
        .AWADDR(axi.AWADDR),
        .AWID(axi.AWID),
        .AWLEN(axi.AWLEN),
        .AWSIZE(axi.AWSIZE),
        .AWBURST(axi.AWBURST),
        .WVALID(axi.WVALID),
        .WREADY(axi.WREADY),
        .WDATA(axi.WDATA),
        .WSTRB(axi.WSTRB),
        .WLAST(axi.WLAST),
        .BVALID(axi.BVALID),
        .BREADY(axi.BREADY),
        .BRESP(axi.BRESP),
        .BID(axi.BID),
        .ARVALID(axi.ARVALID),
        .ARREADY(axi.ARREADY),
        .ARADDR(axi.ARADDR),
        .ARID(axi.ARID),
        .ARLEN(axi.ARLEN),
        .ARSIZE(axi.ARSIZE),
        .ARBURST(axi.ARBURST),
        .RVALID(axi.RVALID),
        .RREADY(axi.RREADY),
        .RDATA(axi.RDATA),
        .RRESP(axi.RRESP),
        .RID(axi.RID),
        .RLAST(axi.RLAST)
    );
endmodule
