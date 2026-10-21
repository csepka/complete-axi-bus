`timescale 1ns/1ps
module tb_axi_channel_fifo;
    localparam int WIDTH=64;
    logic ACLK,ARESETn,in_valid,in_ready,out_valid,out_ready;
    logic [WIDTH-1:0] in_payload,out_payload;
    logic [WIDTH-1:0] expected[0:20000];
    int pushed,popped,checks;
    bit saw_empty,saw_full,saw_both,saw_stall,saw_reset_full;
    logic [31:0] rng;
    initial begin ACLK=0;forever #5 ACLK=~ACLK;end
    axi_channel_fifo #(.WIDTH(WIDTH)) dut(.*);
    initial begin
        ARESETn=0;in_valid=0;out_ready=0;in_payload=0;
        pushed=0;popped=0;checks=0;rng=32'h51CE2026;
        saw_empty=0;saw_full=0;saw_both=0;saw_stall=0;saw_reset_full=0;
        repeat(3)@(negedge ACLK);
        ARESETn=1;
        for(int cycle=0;cycle<10000;cycle++)begin
            bit push,pop;
            // Hold every offered item until accepted. Pacing is reproducible.
            rng=rng*32'd1664525+32'd1013904223;
            if(!in_valid)begin
                in_valid=(rng[7:0]<200);
                in_payload={rng,32'(cycle)};
            end
            out_ready=(rng[15:8]<150);
            @(posedge ACLK);
            push=in_valid&&in_ready;pop=out_valid&&out_ready;
            if(pushed==popped)saw_empty=1;
            if(pushed-popped==2)saw_full=1;
            if(push&&pop)saw_both=1;
            if(out_valid&&!out_ready)saw_stall=1;
            assert(pushed-popped<=2)else $fatal(1,"FIFO overflow");
            if(pop)begin
                assert(popped<pushed && out_payload===expected[popped])else $fatal(1,"FIFO lost/reordered/corrupted payload");
                popped++;checks++;
            end
            if(push)begin expected[pushed]=in_payload;pushed++;end
            @(negedge ACLK);
            if(push)in_valid=0;
            if(cycle%97==0 && pushed-popped==2)begin
                saw_reset_full=1;ARESETn=0;in_valid=0;out_ready=0;
                repeat(2)@(negedge ACLK);
                assert(!out_valid && !in_ready)else $fatal(1,"FIFO reset outputs");
                pushed=0;popped=0;ARESETn=1;
            end
        end
        // Drain any offer and buffered data with a bounded loop.
        out_ready=1;
        for(int cycle=0;cycle<4;cycle++)begin
            bit push;
            @(posedge ACLK);push=in_valid&&in_ready;
            if(out_valid)begin
                assert(popped<pushed && out_payload===expected[popped])else $fatal(1,"FIFO drain");
                popped++;checks++;
            end
            if(push)begin expected[pushed]=in_payload;pushed++;end
            @(negedge ACLK);if(push)in_valid=0;
        end
        assert(pushed==popped && !out_valid && saw_empty && saw_full && saw_both && saw_stall && saw_reset_full)
            else $fatal(1,"FIFO directed state coverage incomplete");
        $display("CHANNEL FIFO REGRESSION PASS: %0d payload checks; empty/full/simultaneous/stall/reset-full observed",checks);
        $finish;
    end
endmodule
