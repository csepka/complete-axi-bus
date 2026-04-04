`timescale 1ns/1ps

module axi_lite_tb_top_oop #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NM = 3,
    parameter NS = 3,
    parameter BYTES = DATA_W/8,
    parameter PERIOD = 10,
    parameter MEM_BYTES = 256
) ();

    logic ACLK, ARESETn;

    logic w_cmd_ready, w_cmd_done;
    logic [DATA_W-1:0] w_cmd_rdata;

    cmd_if #(ADDR_W, DATA_W) cif(ACLK);

    axi_top #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .NM(NM), .NS(NS)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .mgr_sel(cif.mgr_sel),
        .cmd_valid(cif.cmd_valid),
        .cmd_write(cif.cmd_write),
        .cmd_addr(cif.cmd_addr),
        .cmd_wdata(cif.cmd_wdata),
        .cmd_ready(w_cmd_ready),
        .cmd_done(w_cmd_done),
        .cmd_rdata(w_cmd_rdata)
    );

    initial forever begin
        @(posedge ACLK);
        #1;
        cif.cmd_ready = w_cmd_ready;
        cif.cmd_done = w_cmd_done;
        cif.cmd_rdata = w_cmd_rdata;
    end

    initial begin
        ACLK = 0;
        forever #(PERIOD/2) ACLK = ~ACLK;
    end

    localparam DEPTH_WORDS = MEM_BYTES / BYTES;

    initial begin
        axi_lite_env #(ADDR_W, DATA_W, NM, NS, DEPTH_WORDS) env;
        axi_lite_test #(ADDR_W, DATA_W, NM, NS, DEPTH_WORDS) t;
        $dumpfile("sim/oop_tb.vcd");
        $dumpvars(0, axi_lite_tb_top_oop);
        env = new();
        t = new(env);
        t.vif = cif;
        t.run(ARESETn);
        repeat (5) @(posedge ACLK);
        $finish;
    end

endmodule