`timescale 1ns/1ps

module axi_lite_sub_tb;
    localparam int ADDR_W = 32;
    localparam int DATA_W = 32;
    localparam int DEPTH  = 128;
    localparam time CLK_PERIOD = 10ns;

    logic ACLK;
    logic ARESETn;

    logic AWVALID;
    logic AWREADY;
    logic [ADDR_W-1:0] AWADDR;

    logic WVALID;
    logic WREADY;
    logic [DATA_W-1:0] WDATA;
    logic [DATA_W/8-1:0] WSTRB;

    logic BVALID;
    logic BREADY;

    logic ARVALID;
    logic ARREADY;
    logic [ADDR_W-1:0] ARADDR;

    logic RVALID;
    logic RREADY;
    logic [DATA_W-1:0] RDATA;

    logic [DATA_W-1:0] exp_mem [0:DEPTH-1];
    int checks_total;
    int checks_failed;

    axi_lite_sub #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .AWADDR(AWADDR),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .BVALID(BVALID),
        .BREADY(BREADY),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .ARADDR(ARADDR),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .RDATA(RDATA)
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
            AWVALID = 1'b0;
            AWADDR  = '0;
            WVALID  = 1'b0;
            WDATA   = '0;
            WSTRB   = '0;
            BREADY  = 1'b0;
            ARVALID = 1'b0;
            ARADDR  = '0;
            RREADY  = 1'b0;
        end
    endtask

    task automatic init_exp_mem;
        int i;
        begin
            for (i = 0; i < DEPTH; i++) begin
                exp_mem[i] = '0;
            end
        end
    endtask

    task automatic do_reset;
        begin
            ARESETn = 1'b0;
            init_drives();
            init_exp_mem();
            repeat (4) @(posedge ACLK);
            ARESETn = 1'b1;
            @(posedge ACLK);
        end
    endtask

    task automatic write_addr_phase(
        input logic [ADDR_W-1:0] addr,
        input int delay_cycles
    );
        int timeout;
        begin
            repeat (delay_cycles) @(posedge ACLK);
            AWADDR  <= addr;
            AWVALID <= 1'b1;
            timeout = 0;
            while (!(AWVALID && AWREADY)) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "AW handshake timeout");
            end
            AWVALID <= 1'b0;
        end
    endtask

    task automatic write_data_phase(
        input logic [DATA_W-1:0] data,
        input logic [DATA_W/8-1:0] strb,
        input int delay_cycles
    );
        int timeout;
        begin
            repeat (delay_cycles) @(posedge ACLK);
            WDATA  <= data;
            WSTRB  <= strb;
            WVALID <= 1'b1;
            timeout = 0;
            while (!(WVALID && WREADY)) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "W handshake timeout");
            end
            WVALID <= 1'b0;
        end
    endtask

    task automatic write_response_phase(input int bready_delay);
        int timeout;
        begin
            BREADY <= 1'b0;
            repeat (bready_delay) @(posedge ACLK);
            BREADY <= 1'b1;
            timeout = 0;
            while (!BVALID) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "BVALID timeout");
            end
            @(posedge ACLK);
            BREADY <= 1'b0;
        end
    endtask

    task automatic issue_write_no_resp(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data,
        input logic [DATA_W/8-1:0] strb,
        input int aw_delay,
        input int w_delay
    );
        begin
            fork
                write_addr_phase(addr, aw_delay);
                write_data_phase(data, strb, w_delay);
            join
        end
    endtask

    task automatic axi_write(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data,
        input logic [DATA_W/8-1:0] strb,
        input int aw_delay,
        input int w_delay,
        input int bready_delay
    );
        begin
            issue_write_no_resp(addr, data, strb, aw_delay, w_delay);
            write_response_phase(bready_delay);
            exp_mem[addr] = data;
        end
    endtask

    task automatic axi_read(
        input logic [ADDR_W-1:0] addr,
        input int ar_delay,
        input int rready_delay,
        output logic [DATA_W-1:0] data
    );
        int timeout;
        begin
            repeat (ar_delay) @(posedge ACLK);
            ARADDR  <= addr;
            ARVALID <= 1'b1;
            timeout = 0;
            while (!(ARVALID && ARREADY)) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "AR handshake timeout");
            end
            ARVALID <= 1'b0;

            RREADY <= 1'b0;
            repeat (rready_delay) @(posedge ACLK);
            RREADY <= 1'b1;
            timeout = 0;
            while (!RVALID) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "RVALID timeout");
            end
            data = RDATA;
            @(posedge ACLK);
            RREADY <= 1'b0;
        end
    endtask

    task automatic test_write_and_read(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data,
        input int aw_delay,
        input int w_delay
    );
        logic [DATA_W-1:0] rd;
        begin
            axi_write(addr, data, '1, aw_delay, w_delay, 0);
            axi_read(addr, 0, 0, rd);
            check(rd === exp_mem[addr], $sformatf("Readback mismatch at addr=%0d", addr));
        end
    endtask

    task automatic test_b_backpressure;
        int timeout;
        begin
            issue_write_no_resp(32'd21, 32'hBEEF_0021, '1, 0, 0);
            exp_mem[21] = 32'hBEEF_0021;

            timeout = 0;
            while (!BVALID) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "BVALID timeout in backpressure test");
            end

            repeat (3) begin
                @(posedge ACLK);
                check(BVALID === 1'b1, "BVALID must stay high while BREADY is low");
            end

            BREADY <= 1'b1;
            @(posedge ACLK);
            BREADY <= 1'b0;
            @(posedge ACLK);
            check(BVALID === 1'b0, "BVALID should clear after response handshake");
        end
    endtask

    task automatic test_r_backpressure;
        logic [DATA_W-1:0] rd;
        int timeout;
        begin
            axi_write(32'd25, 32'hCAFE_0025, '1, 0, 0, 0);

            ARADDR  <= 32'd25;
            ARVALID <= 1'b1;
            timeout = 0;
            while (!(ARVALID && ARREADY)) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "AR timeout in backpressure test");
            end
            ARVALID <= 1'b0;
            RREADY  <= 1'b0;

            timeout = 0;
            while (!RVALID) begin
                @(posedge ACLK);
                timeout++;
                if (timeout > 100) $fatal(1, "RVALID timeout in backpressure test");
            end

            repeat (3) begin
                @(posedge ACLK);
                check(RVALID === 1'b1, "RVALID must stay high while RREADY is low");
            end

            RREADY <= 1'b1;
            rd = RDATA;
            @(posedge ACLK);
            RREADY <= 1'b0;
            @(posedge ACLK);

            check(rd === exp_mem[25], "RDATA mismatch in read backpressure test");
            check(RVALID === 1'b0, "RVALID should clear after read handshake");
        end
    endtask

    initial begin
        logic [DATA_W-1:0] rd_data;

        $dumpfile("tb/axi_lite_sub_tb.vcd");
        $dumpvars(0, axi_lite_sub_tb);

        ACLK = 1'b0;
        checks_total = 0;
        checks_failed = 0;

        do_reset();
        check(BVALID === 1'b0, "BVALID should be low after reset");
        check(RVALID === 1'b0, "RVALID should be low after reset");
        check(AWREADY === 1'b1, "AWREADY should be high after reset");
        check(WREADY === 1'b1, "WREADY should be high after reset");
        check(ARREADY === 1'b1, "ARREADY should be high after reset");

        test_write_and_read(32'd3, 32'hA5A5_0003, 0, 0);
        test_write_and_read(32'd7, 32'hA5A5_0007, 0, 3);
        test_write_and_read(32'd9, 32'hA5A5_0009, 3, 0);

        axi_read(32'd3, 2, 2, rd_data);
        check(rd_data === exp_mem[3], "Delayed read mismatch");

        test_b_backpressure();
        test_r_backpressure();

        if (checks_failed == 0) begin
            $display("PASS: %0d checks passed", checks_total);
        end else begin
            $fatal(1, "FAIL: %0d/%0d checks failed", checks_failed, checks_total);
        end

        repeat (2) @(posedge ACLK);
        $finish;
    end

endmodule
