`timescale 1ns/1ps

class axi_lite_driver #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
);
    virtual cmd_if #(ADDR_W, DATA_W) vif;
    int num_issued;
    int num_done;

    function new();
        num_issued = 0;
        num_done = 0;
    endfunction

    task issue_cmd(input logic [1:0] sel, input bit is_write,
                   input logic [ADDR_W-1:0] addr, input logic [DATA_W-1:0] wdata);
        vif.mgr_sel <= sel;
        @(posedge vif.ACLK);
        while (vif.cmd_ready !== 1'b1) @(posedge vif.ACLK);
        vif.cmd_write <= is_write;
        vif.cmd_addr <= addr;
        vif.cmd_wdata <= wdata;
        vif.cmd_valid <= 1'b1;
        @(posedge vif.ACLK);
        vif.cmd_valid <= 1'b0;
        num_issued++;
    endtask

    task wait_done(input logic [1:0] sel, output logic [DATA_W-1:0] rdata);
        vif.mgr_sel <= sel;
        @(posedge vif.ACLK);
        while (vif.cmd_done !== 1'b1) @(posedge vif.ACLK);
        rdata = vif.cmd_rdata;
        @(posedge vif.ACLK);
        num_done++;
    endtask

endclass