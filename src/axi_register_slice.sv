// Optional target-boundary pipeline. All five channels are independently
// buffered; response ownership remains held in the arbiter until consumption.
module axi_register_slice #(
    parameter int ADDR_W=32, DATA_W=32, ID_W=4,
    parameter bit ENABLE=0
)(
    input logic ACLK, ARESETn,
    axi_if.sub up,
    axi_if.mgr down
);
    if (ENABLE) begin : g_buffered
        axi_channel_fifo #(.WIDTH(ADDR_W+3+ID_W+8+3+2)) u_aw (
            .ACLK, .ARESETn,
            .in_valid(up.AWVALID), .in_ready(up.AWREADY),
            .in_payload({up.AWADDR,up.AWPROT,up.AWID,up.AWLEN,up.AWSIZE,up.AWBURST}),
            .out_valid(down.AWVALID), .out_ready(down.AWREADY),
            .out_payload({down.AWADDR,down.AWPROT,down.AWID,down.AWLEN,down.AWSIZE,down.AWBURST})
        );
        axi_channel_fifo #(.WIDTH(DATA_W+DATA_W/8+1)) u_w (
            .ACLK, .ARESETn,
            .in_valid(up.WVALID), .in_ready(up.WREADY),
            .in_payload({up.WDATA,up.WSTRB,up.WLAST}),
            .out_valid(down.WVALID), .out_ready(down.WREADY),
            .out_payload({down.WDATA,down.WSTRB,down.WLAST})
        );
        axi_channel_fifo #(.WIDTH(2+ID_W)) u_b (
            .ACLK, .ARESETn,
            .in_valid(down.BVALID), .in_ready(down.BREADY),
            .in_payload({down.BRESP,down.BID}),
            .out_valid(up.BVALID), .out_ready(up.BREADY),
            .out_payload({up.BRESP,up.BID})
        );
        axi_channel_fifo #(.WIDTH(ADDR_W+3+ID_W+8+3+2)) u_ar (
            .ACLK, .ARESETn,
            .in_valid(up.ARVALID), .in_ready(up.ARREADY),
            .in_payload({up.ARADDR,up.ARPROT,up.ARID,up.ARLEN,up.ARSIZE,up.ARBURST}),
            .out_valid(down.ARVALID), .out_ready(down.ARREADY),
            .out_payload({down.ARADDR,down.ARPROT,down.ARID,down.ARLEN,down.ARSIZE,down.ARBURST})
        );
        axi_channel_fifo #(.WIDTH(DATA_W+2+ID_W+1)) u_r (
            .ACLK, .ARESETn,
            .in_valid(down.RVALID), .in_ready(down.RREADY),
            .in_payload({down.RDATA,down.RRESP,down.RID,down.RLAST}),
            .out_valid(up.RVALID), .out_ready(up.RREADY),
            .out_payload({up.RDATA,up.RRESP,up.RID,up.RLAST})
        );
    end else begin : g_bypass
        assign down.AWVALID = up.AWVALID;
        assign up.AWREADY = down.AWREADY;
        assign down.AWADDR = up.AWADDR;
        assign down.AWPROT = up.AWPROT;
        assign down.AWID = up.AWID;
        assign down.AWLEN = up.AWLEN;
        assign down.AWSIZE = up.AWSIZE;
        assign down.AWBURST = up.AWBURST;
        assign down.WVALID = up.WVALID;
        assign up.WREADY = down.WREADY;
        assign down.WDATA = up.WDATA;
        assign down.WSTRB = up.WSTRB;
        assign down.WLAST = up.WLAST;
        assign up.BVALID = down.BVALID;
        assign down.BREADY = up.BREADY;
        assign up.BRESP = down.BRESP;
        assign up.BID = down.BID;
        assign down.ARVALID = up.ARVALID;
        assign up.ARREADY = down.ARREADY;
        assign down.ARADDR = up.ARADDR;
        assign down.ARPROT = up.ARPROT;
        assign down.ARID = up.ARID;
        assign down.ARLEN = up.ARLEN;
        assign down.ARSIZE = up.ARSIZE;
        assign down.ARBURST = up.ARBURST;
        assign up.RVALID = down.RVALID;
        assign down.RREADY = up.RREADY;
        assign up.RDATA = down.RDATA;
        assign up.RRESP = down.RRESP;
        assign up.RID = down.RID;
        assign up.RLAST = down.RLAST;
    end
endmodule
