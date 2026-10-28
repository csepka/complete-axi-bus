// Independent shift-list oracle for address queues retained until completion.
// No assumptions on traffic: unsolicited responses must be gated by ownership.
module formal_request_queue #(
    parameter integer DEPTH=4,
    parameter integer ADDR_W=32, DATA_W=32, ID_W=4,
    parameter integer REQUEST_W=ADDR_W+3+ID_W+8+3+2,
    parameter integer PTR_W=(DEPTH>1)?$clog2(DEPTH):1,
    parameter integer COUNT_W=$clog2(DEPTH+1)
)(
    // Signal declarations and DUT connection are generated structurally.
    `include "ports.vh"
);
    wire [COUNT_W-1:0] formal_wc,formal_rc;
    wire [PTR_W-1:0] formal_wh,formal_wt,formal_rh,formal_rt;
    wire formal_w_sent,formal_r_sent,formal_w_done;
    wire [8:0] formal_wleft;
    wire [DEPTH*REQUEST_W-1:0] formal_wq,formal_rq;
    axi_request_queue_flat #(.MAX_OUTSTANDING(DEPTH),.ADDR_W(ADDR_W),
        .DATA_W(DATA_W),.ID_W(ID_W)) dut(.*);
    reg [COUNT_W-1:0] used_w,used_r;
    reg [REQUEST_W-1:0] writes[0:DEPTH-1],reads[0:DEPTH-1];
    wire push_w=up_AWVALID && up_AWREADY;
    wire push_r=up_ARVALID && up_ARREADY;
    wire pop_w=up_BVALID && up_BREADY;
    wire pop_r=up_RVALID && up_RREADY && up_RLAST;
    wire [REQUEST_W-1:0] offered_w={up_AWADDR,up_AWPROT,up_AWID,up_AWLEN,up_AWSIZE,up_AWBURST};
    wire [REQUEST_W-1:0] offered_r={up_ARADDR,up_ARPROT,up_ARID,up_ARLEN,up_ARSIZE,up_ARBURST};
    wire [REQUEST_W-1:0] issued_w={down_AWADDR,down_AWPROT,down_AWID,down_AWLEN,down_AWSIZE,down_AWBURST};
    wire [REQUEST_W-1:0] issued_r={down_ARADDR,down_ARPROT,down_ARID,down_ARLEN,down_ARSIZE,down_ARBURST};
    reg past_valid=0;
    always @(posedge ACLK) begin
        past_valid<=1;
        if(!past_valid) assume(!ARESETn);
        if(ARESETn) begin
            assert(used_w<=DEPTH && used_r<=DEPTH);
            assert(formal_wc==used_w && formal_rc==used_r);
            assert(formal_wh<DEPTH && formal_wt<DEPTH);
            assert(formal_rh<DEPTH && formal_rt<DEPTH);
            assert(formal_wt==(int'(formal_wh)+int'(used_w))%DEPTH);
            assert(formal_rt==(int'(formal_rh)+int'(used_r))%DEPTH);
            assert(up_AWREADY==(used_w<DEPTH));
            assert(up_ARREADY==(used_r<DEPTH));
            if(formal_w_sent) assert(used_w!=0);
            if(formal_r_sent) assert(used_r!=0);
            if(formal_w_done) assert(formal_w_sent);
            if(formal_w_sent && !formal_w_done) assert(formal_wleft!=0);
            if(up_BVALID) assert(used_w!=0 && formal_w_sent && formal_w_done);
            if(up_RVALID) assert(used_r!=0 && formal_r_sent);
            if(down_WVALID) assert(used_w!=0 && formal_w_sent && !formal_w_done);
            if(down_AWVALID) begin
                assert(used_w!=0 && !formal_w_sent);
                assert(issued_w==writes[0]);
            end
            if(down_ARVALID) begin
                assert(used_r!=0 && !formal_r_sent);
                assert(issued_r==reads[0]);
            end
            for(integer k=0;k<DEPTH;k=k+1) begin
                if(k<used_w) assert(formal_wq[((int'(formal_wh)+k)%DEPTH)*REQUEST_W+:REQUEST_W]==writes[k]);
                if(k<used_r) assert(formal_rq[((int'(formal_rh)+k)%DEPTH)*REQUEST_W+:REQUEST_W]==reads[k]);
            end
            if(past_valid && $past(ARESETn)) begin
                if($past(down_AWVALID && !down_AWREADY)) begin
                    assert(down_AWVALID);assert(issued_w==$past(issued_w));
                end
                if($past(down_ARVALID && !down_ARREADY)) begin
                    assert(down_ARVALID);assert(issued_r==$past(issued_r));
                end
                if($past(used_w!=0 && !pop_w)) assert(writes[0]==$past(writes[0]));
                if($past(used_r!=0 && !pop_r)) assert(reads[0]==$past(reads[0]));
            end
        end else begin
            assert(!up_AWREADY && !up_ARREADY && !down_AWVALID && !down_ARVALID);
            assert(!down_WVALID && !up_WREADY && !up_BVALID && !down_BREADY);
            assert(!up_RVALID && !down_RREADY);
        end
    end
    always @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin used_w<=0;used_r<=0;end
        else begin
            case({push_w,pop_w})
                2'b10:used_w<=used_w+1'b1;
                2'b01:used_w<=used_w-1'b1;
                default:;
            endcase
            case({push_r,pop_r})
                2'b10:used_r<=used_r+1'b1;
                2'b01:used_r<=used_r-1'b1;
                default:;
            endcase
        end
    end
    always @(posedge ACLK) begin
        if(pop_w) for(integer k=0;k<DEPTH-1;k=k+1) writes[k]<=writes[k+1];
        if(pop_r) for(integer k=0;k<DEPTH-1;k=k+1) reads[k]<=reads[k+1];
        if(push_w) writes[int'(used_w)-int'(pop_w)]<=offered_w;
        if(push_r) reads[int'(used_r)-int'(pop_r)]<=offered_r;
    end
endmodule
