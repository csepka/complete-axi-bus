`timescale 1ns/1ps
// Direct AXI traffic: deterministic arrival and sink pacing, independent checks.
module tb_axi_benchmark #(
    parameter int NM=2, NS=2, DATA_W=64, ADDR_W=32,
    parameter bit PIPELINE=0,
    parameter int DEPTH=1
);
    localparam int ID_W=4, BYTES=DATA_W/8;
    logic ACLK, ARESETn;
    initial begin ACLK=0; forever #5 ACLK=~ACLK; end
    bit verify_memory=0;
    bit wrote[NS][NM];
    wire [NS-1:0] target_wfire,target_rfire;
    wire [NM-1:0] arbitration_w_wait,arbitration_r_wait;
    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)) m_axi[NM](.ACLK,.ARESETn);
    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)) s_axi[NS](.ACLK,.ARESETn);
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


    generate
        for (genvar m=0;m<NM;m++) begin : g_driver
`ifdef QUEUED_FABRIC
            assign arbitration_w_wait[m]=dut.dispatch[m].AWVALID && !dut.dispatch[m].AWREADY;
            assign arbitration_r_wait[m]=dut.dispatch[m].ARVALID && !dut.dispatch[m].ARREADY;
`else
            assign arbitration_w_wait[m]=m_axi[m].AWVALID && !m_axi[m].AWREADY;
            assign arbitration_r_wait[m]=m_axi[m].ARVALID && !m_axi[m].ARREADY;
`endif
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


        for (genvar s=0;s<NS;s++) begin : g_ram
            assign target_wfire[s]=s_axi[s].WVALID && s_axi[s].WREADY;
            assign target_rfire[s]=s_axi[s].RVALID && s_axi[s].RREADY;
            axi_sub #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .MEM_BYTES(65536)) u_sub(
                .ACLK,.ARESETn,.axi(s_axi[s].sub));
            // Explicit test-fixture preload, outside measurement; no zero-power-up assumption.
            initial begin
                #1;
                for (int word_idx=0;word_idx<65536/BYTES;word_idx++)
                    u_sub.u_ram.mem[word_idx]=pattern(s,word_idx*BYTES);
            end
            always @(posedge verify_memory) begin
                for (int m=0;m<NM;m++)
                    if(wrote[s][m])
                        for(int b=0;b<burst;b++)
                            assert(u_sub.u_ram.mem[(32768+m*4096)/BYTES+b] ===
                                ~pattern(s,32768+m*4096+b*BYTES))
                                else $fatal(1,"write memory scoreboard target %0d manager %0d beat %0d",s,m,b);
            end
        end
    endgenerate
    axi_interconnect #(.NM(NM),.NS(NS),.ADDR_W(ADDR_W),.DATA_W(DATA_W)
`ifdef QUEUED_FABRIC
        ,.MAX_OUTSTANDING(DEPTH)
`ifdef PIPELINED_FABRIC
        ,.TARGET_PIPELINE(PIPELINE)
