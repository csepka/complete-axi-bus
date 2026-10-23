// Independent shift-register reference for the actual two-entry ring FIFO.
// Induction proves safety for arbitrary traffic and synchronous reset sampling;
// it does not model analog reset release, metastability, or unbounded liveness.
module formal_fifo(input logic ACLK, ARESETn, in_valid, out_ready,
                   input logic [7:0] in_payload);
    wire in_ready, out_valid;
    wire [7:0] out_payload;
    wire [1:0] formal_count;
    wire formal_head,formal_tail;
    wire [7:0] formal_second;
    axi_channel_fifo #(.WIDTH(8)) dut(.*);
    logic [1:0] used;
    logic [7:0] first, second;
    wire push=in_valid && in_ready;
    wire pop=out_valid && out_ready;
    logic past_valid=0;
    always @(posedge ACLK) begin
        past_valid<=1;
        if (!past_valid) assume(!ARESETn);
        if (ARESETn) begin
            assert(used<=2);
            assert(formal_count==used);
            assert((formal_head==formal_tail)==(used!=1));
            if(used==2) assert(formal_second==second);
            assert(in_ready==(used<2));
            assert(out_valid==(used!=0));
            if(out_valid) assert(out_payload==first);
            if(past_valid && $past(ARESETn) && $past(out_valid && !out_ready)) begin
                assert(out_valid);
                assert(out_payload==$past(out_payload));
            end
        end
    end
    always @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) used<=0;
        else case({push,pop})
            2'b10:used<=used+1'b1;
            2'b01:used<=used-1'b1;
            default:;
        endcase
    end
    always @(posedge ACLK) begin
        if(pop) first<=second;
        if(push) begin
            if(used==0 || (used==1 && pop)) first<=in_payload;
            else second<=in_payload;
        end
    end
endmodule
