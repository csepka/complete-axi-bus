`timescale 1ns/1ps
module tb_axi_outstanding #(
    parameter bit PIPELINE=0,
    parameter int DEPTH=4, DATA_W=64, ADDR_W=40
);
    localparam int NM=3,NS=3,ID_W=4,BYTES=DATA_W/8,WORDS=4096/BYTES;
    localparam logic [ADDR_W-1:0] BASE=ADDR_W'(32'h1000_0000);
    logic ACLK,ARESETn;
    logic [NS-1:0] stall_aw,stall_ar,stall_w;
    initial begin ACLK=0;forever #5 ACLK=~ACLK;end
    axi_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)) m_axi[NM](.ACLK,.ARESETn);
    axi_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)) s_axi[NS](.ACLK,.ARESETn);
    logic [NM-1:0] d_awvalid;
    logic [NM-1:0][ADDR_W-1:0] d_awaddr;
    logic [NM-1:0][2:0] d_awprot;
    logic [NM-1:0][ID_W-1:0] d_awid;
    logic [NM-1:0][7:0] d_awlen;
    logic [NM-1:0][2:0] d_awsize;
    logic [NM-1:0][1:0] d_awburst;
    logic [NM-1:0] d_wvalid;
    logic [NM-1:0][DATA_W-1:0] d_wdata;
    logic [NM-1:0][DATA_W/8-1:0] d_wstrb;
    logic [NM-1:0] d_wlast;
    logic [NM-1:0] d_bready;
    logic [NM-1:0] d_arvalid;
    logic [NM-1:0][ADDR_W-1:0] d_araddr;
    logic [NM-1:0][2:0] d_arprot;
    logic [NM-1:0][ID_W-1:0] d_arid;
    logic [NM-1:0][7:0] d_arlen;
    logic [NM-1:0][2:0] d_arsize;
    logic [NM-1:0][1:0] d_arburst;
    logic [NM-1:0] d_rready;

    logic [NM-1:0] q_awready, q_wready, q_bvalid;
    logic [NM-1:0][1:0] q_bresp;
    logic [NM-1:0][ID_W-1:0] q_bid;
    logic [NM-1:0] q_arready, q_rvalid, q_rlast;
    logic [NM-1:0][DATA_W-1:0] q_rdata;
    logic [NM-1:0][1:0] q_rresp;
    logic [NM-1:0][ID_W-1:0] q_rid;


    logic [DATA_W-1:0] model[NS][WORDS];
    int checks=0;
    int verified_peak_w,verified_peak_r;
    int max_w_parallel,max_r_parallel;
    generate
        for(genvar m=0;m<NM;m++) begin : g_driver
            assign m_axi[m].AWVALID = d_awvalid[m];
            assign m_axi[m].AWADDR = d_awaddr[m];
            assign m_axi[m].AWPROT = d_awprot[m];
            assign m_axi[m].AWID = d_awid[m];
            assign m_axi[m].AWLEN = d_awlen[m];
            assign m_axi[m].AWSIZE = d_awsize[m];
            assign m_axi[m].AWBURST = d_awburst[m];
            assign q_awready[m] = m_axi[m].AWREADY;
            assign m_axi[m].WVALID = d_wvalid[m];
            assign m_axi[m].WDATA = d_wdata[m];
            assign m_axi[m].WSTRB = d_wstrb[m];
            assign m_axi[m].WLAST = d_wlast[m];
            assign q_wready[m] = m_axi[m].WREADY;
            assign m_axi[m].BREADY = d_bready[m];
            assign q_bvalid[m] = m_axi[m].BVALID;
            assign q_bresp[m] = m_axi[m].BRESP;
            assign q_bid[m] = m_axi[m].BID;
            assign m_axi[m].ARVALID = d_arvalid[m];
            assign m_axi[m].ARADDR = d_araddr[m];
            assign m_axi[m].ARPROT = d_arprot[m];
            assign m_axi[m].ARID = d_arid[m];
            assign m_axi[m].ARLEN = d_arlen[m];
            assign m_axi[m].ARSIZE = d_arsize[m];
            assign m_axi[m].ARBURST = d_arburst[m];
            assign q_arready[m] = m_axi[m].ARREADY;
            assign m_axi[m].RREADY = d_rready[m];
            assign q_rvalid[m] = m_axi[m].RVALID;
            assign q_rdata[m] = m_axi[m].RDATA;
            assign q_rresp[m] = m_axi[m].RRESP;
            assign q_rid[m] = m_axi[m].RID;
            assign q_rlast[m] = m_axi[m].RLAST;

            axi_protocol_checker u_manager_checker (
                .ACLK, .ARESETn, .axi(m_axi[m])
            );
        end

        for (genvar s = 0; s < NS; s++) begin : g_checker
            axi_protocol_checker u_subordinate_checker (
                .ACLK, .ARESETn, .axi(s_axi[s])
            );
        end


        for(genvar s=0;s<NS;s++) begin : g_ram
            axi_stall_sub #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)) u_sub(
                .ACLK,.ARESETn,.stall_aw(stall_aw[s]),.stall_w(stall_w[s]),.stall_ar(stall_ar[s]),.up(s_axi[s].sub));
            initial begin
                #1;
                for(int j=0;j<WORDS;j++) begin
                    model[s][j]=value(s,j);
                    u_sub.u_sub.u_ram.mem[j]=value(s,j);
                end
            end
        end
    endgenerate
    axi_interconnect #(.NM(NM),.NS(NS),.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W),
        .MAX_OUTSTANDING(DEPTH),.TARGET_PIPELINE(PIPELINE),.BASE_ADDR(BASE)) dut(.ACLK,.ARESETn,.m_axi,.s_axi);
    always @(posedge ACLK) if(!ARESETn) begin
        max_w_parallel<=0;max_r_parallel<=0;
    end else begin
        int nw,nr;
        nw=$countones(d_wvalid&q_wready);nr=$countones(q_rvalid&d_rready);
        if(nw>max_w_parallel)max_w_parallel<=nw;
        if(nr>max_r_parallel)max_r_parallel<=nr;
    end
    initial begin #2000000;$fatal(1,"outstanding test global timeout");end
    function automatic logic [DATA_W-1:0] value(input int seq,beat);
        logic [DATA_W-1:0] v;
        for(int b=0;b<BYTES;b++)v[b*8+:8]=8'(seq*31+beat*7+b);
        return v;
    endfunction
    function automatic logic [ADDR_W-1:0] address(input int t,offset);
        return BASE+(ADDR_W'(t)<<16)+ADDR_W'(offset);
    endfunction
    task automatic check(input bit condition,input string message);
        checks++;
        assert(condition)else $fatal(1,"%s",message);
    endtask
    task automatic reset_dut;
        @(negedge ACLK);
        ARESETn=0;d_awvalid='0;d_arvalid='0;d_wvalid='0;d_bready='0;d_rready='0;
        stall_aw='0;stall_ar='0;stall_w='0;
        repeat(3)@(negedge ACLK);
        check(q_bvalid=='0 && q_rvalid=='0,"reset clears responses");
        ARESETn=1;
        repeat(3)begin
            @(negedge ACLK);
            check(q_bvalid=='0 && q_rvalid=='0,"no ghost response after reset");
        end
    endtask
    task automatic send_aw(input int m,input logic [ADDR_W-1:0] addr,input int beats,input logic [3:0] id);
        int ticks;
        @(negedge ACLK);d_awaddr[m]=addr;d_awlen[m]=8'(beats-1);d_awid[m]=id;
        d_awsize[m]=3'($clog2(BYTES));d_awburst[m]=1;d_awvalid[m]=1;ticks=0;
        do begin @(posedge ACLK);ticks++;if(ticks>5000)$fatal(1,"AW timeout");end while(!q_awready[m]);
        @(negedge ACLK);d_awvalid[m]=0;
    endtask
    task automatic send_ar(input int m,input logic [ADDR_W-1:0] addr,input int beats,input logic [3:0] id);
        int ticks;
        @(negedge ACLK);d_araddr[m]=addr;d_arlen[m]=8'(beats-1);d_arid[m]=id;
        d_arsize[m]=3'($clog2(BYTES));d_arburst[m]=1;d_arvalid[m]=1;ticks=0;
        do begin @(posedge ACLK);ticks++;if(ticks>5000)$fatal(1,"AR timeout");end while(!q_arready[m]);
        @(negedge ACLK);d_arvalid[m]=0;
    endtask
    task automatic send_w(input int m,t,offset,beats,seq,input bit partial=0,input bit final_last=1);
        int ticks;
        for(int b=0;b<beats;b++)begin
            @(negedge ACLK);d_wvalid[m]=1;d_wdata[m]=value(seq,b);d_wlast[m]=final_last && b==beats-1;
            for(int lane=0;lane<BYTES;lane++)d_wstrb[m][lane]=!partial || lane%2==0;
            ticks=0;
            do begin @(posedge ACLK);ticks++;if(ticks>5000)$fatal(1,"W timeout");end while(!q_wready[m]);
            if(t>=0 && t<NS && offset+beats*BYTES<=4096)
                for(int lane=0;lane<BYTES;lane++)
                    if(d_wstrb[m][lane])model[t][offset/BYTES+b][8*lane+:8]=d_wdata[m][8*lane+:8];
            @(negedge ACLK);d_wvalid[m]=0;
        end
    endtask
    task automatic recv_b(input int m,input logic[3:0] id,input logic[1:0] resp=0);
        int ticks;
        // Deliberate response backpressure after every transaction.
        repeat(3)@(negedge ACLK);d_bready[m]=1;ticks=0;
        do begin @(posedge ACLK);ticks++;if(ticks>5000)$fatal(1,"B timeout");end while(!q_bvalid[m]);
        check(q_bid[m]==id && q_bresp[m]==resp,"B ID/status/order");
        @(negedge ACLK);d_bready[m]=0;
    endtask
    task automatic recv_r(input int m,t,offset,beats,input logic[3:0] id,input logic[1:0] resp=0);
        int ticks;
        for(int b=0;b<beats;b++)begin
            repeat(2)@(negedge ACLK);d_rready[m]=1;ticks=0;
            do begin @(posedge ACLK);ticks++;if(ticks>5000)$fatal(1,"R timeout");end while(!q_rvalid[m]);
            check(q_rid[m]==id && q_rresp[m]==resp,"R ID/status/order");
            check(q_rlast[m]==(b==beats-1),"RLAST follows declared burst length");
            if(resp==0)check(q_rdata[m]===model[t][offset/BYTES+b],"R independent data scoreboard");
            else check(q_rdata[m]=='0,"error read zero payload");
            @(negedge ACLK);d_rready[m]=0;
        end
    endtask
    task automatic write_tx(input int m,t,offset,beats,seq,input logic[3:0] id);
        send_aw(m,address(t,offset),beats,id);
        send_w(m,t,offset,beats,seq,1);
        recv_b(m,id);
    endtask
    task automatic read_tx(input int m,t,offset,beats,input logic[3:0] id);
        send_ar(m,address(t,offset),beats,id);
        recv_r(m,t,offset,beats,id);
    endtask

    // Fill independently of execution, keep a fifth request asserted at capacity,
    // then complete everything. IDs deliberately overlap across targets and managers.
    task automatic queued_round(input bit same_id,input int round_idx);
        @(negedge ACLK);stall_aw[0]=1;stall_ar[0]=1;
        for(int q=0;q<DEPTH;q++)begin
            send_aw(0,address(q%NS,round_idx*512+q*32),4,same_id?4'h5:4'(q));
            send_ar(0,address(q%NS,2048+q*32),4,same_id?4'h5:4'(q));
        end
        check(!q_awready[0] && !q_arready[0],"both queues full");
        fork
            send_aw(0,address(DEPTH%NS,round_idx*512+DEPTH*32),4,same_id?4'h5:4'(DEPTH));
            send_ar(0,address(DEPTH%NS,2048+DEPTH*32),4,same_id?4'h5:4'(DEPTH));
            begin
                repeat(8)begin
                    @(negedge ACLK);
                    check(!q_awready[0] && !q_arready[0],"full queue must backpressure overflow");
                end
                // Target 1 is free while manager 0 is blocked on target 0.
                fork
                    write_tx(1,1,1536,4,99,4'h5);
                    read_tx(2,2,1536,4,4'h5);
                join
                check(!q_awready[0] && !q_arready[0],"unrelated completions cannot release owner slots");
                @(negedge ACLK);stall_aw[0]=0;stall_ar[0]=0;
                fork
                    begin
                        for(int q=0;q<=DEPTH;q++)send_w(0,q%NS,round_idx*512+q*32,4,round_idx*20+q,1);
                    end
                    begin
                        for(int q=0;q<=DEPTH;q++)recv_b(0,same_id?4'h5:4'(q));
                    end
                    begin
                        for(int q=0;q<=DEPTH;q++)recv_r(0,q%NS,2048+q*32,4,same_id?4'h5:4'(q));
                    end
                join
            end
        join
        for(int q=0;q<=DEPTH;q++)read_tx(1,q%NS,round_idx*512+q*32,4,4'h5);
    endtask
    task automatic queued_errors;
        // Errors share the same ownership/order machinery as valid queued work.
        fork
            begin
                send_aw(0,address(NS,0),2,4'h2);
                send_aw(0,address(1,1408),2,4'h2);
                send_aw(0,BASE-ADDR_W'(16),2,4'h3);
                send_aw(0,address(0,8192),2,4'h2);
            end
            begin
                send_w(0,-1,0,2,90);
                send_w(0,1,1408,2,91);
                send_w(0,-1,0,2,92);
                send_w(0,0,8192,2,93);
            end
            begin
                recv_b(0,4'h2,2'b11);recv_b(0,4'h2,0);
                recv_b(0,4'h3,2'b11);recv_b(0,4'h2,2'b10);
            end
            begin
                send_ar(0,address(NS,0),2,4'h2);
                send_ar(0,address(2,1408),2,4'h2);
                send_ar(0,BASE-ADDR_W'(16),2,4'h3);
                send_ar(0,address(0,8192),2,4'h2);
            end
            begin
                recv_r(0,-1,0,2,4'h2,2'b11);recv_r(0,2,1408,2,4'h2,0);
                recv_r(0,-1,0,2,4'h3,2'b11);recv_r(0,0,8192,2,4'h2,2'b10);
            end
        join
        read_tx(1,1,1408,2,4'h2);
    endtask
    initial begin
        ARESETn=0;d_awvalid='0;d_wvalid='0;d_bready='0;d_arvalid='0;d_rready='0;
        d_awaddr='0;d_awid='0;d_awlen='0;d_awsize='0;d_awburst='0;d_awprot='0;
        d_wdata='0;d_wstrb='1;d_wlast='0;
        d_araddr='0;d_arid='0;d_arlen='0;d_arsize='0;d_arburst='0;d_arprot='0;
        stall_aw='0;stall_ar='0;stall_w='0;
        reset_dut();
        queued_round(1,0);queued_round(0,1);queued_errors();
        // Non-power-of-two port count; all targets operate concurrently.
        fork
            write_tx(0,0,3072,8,60,4'hA);
            write_tx(1,1,3072,8,61,4'hA);
            write_tx(2,2,3072,8,62,4'hA);
        join
        fork
            read_tx(0,2,3072,8,4'hA);
            read_tx(1,0,3072,8,4'hA);
            read_tx(2,1,3072,8,4'hA);
        join
        check(max_w_parallel==3 && max_r_parallel==3,"three independent targets transfer in parallel");
        verified_peak_w=max_w_parallel;verified_peak_r=max_r_parallel;
        // Sustained same-target requesters: bounded completion for every manager.
        fork
            begin for(int n=0;n<12;n++)write_tx(0,0,3200,4,n,4'h3);end
            begin for(int n=0;n<12;n++)write_tx(1,0,3264,4,n,4'h3);end
            begin for(int n=0;n<12;n++)write_tx(2,0,3328,4,n,4'h3);end
        join
        // Decode misses above and below a nonzero base, queued with valid work.
        send_aw(0,BASE-ADDR_W'(16),4,4'h6);
        send_w(0,-1,0,4,77);recv_b(0,4'h6,2'b11);
        send_ar(1,address(NS,0),4,4'h6);recv_r(1,-1,0,4,4'h6,2'b11);
        send_ar(1,BASE-ADDR_W'(16),2,4'h7);recv_r(1,-1,0,2,4'h7,2'b11);
        send_aw(0,address(0,8192),4,4'h9);send_w(0,0,8192,4,77);recv_b(0,4'h9,2'b10);
        send_ar(1,address(0,8192),2,4'h9);recv_r(1,0,8192,2,4'h9,2'b10);
        // Reset held address grants and full queues.
        @(negedge ACLK);stall_aw[0]=1;stall_ar[0]=1;
        for(int q=0;q<DEPTH;q++)begin
            send_aw(0,address(0,0),4,4'h1);send_ar(0,address(0,0),4,4'h1);
        end
        reset_dut();
        write_tx(0,0,3584,4,80,4'h1);read_tx(1,0,3584,4,4'h1);
        // Reset mid-write and with an unconsumed read beat.
        send_aw(0,address(0,3648),4,4'h2);
        send_w(0,0,3648,1,81,0,0);
        send_ar(1,address(1,0),4,4'h2);
        repeat(5)@(negedge ACLK);
        check(q_rvalid[1],"read pending before reset");
        reset_dut();
        write_tx(0,0,3648,4,82,4'h2);read_tx(1,0,3648,4,4'h2);
        // Reset with B and R simultaneously backpressured.
        send_aw(0,address(0,3712),4,4'h3);send_w(0,0,3712,4,83);
        send_ar(1,address(1,0),4,4'h3);
        repeat(5)@(negedge ACLK);
        check(q_bvalid[0] && q_rvalid[1],"B and R pending before reset");
        reset_dut();
        write_tx(2,2,3712,4,84,4'h3);read_tx(0,2,3712,4,4'h3);
        $display("OUTSTANDING REGRESSION PASS: depth=%0d checks=%0d peak W/R=%0d/%0d",DEPTH,checks,verified_peak_w,verified_peak_r);
        $finish;
    end
endmodule
