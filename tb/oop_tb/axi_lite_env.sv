`timescale 1ns/1ps
class axi_lite_env #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NM = 3,
    parameter NS = 3,
    parameter DEPTH_WORDS = 1024
);
    virtual cmd_if #(ADDR_W, DATA_W) vif;
    axi_lite_driver #(ADDR_W, DATA_W) drv;
    axi_lite_monitor #(ADDR_W, DATA_W) mon;
    axi_lite_scoreboard #(ADDR_W, DATA_W, NS, DEPTH_WORDS) sb;
    mailbox #(cmd_txn_t) txn_mbx;

    function new();
        txn_mbx = new(8);
        sb = new();
        drv = new();
        mon = new(txn_mbx);
    endfunction

    function void build();
        sb.init_model();
    endfunction

    function void connect(virtual cmd_if #(ADDR_W, DATA_W) vi);
        vif = vi;
        drv.vif = vi;
        mon.vif = vi;
    endfunction

    task get_mail();
        cmd_txn_t t;
        forever begin
            txn_mbx.get(t);
            if (t.is_write)
                $display("[Mbx] mgr=%0d WRITE addr=0x%08x, data=0x%08x", t.mgr_sel, t.addr, t.data);
            else
                $display("[Mbx] mgr=%0d READ addr=0x%08x, data=0x%08x", t.mgr_sel, t.addr, t.data);
        end
    endtask

    task run_test();
        fork
            mon.run();
            get_mail();
        join_none
    endtask
   
endclass