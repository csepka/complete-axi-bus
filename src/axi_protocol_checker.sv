module axi_protocol_checker (
    input logic ACLK,
    input logic ARESETn,
    axi_if axi
);
    ap_aw_stable: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.AWVALID && !axi.AWREADY |=> axi.AWVALID &&
        $stable({axi.AWADDR, axi.AWPROT, axi.AWID, axi.AWLEN,
                 axi.AWSIZE, axi.AWBURST}));

    ap_w_stable: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.WVALID && !axi.WREADY |=> axi.WVALID &&
        $stable({axi.WDATA, axi.WSTRB, axi.WLAST}));

    ap_b_stable: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.BVALID && !axi.BREADY |=> axi.BVALID &&
        $stable({axi.BRESP, axi.BID}));

    ap_ar_stable: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.ARVALID && !axi.ARREADY |=> axi.ARVALID &&
        $stable({axi.ARADDR, axi.ARPROT, axi.ARID, axi.ARLEN,
                 axi.ARSIZE, axi.ARBURST}));

    ap_r_stable: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.RVALID && !axi.RREADY |=> axi.RVALID &&
        $stable({axi.RDATA, axi.RRESP, axi.RID, axi.RLAST}));

    ap_wlast_known: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.WVALID |-> !$isunknown(axi.WLAST));

    ap_rlast_known: assert property (
        @(posedge ACLK) disable iff (!ARESETn)
        axi.RVALID |-> !$isunknown(axi.RLAST));
endmodule