`endif
`endif
    ) dut(.ACLK,.ARESETn,.m_axi,.s_axi);

    function automatic logic [DATA_W-1:0] pattern(input int target, addr);
        logic [DATA_W-1:0] v;
        for (int b=0;b<BYTES;b++) v[8*b+:8]=8'(target*29+(addr>>8)*17+addr+b);
        return v;
    endfunction
    int burst=16, transactions=32, mode=2, distribution=0, ready_pct=100, arrival_pct=100;
    int seed=1, cycles=0, active_managers=NM;
    int read_percent=-1,reads,writes;
    int aw[NM], wd[NM], bc[NM], ar[NM], rd[NM];
    int aw_time[NM][1024], ar_time[NM][1024];
    int wbeats[NM], rbeats[NM], wait_aw[NM], wait_ar[NM], stall_w[NM], stall_r[NM];
    int target_w[NS], target_r[NS];
    int lat_sum[NM], lat_max[NM], completed[NM], peak_w=0, peak_r=0;
    longint unsigned cumulative_w=0,cumulative_r=0;
    int outstanding_w[NM], outstanding_r[NM], peak_ow=0, peak_or=0;
    int arb_aw_wait[NM],arb_ar_wait[NM];
    int aw_offer[NM], ar_offer[NM], offer_sum[NM], offer_max[NM];
    logic [31:0] rng;
    function automatic int target(input int manager, tx);
        if (distribution==1) return 0;
        if (distribution==2) return (manager+tx+seed)%NS;
        return manager%NS;
    endfunction
    function automatic int address(input int manager, tx, input bit wr);
        return target(manager,tx)*65536 + (wr ? 32768 : 0) + manager*4096;
    endfunction
    task automatic record_latency(input int m, start_cycle, offer_cycle);
        int v;
        v=cycles-start_cycle;
        lat_sum[m]+=v; if(v>lat_max[m]) lat_max[m]=v;
        v=cycles-offer_cycle;
        offer_sum[m]+=v; if(v>offer_max[m]) offer_max[m]=v;
        completed[m]++;
    endtask
    int aw_offers[NM][1024], ar_offers[NM][1024];
    initial begin
        void'($value$plusargs("burst=%d",burst));
        void'($value$plusargs("transactions=%d",transactions));
        void'($value$plusargs("mode=%d",mode));
        void'($value$plusargs("distribution=%d",distribution));
        void'($value$plusargs("ready=%d",ready_pct));
        void'($value$plusargs("arrival=%d",arrival_pct));
        void'($value$plusargs("seed=%d",seed));
        void'($value$plusargs("managers=%d",active_managers));
        assert(burst>0 && burst<=256 && burst*BYTES<=4096 && transactions>0 && transactions<=1024
            && active_managers>0 && active_managers<=NM && NM<=8 && mode>=0 && mode<=2
            && ready_pct>0 && ready_pct<=100 && arrival_pct>0 && arrival_pct<=100)
            else $fatal(1,"invalid benchmark configuration");
        ARESETn=0;
        assert(DEPTH>0 && (PIPELINE==0 || PIPELINE==1)) else $fatal;
        reads=(mode!=1)?transactions:0;writes=(mode!=0)?transactions:0;
        if($value$plusargs("read_percent=%d",read_percent))begin
            assert(read_percent>=0 && read_percent<=100 && mode==2)else $fatal(1,"invalid mix");
            reads=2*transactions*read_percent/100;writes=2*transactions-reads;
        end
        assert(reads<=1024 && writes<=1024 && seed>=0)else $fatal(1,"transaction table or seed out of range");
        rng=32'(seed);
        d_awvalid='0; d_wvalid='0; d_bready='0; d_arvalid='0; d_rready='0;
        d_awaddr='0; d_awid='0; d_awlen='0; d_awsize='0; d_awburst='0; d_awprot='0;
        d_wdata='0; d_wstrb='1; d_wlast='0;
        d_araddr='0; d_arid='0; d_arlen='0; d_arsize='0; d_arburst='0; d_arprot='0;
        repeat(4) @(negedge ACLK);
        ARESETn=1;
        while(1) begin
            int fw,fr,ow,orr;
            bit done_all;
            // All inputs change on falling edge and are held until handshake.
            for(int m=0;m<active_managers;m++) begin
                rng=rng*32'd1664525+32'd1013904223;
                d_bready[m]=(int'(rng%100)<ready_pct);
                d_rready[m]=(int'((rng>>8)%100)<ready_pct);
                if(!d_awvalid[m] && writes>0 && aw[m]<writes && int'((rng>>16)%100)<arrival_pct) begin
                    d_awvalid[m]=1; d_awaddr[m]=ADDR_W'(address(m,aw[m],1));
                    d_awlen[m]=8'(burst-1); d_awsize[m]=3'($clog2(BYTES)); d_awburst[m]=1;
                    d_awid[m]=4'(aw[m]%3); aw_offer[m]=cycles;
                end
                if(!d_arvalid[m] && reads>0 && ar[m]<reads && int'((rng>>20)%100)<arrival_pct) begin
                    d_arvalid[m]=1; d_araddr[m]=ADDR_W'(address(m,ar[m],0));
                    d_arlen[m]=8'(burst-1); d_arsize[m]=3'($clog2(BYTES)); d_arburst[m]=1;
                    d_arid[m]=4'(ar[m]%3); ar_offer[m]=cycles;
                end
                if(!d_wvalid[m] && wd[m]<aw[m]*burst) begin
                    d_wvalid[m]=1; d_wlast[m]=(wd[m]%burst==burst-1);
                    d_wdata[m]=~pattern(target(m,wd[m]/burst),32768+m*4096+(wd[m]%burst)*BYTES);
                end
            end
            @(posedge ACLK);
            cycles++; fw=0;fr=0;ow=0;orr=0;done_all=1;
            for(int m=0;m<active_managers;m++) begin
                if(arbitration_w_wait[m]) arb_aw_wait[m]++;
                if(arbitration_r_wait[m]) arb_ar_wait[m]++;
                if(d_awvalid[m] && !q_awready[m]) wait_aw[m]++;
                if(d_arvalid[m] && !q_arready[m]) wait_ar[m]++;
                if(d_wvalid[m] && !q_wready[m]) stall_w[m]++;
                if(q_rvalid[m] && !d_rready[m]) stall_r[m]++;
                if(d_awvalid[m] && q_awready[m]) begin
                    aw_time[m][aw[m]]=cycles; aw_offers[m][aw[m]]=aw_offer[m]; aw[m]++; outstanding_w[m]++;
                end
                if(d_arvalid[m] && q_arready[m]) begin
                    ar_time[m][ar[m]]=cycles; ar_offers[m][ar[m]]=ar_offer[m]; ar[m]++; outstanding_r[m]++;
                end
                if(d_wvalid[m] && q_wready[m]) begin
                    wrote[target(m,wd[m]/burst)][m]=1;
                    wd[m]++; wbeats[m]++;fw++;
                end
                if(q_bvalid[m] && d_bready[m]) begin
                    assert(q_bresp[m]==0 && q_bid[m]==4'(bc[m]%3) && bc[m]<aw[m])
                        else $fatal(1,"write response routing/order");
                    record_latency(m,aw_time[m][bc[m]],aw_offers[m][bc[m]]);bc[m]++;outstanding_w[m]--;
                end
                if(q_rvalid[m] && d_rready[m]) begin
                    assert(q_rresp[m]==0 && q_rid[m]==4'((rd[m]/burst)%3) &&
                        q_rlast[m]==(rd[m]%burst==burst-1) && rd[m]<ar[m]*burst &&
                        q_rdata[m]===pattern(target(m,rd[m]/burst),m*4096+(rd[m]%burst)*BYTES))
                        else $fatal(1,"read data/routing/order manager %0d beat %0d",m,rd[m]);
                    if(q_rlast[m]) begin
                        record_latency(m,ar_time[m][rd[m]/burst],ar_offers[m][rd[m]/burst]);outstanding_r[m]--;
                    end
                    rd[m]++;rbeats[m]++;fr++;
                end
                ow+=outstanding_w[m];orr+=outstanding_r[m];
                if(bc[m]!=writes || rd[m]!=reads*burst) done_all=0;
            end
            for(int t=0;t<NS;t++)begin
                if(target_wfire[t])target_w[t]++;
                if(target_rfire[t])target_r[t]++;
            end
            if(fw>peak_w)peak_w=fw;if(fr>peak_r)peak_r=fr;
            cumulative_w+=64'(ow);cumulative_r+=64'(orr);
            if(ow>peak_ow)peak_ow=ow;if(orr>peak_or)peak_or=orr;
            if(done_all) break;
            if(cycles>2000000) $fatal(1,"benchmark timeout");
            // Capture handshake before NBA changes READY/VALID, then remove at negedge.
            begin
                logic [NM-1:0] af,rf,wf;
                af=d_awvalid&q_awready;rf=d_arvalid&q_arready;wf=d_wvalid&q_wready;
                @(negedge ACLK);
                d_awvalid &= ~af;d_arvalid &= ~rf;d_wvalid &= ~wf;
            end
        end
        $display("TOTAL,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycles,peak_w,peak_r,peak_ow,peak_or,cumulative_w,cumulative_r);
        for(int m=0;m<NM;m++)
            $display("MANAGER,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",m,wbeats[m],rbeats[m],wait_aw[m],wait_ar[m],stall_w[m],stall_r[m],lat_sum[m],lat_max[m],completed[m],offer_sum[m],offer_max[m],arb_aw_wait[m],arb_ar_wait[m]);
        for(int s=0;s<NS;s++) $display("TARGET,%0d,%0d,%0d",s,target_w[s],target_r[s]);
        @(negedge ACLK); verify_memory=1; #1;
        $display("BENCHMARK PASS"); $finish;
    end
endmodule
