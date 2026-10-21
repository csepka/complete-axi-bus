// Per-target concurrency with one ordered head transaction per manager/direction.
// Payload storage and outstanding accounting live in axi_request_queue.
module axi_interconnect #(
    parameter int NM=2, NS=2, ADDR_W=32, DATA_W=32, ID_W=4,
    parameter int S_ADDR_WIDTH=16,
    parameter int MAX_OUTSTANDING=4,
    parameter logic [ADDR_W-1:0] BASE_ADDR='0
)(
    input logic ACLK, ARESETn,
    axi_if m_axi[NM],
    axi_if s_axi[NS]
);
    localparam int SEL_W=$clog2(NS+1);
    localparam logic [ADDR_W-1:0] WINDOW_MASK={ADDR_W{1'b1}} >> (ADDR_W-S_ADDR_WIDTH);
    axi_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)) dispatch[NM](.ACLK,.ARESETn);
    function automatic logic [SEL_W-1:0] decode(input logic [ADDR_W-1:0] addr);
        logic [ADDR_W-1:0] slot;
        slot=(addr-BASE_ADDR)>>S_ADDR_WIDTH;
        return (addr>=BASE_ADDR && slot<ADDR_W'(NS)) ? SEL_W'(slot) : SEL_W'(NS);
    endfunction
    for(genvar m=0;m<NM;m++) begin : g_manager
`ifdef AXI_INTERNAL_CHECKS
        axi_protocol_checker dispatch_checker(.ACLK,.ARESETn,.axi(dispatch[m]));
`endif
        wire [SEL_W-1:0] wselect=decode(dispatch[m].AWADDR);
        wire [SEL_W-1:0] rselect=decode(dispatch[m].ARADDR);
        axi_request_queue #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W),
            .MAX_OUTSTANDING(MAX_OUTSTANDING)) u_queue(
            .ACLK,.ARESETn,.up(m_axi[m]),.down(dispatch[m]));
        wire [NS:0] mux_AWREADY;
        assign dispatch[m].AWREADY=mux_AWREADY[wselect];
        wire [NS:0] mux_WREADY;
        assign dispatch[m].WREADY=mux_WREADY[wselect];
        wire [NS:0] mux_BVALID;
        assign dispatch[m].BVALID=mux_BVALID[wselect];
        wire [NS:0][2-1:0] mux_BRESP;
        assign dispatch[m].BRESP=mux_BRESP[wselect];
        wire [NS:0][ID_W-1:0] mux_BID;
        assign dispatch[m].BID=mux_BID[wselect];
        wire [NS:0] mux_ARREADY;
        assign dispatch[m].ARREADY=mux_ARREADY[rselect];
        wire [NS:0] mux_RVALID;
        assign dispatch[m].RVALID=mux_RVALID[rselect];
        wire [NS:0][DATA_W-1:0] mux_RDATA;
        assign dispatch[m].RDATA=mux_RDATA[rselect];
        wire [NS:0][2-1:0] mux_RRESP;
        assign dispatch[m].RRESP=mux_RRESP[rselect];
        wire [NS:0][ID_W-1:0] mux_RID;
        assign dispatch[m].RID=mux_RID[rselect];
        wire [NS:0] mux_RLAST;
        assign dispatch[m].RLAST=mux_RLAST[rselect];
    end
    for(genvar t=0;t<=NS;t++) begin : g_target
        axi_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)) links[NM](.ACLK,.ARESETn);
        axi_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)) endpoint[1](.ACLK,.ARESETn);
        axi_target_arbiter #(.NM(NM),.NS(1),.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W),
            .S_ADDR_WIDTH(S_ADDR_WIDTH),.BASE_ADDR(t<NS ? BASE_ADDR+(ADDR_W'(t)<<S_ADDR_WIDTH) : BASE_ADDR),
            .FORCE_DECERR(t==NS)) u_arbiter(.ACLK,.ARESETn,.m_axi(links),.s_axi(endpoint));
        for(genvar m=0;m<NM;m++) begin : g_link
`ifdef AXI_INTERNAL_CHECKS
            axi_protocol_checker link_checker(.ACLK,.ARESETn,.axi(links[m]));
`endif
            assign links[m].AWVALID=dispatch[m].AWVALID && g_manager[m].wselect==SEL_W'(t);
            assign g_manager[m].mux_AWREADY[t]=links[m].AWREADY;
            assign links[m].AWADDR=dispatch[m].AWADDR;
            assign links[m].AWPROT=dispatch[m].AWPROT;
            assign links[m].AWID=dispatch[m].AWID;
            assign links[m].AWLEN=dispatch[m].AWLEN;
            assign links[m].AWSIZE=dispatch[m].AWSIZE;
            assign links[m].AWBURST=dispatch[m].AWBURST;
            assign links[m].WVALID=dispatch[m].WVALID && g_manager[m].wselect==SEL_W'(t);
            assign g_manager[m].mux_WREADY[t]=links[m].WREADY;
            assign links[m].WDATA=dispatch[m].WDATA;
            assign links[m].WSTRB=dispatch[m].WSTRB;
            assign links[m].WLAST=dispatch[m].WLAST;
            assign g_manager[m].mux_BVALID[t]=links[m].BVALID;
            assign links[m].BREADY=dispatch[m].BREADY && g_manager[m].wselect==SEL_W'(t);
            assign g_manager[m].mux_BRESP[t]=links[m].BRESP;
            assign g_manager[m].mux_BID[t]=links[m].BID;
            assign links[m].ARVALID=dispatch[m].ARVALID && g_manager[m].rselect==SEL_W'(t);
            assign g_manager[m].mux_ARREADY[t]=links[m].ARREADY;
            assign links[m].ARADDR=dispatch[m].ARADDR;
            assign links[m].ARPROT=dispatch[m].ARPROT;
            assign links[m].ARID=dispatch[m].ARID;
            assign links[m].ARLEN=dispatch[m].ARLEN;
            assign links[m].ARSIZE=dispatch[m].ARSIZE;
            assign links[m].ARBURST=dispatch[m].ARBURST;
            assign g_manager[m].mux_RVALID[t]=links[m].RVALID;
            assign links[m].RREADY=dispatch[m].RREADY && g_manager[m].rselect==SEL_W'(t);
            assign g_manager[m].mux_RDATA[t]=links[m].RDATA;
            assign g_manager[m].mux_RRESP[t]=links[m].RRESP;
            assign g_manager[m].mux_RID[t]=links[m].RID;
            assign g_manager[m].mux_RLAST[t]=links[m].RLAST;
        end
        if(t<NS) begin : g_real
            assign s_axi[t].AWVALID=endpoint[0].AWVALID;
            assign endpoint[0].AWREADY=s_axi[t].AWREADY;
            assign s_axi[t].AWADDR=endpoint[0].AWADDR;
            assign s_axi[t].AWPROT=endpoint[0].AWPROT;
            assign s_axi[t].AWID=endpoint[0].AWID;
            assign s_axi[t].AWLEN=endpoint[0].AWLEN;
            assign s_axi[t].AWSIZE=endpoint[0].AWSIZE;
            assign s_axi[t].AWBURST=endpoint[0].AWBURST;
            assign s_axi[t].WVALID=endpoint[0].WVALID;
            assign endpoint[0].WREADY=s_axi[t].WREADY;
            assign s_axi[t].WDATA=endpoint[0].WDATA;
            assign s_axi[t].WSTRB=endpoint[0].WSTRB;
            assign s_axi[t].WLAST=endpoint[0].WLAST;
            assign endpoint[0].BVALID=s_axi[t].BVALID;
            assign s_axi[t].BREADY=endpoint[0].BREADY;
            assign endpoint[0].BRESP=s_axi[t].BRESP;
            assign endpoint[0].BID=s_axi[t].BID;
            assign s_axi[t].ARVALID=endpoint[0].ARVALID;
            assign endpoint[0].ARREADY=s_axi[t].ARREADY;
            assign s_axi[t].ARADDR=endpoint[0].ARADDR;
            assign s_axi[t].ARPROT=endpoint[0].ARPROT;
            assign s_axi[t].ARID=endpoint[0].ARID;
            assign s_axi[t].ARLEN=endpoint[0].ARLEN;
            assign s_axi[t].ARSIZE=endpoint[0].ARSIZE;
            assign s_axi[t].ARBURST=endpoint[0].ARBURST;
            assign endpoint[0].RVALID=s_axi[t].RVALID;
            assign s_axi[t].RREADY=endpoint[0].RREADY;
            assign endpoint[0].RDATA=s_axi[t].RDATA;
            assign endpoint[0].RRESP=s_axi[t].RRESP;
            assign endpoint[0].RID=s_axi[t].RID;
            assign endpoint[0].RLAST=s_axi[t].RLAST;
        end else begin : g_error
            // FORCE_DECERR ensures the arbiter never drives this unused endpoint.
            assign endpoint[0].AWREADY='0;
            assign endpoint[0].WREADY='0;
            assign endpoint[0].BVALID='0;
            assign endpoint[0].BRESP='0;
            assign endpoint[0].BID='0;
            assign endpoint[0].ARREADY='0;
            assign endpoint[0].RVALID='0;
            assign endpoint[0].RDATA='0;
            assign endpoint[0].RRESP='0;
            assign endpoint[0].RID='0;
            assign endpoint[0].RLAST='0;
        end
    end
`ifndef SYNTHESIS
    initial begin
        assert(NM>0 && NS>0 && MAX_OUTSTANDING>0) else $fatal(1,"positive port counts/depth required");
        assert(S_ADDR_WIDTH>=12 && S_ADDR_WIDTH<ADDR_W) else $fatal(1,"invalid address window");
        assert((BASE_ADDR & WINDOW_MASK)=='0) else $fatal(1,"unaligned BASE_ADDR");
        assert(({1'b0,BASE_ADDR}+((ADDR_W+1)'(NS)<<S_ADDR_WIDTH)) <= ((ADDR_W+1)'(1)<<ADDR_W))
            else $fatal(1,"address map exceeds address space");
    end
`endif
endmodule
