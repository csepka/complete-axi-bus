// Bounded accepted-address storage. A slot remains allocated through response
// acceptance, so MAX_OUTSTANDING includes the executing head. Strict head issue
// preserves all IDs' ordering without ID widening or response reorder storage.
module axi_request_queue #(
    parameter int ADDR_W=32, DATA_W=32, ID_W=4, MAX_OUTSTANDING=1
)(
    input logic ACLK, ARESETn,
    axi_if.sub up,
    axi_if.mgr down
);
    localparam int PTR_W=(MAX_OUTSTANDING>1)?$clog2(MAX_OUTSTANDING):1;
    localparam int COUNT_W=$clog2(MAX_OUTSTANDING+1);
    typedef struct packed {
        logic [ADDR_W-1:0] addr;
        logic [2:0] prot;
        logic [ID_W-1:0] id;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst;
    } request_t;
    request_t wq[MAX_OUTSTANDING], rq[MAX_OUTSTANDING];
    logic [PTR_W-1:0] wh,wt,rh,rt;
    logic [COUNT_W-1:0] wc,rc;
    logic w_sent,r_sent,w_done;
    logic [8:0] wleft;
    wire wpush=up.AWVALID && up.AWREADY;
    wire rpush=up.ARVALID && up.ARREADY;
    wire wpop=up.BVALID && up.BREADY;
    wire rpop=up.RVALID && up.RREADY && up.RLAST;
    function automatic logic [PTR_W-1:0] advance(input logic [PTR_W-1:0] ptr);
        return ptr==PTR_W'(MAX_OUTSTANDING-1) ? '0 : ptr+1'b1;
    endfunction
    assign up.AWREADY=ARESETn && wc<COUNT_W'(MAX_OUTSTANDING);
    assign up.ARREADY=ARESETn && rc<COUNT_W'(MAX_OUTSTANDING);
    assign down.AWVALID=ARESETn && wc!=0 && !w_sent;
    assign down.ARVALID=ARESETn && rc!=0 && !r_sent;
    assign {down.AWADDR,down.AWPROT,down.AWID,down.AWLEN,down.AWSIZE,down.AWBURST}=wq[wh];
    assign {down.ARADDR,down.ARPROT,down.ARID,down.ARLEN,down.ARSIZE,down.ARBURST}=rq[rh];
    assign down.WVALID=ARESETn && w_sent && !w_done && up.WVALID;
    assign {down.WDATA,down.WSTRB,down.WLAST}={up.WDATA,up.WSTRB,up.WLAST};
    assign up.WREADY=ARESETn && w_sent && !w_done && down.WREADY;
    assign down.BREADY=ARESETn && w_sent && w_done && up.BREADY;
    assign up.BVALID=ARESETn && w_sent && w_done && down.BVALID;
    assign {up.BRESP,up.BID}={down.BRESP,down.BID};
    assign down.RREADY=ARESETn && r_sent && up.RREADY;
    assign up.RVALID=ARESETn && r_sent && down.RVALID;
    assign {up.RDATA,up.RRESP,up.RID,up.RLAST}={down.RDATA,down.RRESP,down.RID,down.RLAST};

    // Payload RAMs need no reset: zero counts make stale entries inaccessible.
    always_ff @(posedge ACLK) begin
        if(wpush) wq[wt]<={up.AWADDR,up.AWPROT,up.AWID,up.AWLEN,up.AWSIZE,up.AWBURST};
        if(rpush) rq[rt]<={up.ARADDR,up.ARPROT,up.ARID,up.ARLEN,up.ARSIZE,up.ARBURST};
    end
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin
            wh<='0;wt<='0;rh<='0;rt<='0;wc<='0;rc<='0;
            w_sent<=0;r_sent<=0;w_done<=0;wleft<='0;
        end else begin
            case({wpush,wpop})
                2'b10: wc<=wc+1'b1;
                2'b01: wc<=wc-1'b1;
                default: ;
            endcase
            case({rpush,rpop})
                2'b10: rc<=rc+1'b1;
                2'b01: rc<=rc-1'b1;
                default: ;
            endcase
            if(wpush) wt<=advance(wt);
            if(rpush) rt<=advance(rt);
            if(down.AWVALID && down.AWREADY) begin
                w_sent<=1;wleft<={1'b0,down.AWLEN}+9'd1;
            end
            if(down.ARVALID && down.ARREADY) r_sent<=1;
            if(down.WVALID && down.WREADY) begin
                if(wleft==1) w_done<=1;
                else wleft<=wleft-1'b1;
            end
            if(wpop) begin wh<=advance(wh);w_sent<=0;w_done<=0;end
            if(rpop) begin rh<=advance(rh);r_sent<=0;end
        end
    end
`ifndef SYNTHESIS
    initial assert(MAX_OUTSTANDING>0 && DATA_W>=32) else $fatal(1,"invalid queue parameters");
    ap_w_bound: assert property(@(posedge ACLK) disable iff(!ARESETn) wc<=COUNT_W'(MAX_OUTSTANDING));
    ap_r_bound: assert property(@(posedge ACLK) disable iff(!ARESETn) rc<=COUNT_W'(MAX_OUTSTANDING));
    ap_w_owner: assert property(@(posedge ACLK) disable iff(!ARESETn) wpop |-> wc!=0 && w_sent && w_done);
    ap_r_owner: assert property(@(posedge ACLK) disable iff(!ARESETn) rpop |-> rc!=0 && r_sent);
`endif
endmodule
