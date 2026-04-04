`timescale 1ns/1ps

interface cmd_if #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
) (input logic ACLK);
    logic [1:0] mgr_sel;
    logic cmd_valid;
    logic cmd_write;
    logic [ADDR_W-1:0] cmd_addr;
    logic [DATA_W-1:0] cmd_wdata;
    logic cmd_ready;
    logic cmd_done;
    logic [DATA_W-1:0] cmd_rdata;

    // clocking drv_cb @(posedge ACLK); 
    //     output mgr_sel, cmd_valid, cmd_write, cmd_addr, cmd_wdata;
    //     input cmd_ready, cmd_done, cmd_rdata;
    // endclocking

    // clocking mon_cb @(posedge ACLK);
    //     input mgr_sel, cmd_valid, cmd_write, cmd_addr, cmd_wdata,
    //           cmd_ready, cmd_done, cmd_rdata;
    // endclocking
endinterface