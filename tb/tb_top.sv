`timescale 1ns/1ps


module tb_top  #( parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NM = 3,
    parameter NS = 3,
    parameter BYTES = (DATA_W/8),
    parameter PERIOD = 10,

    parameter MEM_BYTES = 4096

)();
    logic ACLK;
    logic ARESETn;

    logic [1:0] mgr_sel;
    logic cmd_valid;
    logic cmd_write;
    logic [ADDR_W-1:0] cmd_addr;
    logic [DATA_W-1:0] cmd_wdata;

    logic cmd_ready;
    logic cmd_done;
    logic [DATA_W-1:0] cmd_rdata;


    initial begin
        ACLK = 1'b0;
        forever #(PERIOD/2) ACLK = ~ACLK;
    end

    

    axi_top #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .NM(NM),
        .NS(NS)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .mgr_sel(mgr_sel),
        .cmd_valid(cmd_valid),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_ready(cmd_ready),
        .cmd_done(cmd_done),
        .cmd_rdata(cmd_rdata)
    );

    localparam DEPTH_WORDS = MEM_BYTES / BYTES;

    // model memory for the subordinates
    logic [DATA_W-1:0] model_mem [NS][DEPTH_WORDS];

    // address decode
    function automatic int addr_to_sid(input logic [ADDR_W-1:0] a);
        case (a[19:16])
            4'h0: return 0;
            4'h1: return 1;
            4'h2: return 2;
            default: return 0;
        endcase    
    endfunction

    function automatic int addr_to_widx(input logic [ADDR_W-1:0] a);
        return (a >> 2) % DEPTH_WORDS;
    endfunction

    int checks_total, checks_failed;

    task automatic check(input bit cond, input string msg);
        checks_total++;
        if (!cond) begin
            checks_failed++;
            $error("CHECK FAILED: %s", msg);
        end
    endtask

    task automatic init_model;
        for (int s = 0; s <NS; s++)
            for (int i = 0; i < DEPTH_WORDS; i++)
            model_mem[s][i] = 0;
    endtask

    task automatic init_drives;
        mgr_sel = 0;
        cmd_valid = 1'b0;
        cmd_write = 1'b0;
        cmd_addr = 0;
        cmd_wdata = 0;
    endtask

    task automatic do_reset;
        ARESETn = 1'b0;
        init_drives();
        init_model();
        repeat (5) @(posedge ACLK);
        ARESETn = 1'b1;
        @(posedge ACLK);
    endtask

    task automatic do_cmd(
        input logic [1:0] sel,
        input bit is_write,
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] wdata,
        output logic [DATA_W-1:0] rdata
    );
        while (!cmd_ready) @(posedge ACLK);

        mgr_sel = sel;
        cmd_write = is_write;
        cmd_addr = addr;
        cmd_wdata = wdata;
        cmd_valid = 1'b1;
        @(posedge ACLK);
        cmd_valid = 1'b0;

        while (!cmd_done) @(posedge ACLK);
        rdata = cmd_rdata;
        @(posedge ACLK);
    endtask

    // writing to the memory model
    task automatic sb_write(
        input logic [1:0] sel,
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data
    );
        logic [DATA_W-1:0] blank;
        int sid, widx;
        begin
            do_cmd(sel, 1'b1, addr, data, blank);
            sid = addr_to_sid(addr);
            widx = addr_to_widx(addr);
            model_mem[sid][widx] = data;
        end
    endtask

    task automatic sb_read_check(
        input logic [1:0] sel,
        input logic [ADDR_W-1:0] addr
    );
        logic [DATA_W-1:0] rd;
        int sid, widx;
        begin
            do_cmd(sel, 1'b0, addr, 0, rd);
            sid = addr_to_sid(addr);
            widx = addr_to_widx(addr);
            check(rd === model_mem[sid][widx],
                $sformatf("Read mismatch sel=%0d addr=0x%08x exp=0x%08x got=0x%08x",
                sel, addr, model_mem[sid][widx], rd));
        end
    endtask

    task automatic test_directed;
    begin
        sb_write(2'd0, 32'h0000_000C, 32'h1111_000C);
        sb_read_check(2'd0, 32'h0000_000C);

        sb_write(2'd1, 32'h0001_0010, 32'h2222_0010);
        sb_read_check(2'd1, 32'h0001_0010);

        sb_write(2'd2, 32'h0002_0004, 32'h3333_0004);
        sb_read_check(2'd2, 32'h0002_0004);

        sb_write(2'd0, 32'h0000_0014, 32'hAAAA_0014);
        sb_write(2'd0, 32'h0000_0018, 32'hBBBB_0018);
        sb_read_check(2'd0, 32'h0000_0014);
        sb_read_check(2'd0, 32'h0000_0018);

    end
    endtask

    // maybe include another set of randomized tests

    //Below is the main execution block
    initial begin
        $dumpfile("sim/tb_top.vcd");
        $dumpvars(0, tb_top);

        checks_total = 0;
        checks_failed = 0;

        do_reset();

        test_directed();

        if (checks_failed == 0)
            $display("PASS: %0d checks", checks_total);
        else
            $fatal(1, "FAIL: %0d/%0d checks failed", checks_failed, checks_total);

        repeat (5) @(posedge ACLK);
        $finish;
    end

endmodule