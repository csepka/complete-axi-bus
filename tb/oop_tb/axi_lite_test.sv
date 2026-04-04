`timescale 1ns/1ps

class axi_lite_test #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NM = 3,
    parameter NS = 3,
    parameter DEPTH_WORDS = 1024,
    parameter RAND_SEED = 531
);
    axi_lite_env #(ADDR_W, DATA_W, NM, NS, DEPTH_WORDS) env;
    virtual cmd_if #(ADDR_W, DATA_W) vif;
    logic [ADDR_W-1:0] rst_arstn;
    event reset_done;

    function new(axi_lite_env #(ADDR_W, DATA_W, NM, NS, DEPTH_WORDS) e);
        env = e;
    endfunction

    function logic [ADDR_W-1:0] mk_addr(int sid, int widx);
        return {12'h0, 4'(sid), 14'(widx), 2'b00};
    endfunction

    task do_reset(ref logic ARESETn);
        ARESETn = 1'b0;
        env.drv.vif.mgr_sel = 0;
        env.drv.vif.cmd_valid = 0;
        env.drv.vif.cmd_addr = 0;
        env.drv.vif.cmd_wdata = 0;
        repeat (5) @(posedge env.vif.ACLK);
        ARESETn = 1'b1;
        @(posedge env.vif.ACLK);
    endtask

    task run_100_random(ref logic ARESETn);
        logic [1:0] sel;
        int sid, widx;
        logic [ADDR_W-1:0] addr;
        logic [DATA_W-1:0] wdata, rdata;
        void'($urandom(RAND_SEED));
        for (int i = 0; i < 100; i++) begin
            sel = $urandom_range(0, NM-1);
            sid = $urandom_range(0, NS-1);
            widx = $urandom;
            addr = mk_addr(sid, widx);
            wdata = $urandom;
            env.drv.issue_cmd(sel, 1'b1, addr, wdata);
            env.drv.wait_done(sel, rdata);
            env.sb.update_model(addr, wdata);
            env.drv.issue_cmd(sel, 1'b0, addr, 0);
            env.drv.wait_done(sel, rdata);
            env.sb.check_read(addr, rdata);
        end
    endtask

    task run_5_round_robin(ref logic ARESETn);
        logic [DATA_W-1:0] rd;

        // RR1: three managers, each tries to write
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 0), 32'hA0A0_A0A0);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(1, 1), 32'hB1B1_B1B1);
        env.drv.issue_cmd(2'd2, 1'b1, mk_addr(2, 2), 32'hC2C2_C2C2);
        env.drv.wait_done(2'd0, rd);
        env.sb.update_model(mk_addr(0, 0), 32'hA0A0_A0A0);
        env.drv.wait_done(2'd1, rd);
        env.sb.update_model(mk_addr(1, 1), 32'hB1B1_B1B1);
        env.drv.wait_done(2'd2, rd);
        env.sb.update_model(mk_addr(2, 2), 32'hC2C2_C2C2);
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 0), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 0), rd);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(1, 1), 0);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(1, 1), rd);
        env.drv.issue_cmd(2'd2, 1'b0, mk_addr(2, 2), 0);
        env.drv.wait_done(2'd2, rd);
        env.sb.check_read(mk_addr(2, 2), rd);


        // RR2: two managers and two writes
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 10), 32'hDEAD_0000);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(1, 10), 32'hBEEF_0001);
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 11), 32'hDEAD_0011);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(1, 11), 32'hBEEF_0011);
        env.drv.wait_done(2'd0, rd);
        env.sb.update_model(mk_addr(0, 10), 32'hDEAD_0000);
        env.drv.wait_done(2'd1, rd);
        env.sb.update_model(mk_addr(1, 10), 32'hBEEF_0001);
        env.drv.wait_done(2'd0, rd);
        env.sb.update_model(mk_addr(0, 11), 32'hDEAD_0011);
        env.drv.wait_done(2'd1, rd);
        env.sb.update_model(mk_addr(1, 11), 32'hBEEF_0011);
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 10), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 10), rd);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(1, 10), 0);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(1, 10), rd);
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 11), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 11), rd);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(1, 11), 0);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(1, 11), rd);

        // RR3 interleave 0, 1, 2, 0, 1, 2
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 20), 32'h1111_1111);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(1, 20), 32'h2222_2222);
        env.drv.issue_cmd(2'd2, 1'b1, mk_addr(2, 20), 32'h3333_3333);
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 21), 32'h4444_4444);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(1, 21), 32'h5555_5555);
        env.drv.issue_cmd(2'd2, 1'b1, mk_addr(2, 21), 32'h6666_6666);
        for (int m = 0; m < 3; m++) begin
            env.drv.wait_done(2'(m), rd);
            env.sb.update_model(mk_addr(m, 20), (m==0)?32'h1111_1111:(m==1)?32'h2222_2222:32'h3333_3333);
        end
        for (int m = 0; m < 3; m++) begin
            env.drv.wait_done(2'(m), rd);
            env.sb.update_model(mk_addr(m, 21), (m==0)?32'h4444_4444:(m==1)?32'h5555_5555:32'h6666_6666);
        end
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 20), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 20), rd);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(1, 20), 0);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(1, 20), rd);
        env.drv.issue_cmd(2'd2, 1'b0, mk_addr(2, 20), 0);
        env.drv.wait_done(2'd2, rd);
        env.sb.check_read(mk_addr(2, 20), rd);
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 21), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 21), rd);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(1, 21), 0);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(1, 21), rd);
        env.drv.issue_cmd(2'd2, 1'b0, mk_addr(2, 21), 0);
        env.drv.wait_done(2'd2, rd);
        env.sb.check_read(mk_addr(2, 21), rd);




        // RR4 two masters read after write
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 30), 32'hBEAD_FE00);
        env.drv.wait_done(2'd0, rd);
        env.sb.update_model(mk_addr(0, 30), 32'hBEAD_FE00);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(1, 30), 32'hBEAD_FE01);
        env.drv.wait_done(2'd1, rd);
        env.sb.update_model(mk_addr(1, 30), 32'hBEAD_FE01);
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 30), 0);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(1, 30), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 30), rd);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(1, 30), rd);

        // RR5 all three write to same sub
        env.drv.issue_cmd(2'd0, 1'b1, mk_addr(0, 40), 32'hF0F0_4040);
        env.drv.issue_cmd(2'd1, 1'b1, mk_addr(0, 41), 32'hF1F1_4141);
        env.drv.issue_cmd(2'd2, 1'b1, mk_addr(0, 42), 32'hF2F2_4242);
        env.drv.wait_done(2'd0, rd);
        env.sb.update_model(mk_addr(0, 40), 32'hF0F0_4040);
        env.drv.wait_done(2'd1, rd);
        env.sb.update_model(mk_addr(0, 41), 32'hF1F1_4141);
        env.drv.wait_done(2'd2, rd);
        env.sb.update_model(mk_addr(0, 42), 32'hF2F2_4242);
        env.drv.issue_cmd(2'd0, 1'b0, mk_addr(0, 40), 0);
        env.drv.wait_done(2'd0, rd);
        env.sb.check_read(mk_addr(0, 40), rd);
        env.drv.issue_cmd(2'd1, 1'b0, mk_addr(0, 41), 0);
        env.drv.wait_done(2'd1, rd);
        env.sb.check_read(mk_addr(0, 41), rd);
        env.drv.issue_cmd(2'd2, 1'b0, mk_addr(0, 42), 0);
        env.drv.wait_done(2'd2, rd);
        env.sb.check_read(mk_addr(0, 42), rd);



    endtask

    task run(ref logic ARESETn);
        env.connect(vif);
        env.build();
        env.run_test();
        do_reset(ARESETn);
        run_100_random(ARESETn);
        run_5_round_robin(ARESETn);
        env.sb.report();
        if (env.sb.checks_failed != 0)
            $fatal(1, "TEST FAIL: %0d errors", env.sb.checks_failed);
    endtask
endclass