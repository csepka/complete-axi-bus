`timescale 1ns/1ps

module tb_axi_burst;
    localparam int ADDR_W       = 32;
    localparam int DATA_W       = 32;
    localparam int ID_W         = 4;
    localparam int NM           = 2;
    localparam int NS           = 2;
    localparam int S_ADDR_WIDTH = 16;
    localparam int MEM_BYTES    = 4096;
    localparam int WORDS        = MEM_BYTES / (DATA_W/8);
    localparam int TIMEOUT      = 4000;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;
    localparam logic [1:0] RESP_DECERR = 2'b11;
    localparam logic [1:0] BURST_FIXED = 2'b00;
    localparam logic [1:0] BURST_INCR  = 2'b01;
    localparam logic [1:0] BURST_WRAP  = 2'b10;

    logic ACLK;
    logic ARESETn;
    logic stall_aw;
    logic stall_w;
    logic stall_ar;

    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W))
        m_axi [NM] (.ACLK, .ARESETn);
    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W))
        s_axi [NS] (.ACLK, .ARESETn);

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

    logic [DATA_W-1:0] model [0:NS-1][0:WORDS-1];
    integer checks;
    integer failures;

    initial begin
        ACLK = 1'b0;
        forever #5 ACLK = ~ACLK;
    end

    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("build/tb_axi_burst.vcd");
            $dumpvars(0, tb_axi_burst);
        end
    end

    generate
        for (genvar m = 0; m < NM; m++) begin : g_driver
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

        if (NS > 0) begin : g_stallable_subordinate
            axi_stall_sub #(
                .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
                .MEM_BYTES(MEM_BYTES), .ADDR_OFFSET_W(S_ADDR_WIDTH)
            ) u_sub (
                .ACLK, .ARESETn, .stall_aw, .stall_w, .stall_ar,
                .up(s_axi[0].sub)
            );
        end

        for (genvar s = 1; s < NS; s++) begin : g_subordinate
            axi_sub #(
                .ADDR_W(ADDR_W),
                .DATA_W(DATA_W),
                .ID_W(ID_W),
                .MEM_BYTES(MEM_BYTES),
                .ADDR_OFFSET_W(S_ADDR_WIDTH)
            ) u_sub (
                .ACLK, .ARESETn, .axi(s_axi[s].sub)
            );
        end
    endgenerate

    axi_interconnect #(
        .NM(NM),
        .NS(NS),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .S_ADDR_WIDTH(S_ADDR_WIDTH)
    ) dut (
        .ACLK, .ARESETn, .m_axi, .s_axi
    );

    task automatic check_result(input logic condition, input string message);
        checks = checks + 1;
        if (!condition) begin
            failures = failures + 1;
            $error("CHECK FAILED: %s", message);
        end
    endtask

    function automatic [ADDR_W-1:0] next_address(
        input logic [ADDR_W-1:0] address,
        input logic [7:0] length,
        input logic [1:0] burst
    );
        logic [ADDR_W-1:0] incremented;
        logic [ADDR_W-1:0] wrap_bytes;
        logic [ADDR_W-1:0] wrap_base;
        begin
            if (burst == BURST_FIXED) begin
                next_address = address;
            end else begin
                incremented = address + (DATA_W/8);
                if (burst == BURST_WRAP) begin
                    wrap_bytes = (int'(length) + 1) * (DATA_W/8);
                    wrap_base = (address / wrap_bytes) * wrap_bytes;
                    next_address = (incremented >= wrap_base + wrap_bytes)
                                   ? wrap_base : incremented;
                end else begin
                    next_address = incremented;
                end
            end
        end
    endfunction

    function automatic integer subordinate_id(input logic [ADDR_W-1:0] address);
        subordinate_id = address >> S_ADDR_WIDTH;
    endfunction

    function automatic integer word_id(input logic [ADDR_W-1:0] address);
        word_id = (address & ((1 << S_ADDR_WIDTH) - 1)) >> $clog2(DATA_W/8);
    endfunction

    function automatic [DATA_W-1:0] merge_strobe(
        input logic [DATA_W-1:0] old_data,
        input logic [DATA_W-1:0] new_data,
        input logic [DATA_W/8-1:0] strobe
    );
        logic [DATA_W-1:0] merged;
        begin
            merged = old_data;
            for (integer lane = 0; lane < DATA_W/8; lane = lane + 1)
                if (strobe[lane])
                    merged[(lane*8) +: 8] = new_data[(lane*8) +: 8];
            merge_strobe = merged;
        end
    endfunction

    task automatic initialize;
        ARESETn = 1'b0;
        stall_aw = 1'b0;
        stall_w = 1'b0;
        stall_ar = 1'b0;
        d_awvalid = '0;
        d_awaddr = '0;
        d_awprot = '0;
        d_awid = '0;
        d_awlen = '0;
        d_awsize = '0;
        d_awburst = '0;
        d_wvalid = '0;
        d_wdata = '0;
        d_wstrb = '0;
        d_wlast = '0;
        d_bready = '0;
        d_arvalid = '0;
        d_araddr = '0;
        d_arprot = '0;
        d_arid = '0;
        d_arlen = '0;
        d_arsize = '0;
        d_arburst = '0;
        d_rready = '0;
        for (integer s = 0; s < NS; s = s + 1)
            for (integer w = 0; w < WORDS; w = w + 1)
                model[s][w] = '0;
        repeat (5) @(posedge ACLK);
        ARESETn = 1'b1;
        repeat (2) @(posedge ACLK);
    endtask

    task automatic axi_write(
        input integer manager,
        input logic [ADDR_W-1:0] start_address,
        input logic [7:0] length,
        input logic [1:0] burst,
        input logic [ID_W-1:0] id,
        input logic [DATA_W-1:0] seed,
        input logic [DATA_W/8-1:0] strobe,
        input logic [1:0] expected_response,
        input logic malformed_last = 1'b0,
        input logic [2:0] transfer_size = 3'($clog2(DATA_W/8))
    );
        logic [ADDR_W-1:0] address;
        logic [DATA_W-1:0] beat_data;
        integer cycles;
        integer sid;
        integer wid;

        @(negedge ACLK);
        d_awaddr[manager] = start_address;
        d_awid[manager] = id;
        d_awlen[manager] = length;
        d_awsize[manager] = transfer_size;
        d_awburst[manager] = burst;
        d_awprot[manager] = 3'b000;
        d_awvalid[manager] = 1'b1;
        cycles = 0;
        while (!q_awready[manager] && cycles < TIMEOUT) begin
            @(posedge ACLK);
            cycles = cycles + 1;
        end
        if (cycles == TIMEOUT)
            $fatal(1, "AW timeout for manager %0d", manager);
        @(negedge ACLK);
        d_awvalid[manager] = 1'b0;

        address = start_address;
        for (integer beat = 0; beat <= length; beat = beat + 1) begin
            repeat ($urandom_range(0, 2)) @(posedge ACLK);
            @(negedge ACLK);
            beat_data = seed + beat;
            d_wdata[manager] = beat_data;
            d_wstrb[manager] = strobe;
            d_wlast[manager] = malformed_last ? (beat == 0)
                                                : (beat == int'(length));
            d_wvalid[manager] = 1'b1;
            cycles = 0;
            while (!q_wready[manager] && cycles < TIMEOUT) begin
                @(posedge ACLK);
                cycles = cycles + 1;
            end
            if (cycles == TIMEOUT)
                $fatal(1, "W timeout for manager %0d beat %0d", manager, beat);
            if (expected_response == RESP_OKAY) begin
                sid = subordinate_id(address);
                wid = word_id(address);
                model[sid][wid] = merge_strobe(model[sid][wid], beat_data, strobe);
            end
            @(negedge ACLK);
            d_wvalid[manager] = 1'b0;
            address = next_address(address, length, burst);
        end

        repeat ($urandom_range(0, 3)) @(posedge ACLK);
        @(negedge ACLK);
        d_bready[manager] = 1'b1;
        cycles = 0;
        while (!q_bvalid[manager] && cycles < TIMEOUT) begin
            @(posedge ACLK);
            cycles = cycles + 1;
        end
        if (cycles == TIMEOUT)
            $fatal(1, "B timeout for manager %0d", manager);
        check_result(q_bresp[manager] == expected_response,
                     $sformatf("BRESP manager=%0d expected=%b actual=%b",
                               manager, expected_response, q_bresp[manager]));
        check_result(q_bid[manager] == id,
                     $sformatf("BID manager=%0d expected=%h actual=%h",
                               manager, id, q_bid[manager]));
        @(negedge ACLK);
        d_bready[manager] = 1'b0;
    endtask

    task automatic axi_read(
        input integer manager,
        input logic [ADDR_W-1:0] start_address,
        input logic [7:0] length,
        input logic [1:0] burst,
        input logic [ID_W-1:0] id,
        input logic [1:0] expected_response,
        input logic [2:0] transfer_size = 3'($clog2(DATA_W/8))
    );
        logic [ADDR_W-1:0] address;
        logic [DATA_W-1:0] expected_data;
        integer cycles;
        integer sid;
        integer wid;

        @(negedge ACLK);
        d_araddr[manager] = start_address;
        d_arid[manager] = id;
        d_arlen[manager] = length;
        d_arsize[manager] = transfer_size;
        d_arburst[manager] = burst;
        d_arprot[manager] = 3'b000;
        d_arvalid[manager] = 1'b1;
        cycles = 0;
        while (!q_arready[manager] && cycles < TIMEOUT) begin
            @(posedge ACLK);
            cycles = cycles + 1;
        end
        if (cycles == TIMEOUT)
            $fatal(1, "AR timeout for manager %0d", manager);
        @(negedge ACLK);
        d_arvalid[manager] = 1'b0;

        address = start_address;
        for (integer beat = 0; beat <= length; beat = beat + 1) begin
            // Random response stalls exercise payload stability assertions.
            repeat ($urandom_range(0, 3)) @(posedge ACLK);
            @(negedge ACLK);
            d_rready[manager] = 1'b1;
            cycles = 0;
            while (!q_rvalid[manager] && cycles < TIMEOUT) begin
                @(posedge ACLK);
                cycles = cycles + 1;
            end
            if (cycles == TIMEOUT)
                $fatal(1, "R timeout for manager %0d beat %0d", manager, beat);

            check_result(q_rresp[manager] == expected_response,
                         $sformatf("RRESP manager=%0d beat=%0d expected=%b actual=%b",
                                   manager, beat, expected_response, q_rresp[manager]));
            check_result(q_rid[manager] == id,
                         $sformatf("RID manager=%0d beat=%0d expected=%h actual=%h",
                                   manager, beat, id, q_rid[manager]));
            check_result(q_rlast[manager] == (beat == int'(length)),
                         $sformatf("RLAST manager=%0d beat=%0d", manager, beat));
            if (expected_response == RESP_OKAY) begin
                sid = subordinate_id(address);
                wid = word_id(address);
                expected_data = model[sid][wid];
                check_result(q_rdata[manager] === expected_data,
                             $sformatf("RDATA manager=%0d beat=%0d address=%h expected=%h actual=%h",
                                       manager, beat, address, expected_data, q_rdata[manager]));
            end else begin
                check_result(q_rdata[manager] == '0,
                             $sformatf("error read data manager=%0d beat=%0d", manager, beat));
            end
            @(negedge ACLK);
            d_rready[manager] = 1'b0;
            address = next_address(address, length, burst);
        end
    endtask

    initial begin
        checks = 0;
        failures = 0;
        void'($urandom(32'hA81C_2026));
        initialize();

        // A grant must remain stable when address/data channels are backpressured.
        stall_aw = 1'b1;
        fork
            axi_write(1, 32'h0000_0000, 8'd0, BURST_INCR, 4'h1,
                      32'h0101_0001, 4'hF, RESP_OKAY);
            begin
                repeat (3) @(posedge ACLK);
                axi_write(0, 32'h0000_0004, 8'd0, BURST_INCR, 4'h2,
                          32'h0202_0002, 4'hF, RESP_OKAY);
            end
            begin
                repeat (10) @(posedge ACLK);
                @(negedge ACLK);
                stall_aw = 1'b0;
            end
        join

        stall_ar = 1'b1;
        fork
            axi_read(1, 32'h0000_0000, 8'd0, BURST_INCR, 4'h3, RESP_OKAY);
            begin
                repeat (3) @(posedge ACLK);
                axi_read(0, 32'h0000_0004, 8'd0, BURST_INCR, 4'h4, RESP_OKAY);
            end
            begin
                repeat (10) @(posedge ACLK);
                @(negedge ACLK);
                stall_ar = 1'b0;
            end
        join

        stall_w = 1'b1;
        fork
            axi_write(0, 32'h0000_0008, 8'd0, BURST_INCR, 4'h5,
                      32'h0505_0005, 4'hF, RESP_OKAY);
            begin
                repeat (10) @(posedge ACLK);
                @(negedge ACLK);
                stall_w = 1'b0;
            end
        join
        axi_read(1, 32'h0000_0008, 8'd0, BURST_INCR, 4'h6, RESP_OKAY);

        // Every legal burst mode, with response backpressure and ID checking.
        axi_write(0, 32'h0000_0020, 8'd3, BURST_INCR, 4'h1,
                  32'h1000_0000, 4'hF, RESP_OKAY);
        axi_read (1, 32'h0000_0020, 8'd3, BURST_INCR, 4'h2, RESP_OKAY);

        axi_write(1, 32'h0001_0040, 8'd3, BURST_FIXED, 4'h3,
                  32'h2000_0000, 4'hF, RESP_OKAY);
        axi_read (0, 32'h0001_0040, 8'd3, BURST_FIXED, 4'h4, RESP_OKAY);

        // Four-beat wrap starts at the final word of its 16-byte boundary.
        axi_write(0, 32'h0000_003C, 8'd3, BURST_WRAP, 4'h5,
                  32'h3000_0000, 4'hF, RESP_OKAY);
        axi_read (1, 32'h0000_003C, 8'd3, BURST_WRAP, 4'h6, RESP_OKAY);

        // A legal wrap may begin on the final word of the implemented RAM.
        axi_write(0, 32'h0000_0FFC, 8'd3, BURST_WRAP, 4'h7,
                  32'h3F00_0000, 4'hF, RESP_OKAY);
        axi_read (1, 32'h0000_0FFC, 8'd3, BURST_WRAP, 4'h8, RESP_OKAY);

        // Byte lane semantics preserve bytes whose WSTRB bits are clear.
        axi_write(0, 32'h0000_0080, 8'd0, BURST_INCR, 4'h7,
                  32'h1122_3344, 4'hF, RESP_OKAY);
        axi_write(1, 32'h0000_0080, 8'd0, BURST_INCR, 4'h8,
                  32'hAABB_CCDD, 4'b0101, RESP_OKAY);
        axi_read (0, 32'h0000_0080, 8'd0, BURST_INCR, 4'h9, RESP_OKAY);

        // Simultaneous requesters exercise round-robin ownership locking.
        fork
            axi_write(0, 32'h0000_0100, 8'd7, BURST_INCR, 4'hA,
                      32'h4000_0000, 4'hF, RESP_OKAY);
            axi_write(1, 32'h0001_0100, 8'd7, BURST_INCR, 4'hB,
                      32'h5000_0000, 4'hF, RESP_OKAY);
        join
        fork
            axi_read(0, 32'h0001_0100, 8'd7, BURST_INCR, 4'hC, RESP_OKAY);
            axi_read(1, 32'h0000_0100, 8'd7, BURST_INCR, 4'hD, RESP_OKAY);
        join

        // Read and write datapaths progress independently.
        fork
            axi_write(0, 32'h0000_0200, 8'd15, BURST_INCR, 4'hE,
                      32'h6000_0000, 4'hF, RESP_OKAY);
            axi_read(1, 32'h0001_0100, 8'd7, BURST_INCR, 4'hF, RESP_OKAY);
        join
        axi_read(1, 32'h0000_0200, 8'd15, BURST_INCR, 4'h0, RESP_OKAY);

        // Maximum-length AXI4 INCR burst (256 beats) remains inside one 4-KiB region.
        axi_write(0, 32'h0000_0400, 8'hFF, BURST_INCR, 4'h1,
                  32'h7000_0000, 4'hF, RESP_OKAY);
        axi_read (1, 32'h0000_0400, 8'hFF, BURST_INCR, 4'h2, RESP_OKAY);

        // Decode and subordinate validation failures complete deterministically.
        axi_write(0, 32'h0002_0000, 8'd3, BURST_INCR, 4'h1,
                  32'hDEAD_0000, 4'hF, RESP_DECERR);
        axi_read (1, 32'h0002_0000, 8'd3, BURST_INCR, 4'h2, RESP_DECERR);
        axi_read (0, 32'h0000_2000, 8'd3, BURST_INCR, 4'h3, RESP_SLVERR);
        axi_read (1, 32'h0000_0002, 8'd0, BURST_INCR, 4'h4, RESP_SLVERR);
        axi_read (0, 32'h0000_0040, 8'd2, BURST_WRAP, 4'h5, RESP_SLVERR);
        axi_read (1, 32'h0000_0000, 8'd0, BURST_INCR, 4'h6, RESP_SLVERR, 3'd1);
        axi_write(0, 32'h0000_00C0, 8'd1, BURST_INCR, 4'h7,
                  32'hBAD0_0000, 4'hF, RESP_SLVERR, 1'b1);

        // Complete legal WRAP-length coverage and FIXED length boundary.
        axi_write(0,32'h0000_0104,8'd1,BURST_WRAP,4'h1,32'h8100_0000,4'hF,RESP_OKAY);
        axi_read(1,32'h0000_0104,8'd1,BURST_WRAP,4'h1,RESP_OKAY);
        axi_write(0,32'h0000_011C,8'd7,BURST_WRAP,4'h2,32'h8200_0000,4'hF,RESP_OKAY);
        axi_read(1,32'h0000_011C,8'd7,BURST_WRAP,4'h2,RESP_OKAY);
        axi_write(0,32'h0000_013C,8'd15,BURST_WRAP,4'h3,32'h8300_0000,4'hF,RESP_OKAY);
        axi_read(1,32'h0000_013C,8'd15,BURST_WRAP,4'h3,RESP_OKAY);
        axi_write(0,32'h0000_0180,8'd15,BURST_FIXED,4'h4,32'h8400_0000,4'hF,RESP_OKAY);
        axi_read(1,32'h0000_0180,8'd15,BURST_FIXED,4'h4,RESP_OKAY);
        axi_write(0,32'h0000_0180,8'd16,BURST_FIXED,4'h5,32'hBAD0_0000,4'hF,RESP_SLVERR);
        axi_read(1,32'h0000_0180,8'd16,BURST_FIXED,4'h5,RESP_SLVERR);
        // Last aligned beat is legal; crossing a 4-KiB page is rejected.
        axi_write(0,32'h0000_0FFC,8'd0,BURST_INCR,4'h6,32'h8600_0000,4'hF,RESP_OKAY);
        axi_read(1,32'h0000_0FFC,8'd0,BURST_INCR,4'h6,RESP_OKAY);
        axi_write(0,32'h0000_0FFC,8'd1,BURST_INCR,4'h7,32'hBAD0_0000,4'hF,RESP_SLVERR);
        axi_read(1,32'h0000_0FFC,8'd1,BURST_INCR,4'h7,RESP_SLVERR);
        axi_write(0,32'h0000_0190,8'd0,BURST_INCR,4'h8,32'hBAD0_0000,4'hF,RESP_SLVERR,0,3'd1);
        axi_write(0,32'h0000_0192,8'd0,BURST_INCR,4'h9,32'hBAD0_0000,4'hF,RESP_SLVERR);
        axi_write(0,32'h0000_0190,8'd0,2'b11,4'hA,32'hBAD0_0000,4'hF,RESP_SLVERR);
        axi_read(1,32'h0000_0190,8'd0,2'b11,4'hA,RESP_SLVERR);

        if (failures != 0)
            $fatal(1, "BURST REGRESSION FAILED: %0d of %0d checks", failures, checks);
        $display("BURST REGRESSION PASS: %0d checks", checks);
        $finish;
    end
endmodule
