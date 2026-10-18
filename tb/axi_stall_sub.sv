module axi_stall_sub #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32,
    parameter int ID_W = 4,
    parameter int MEM_BYTES = 4096,
    parameter int ADDR_OFFSET_W = 16
) (
    input logic ACLK,
    input logic ARESETn,
    input logic stall_aw,
    input logic stall_w,
    input logic stall_ar,
    axi_if.sub up
);
    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W))
        down (.ACLK, .ARESETn);

    assign down.AWVALID = up.AWVALID && !stall_aw;
    assign down.AWADDR = up.AWADDR;
    assign down.AWPROT = up.AWPROT;
    assign down.AWID = up.AWID;
    assign down.AWLEN = up.AWLEN;
    assign down.AWSIZE = up.AWSIZE;
    assign down.AWBURST = up.AWBURST;
    assign up.AWREADY = down.AWREADY && !stall_aw;
    assign down.WVALID = up.WVALID && !stall_w;
    assign down.WDATA = up.WDATA;
    assign down.WSTRB = up.WSTRB;
    assign down.WLAST = up.WLAST;
    assign up.WREADY = down.WREADY && !stall_w;
    assign down.BREADY = up.BREADY;
    assign up.BVALID = down.BVALID;
    assign up.BRESP = down.BRESP;
    assign up.BID = down.BID;
    assign down.ARVALID = up.ARVALID && !stall_ar;
    assign down.ARADDR = up.ARADDR;
    assign down.ARPROT = up.ARPROT;
    assign down.ARID = up.ARID;
    assign down.ARLEN = up.ARLEN;
    assign down.ARSIZE = up.ARSIZE;
    assign down.ARBURST = up.ARBURST;
    assign up.ARREADY = down.ARREADY && !stall_ar;
    assign down.RREADY = up.RREADY;
    assign up.RVALID = down.RVALID;
    assign up.RDATA = down.RDATA;
    assign up.RRESP = down.RRESP;
    assign up.RID = down.RID;
    assign up.RLAST = down.RLAST;

    axi_sub #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
        .MEM_BYTES(MEM_BYTES), .ADDR_OFFSET_W(ADDR_OFFSET_W)
    ) u_sub (
        .ACLK, .ARESETn, .axi(down.sub)
    );
endmodule
