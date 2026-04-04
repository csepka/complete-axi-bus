`timescale 1ns/1ps

module axi_lite_mgr_tb;
    localparam int ADDR_W = 32;
    localparam int DATA_W = 32;
    localparam time CLK_PERIOD = 10ns;

    logic ACLK;
    logic ARESETn;

    // AXI write address channel
    logic AWVALID;
    logic AWREADY;
    logic [2:0] AWPROT;
    logic [ADDR_W-1:0] AWADDR;

    // AXI write data channel
    logic WVALID;
    logic WREADY;
    logic [DATA_W-1:0] WDATA;
    logic [DATA_W/8-1:0] WSTRB;

    // AXI write response channel
    logic BVALID;
    logic BREADY;
    logic [1:0] BRESP;

    // AXI read address channel
    logic ARVALID;
    logic ARREADY;
    logic [ADDR_W-1:0] ARADDR;
    logic [2:0] ARPROT;

    // AXI read data channel
    logic RVALID;
    logic RREADY;
    logic [DATA_W-1:0] RDATA;
    logic [1:0] RRESP;

    // Command-side interface
    logic cmd_valid;
    logic cmd_write;
    logic [ADDR_W-1:0] cmd_addr;
    logic [DATA_W-1:0] cmd_wdata;
    logic cmd_ready;
    logic cmd_done;
    logic [DATA_W-1:0] cmd_rdata;

    int checks_total;
    int checks_failed;

    axi_lite_mgr #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .AWPROT(AWPROT),
        .AWADDR(AWADDR),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .BREADY(BREADY),
        .BVALID(BVALID),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .ARADDR(ARADDR),
        .ARPROT(ARPROT),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .RDATA(RDATA),
        .cmd_valid(cmd_valid),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_ready(cmd_ready),
        .cmd_done(cmd_done),
        .cmd_rdata(cmd_rdata)
    );

    axi_lite_sub #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) mem (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .AWADDR(AWADDR),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .BREADY(BREADY),
        .BVALID(BVALID),
        .BRESP(BRESP),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .ARADDR(ARADDR),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .RDATA(RDATA),
        .RRESP(RRESP)
    );

    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    task automatic check(input bit cond, input string msg);
        begin
            checks_total++;
            if (!cond) begin
                checks_failed++;
                $error("CHECK FAILED: %s (t=%0t)", msg, $time);
            end
        end
    endtask

    task automatic init_drives;
        begin
            cmd_valid = 1'b0;
            cmd_write = 1'b0;
            cmd_addr  = '0;
            cmd_wdata = '0;
        end
    endtask

    task automatic do_reset;
        begin
            ARESETn = 1'b0;
            init_drives();
            repeat (4) @(posedge ACLK);
            ARESETn = 1'b1;
            @(posedge ACLK);
        end
    endtask

    task automatic issue_cmd(
        input logic write_not_read,
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] wdata
    );
        int timeout;
        begin
            timeout = 0;
            while (!cmd_ready) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "cmd_ready timeout");
            end

            cmd_write <= write_not_read;
            cmd_addr  <= addr;
            cmd_wdata <= wdata;
            cmd_valid <= 1'b1;
            @(posedge ACLK);
            cmd_valid <= 1'b0;

            timeout = 0;
            while (!cmd_done) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "cmd_done timeout");
            end
        end
    endtask

    initial begin
        localparam logic [ADDR_W-1:0] TEST_ADDR = 32'h0000_0010;
        localparam logic [DATA_W-1:0] TEST_DATA = 32'hDEAD_BEEF;

        $dumpfile("tb/axi_lite_mgr_tb.vcd");
        $dumpvars(0, axi_lite_mgr_tb);

        ACLK = 1'b0;
        checks_total = 0;
        checks_failed = 0;

        do_reset();
        check(cmd_ready === 1'b1, "cmd_ready should be high after reset");

        issue_cmd(1'b1, TEST_ADDR, TEST_DATA); // write
        check(cmd_ready === 1'b1, "cmd_ready should return high after write");

        issue_cmd(1'b0, TEST_ADDR, '0); // read
        check(cmd_rdata === TEST_DATA, "Readback data mismatch");

        if (checks_failed == 0) begin
            $display("PASS: %0d checks passed", checks_total);
        end else begin
            $fatal(1, "FAIL: %0d/%0d checks failed", checks_failed, checks_total);
        end

        repeat (2) @(posedge ACLK);
        $finish;
    end

endmodule
