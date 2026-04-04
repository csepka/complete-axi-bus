`timescale 1ns/1ps

typedef struct packed {
    logic [1:0] mgr_sel;
    logic is_write;
    logic [31:0] addr;
    logic [31:0] data;
} cmd_txn_t;

class axi_lite_monitor #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NM = 3
);
    virtual cmd_if #(ADDR_W, DATA_W) vif;
    mailbox #(cmd_txn_t) txn_mbx;
    int txn_count;

    cmd_txn_t pending [NM];
    bit pending_valid [NM];

    function new(mailbox #(cmd_txn_t) mbx);
        txn_mbx = mbx;
        txn_count = 0;
        for (int m = 0; m < NM; m++) begin
            pending_valid[m] = 0;
            pending[m] = 0;
        end

    endfunction

    task run();
        int msel;
        cmd_txn_t t;

        forever begin
            @(posedge vif.ACLK);

            if (vif.cmd_valid && vif.cmd_ready) begin
                msel = int'($unsigned(vif.mgr_sel));
                if (msel >= 0 && msel < NM) begin
                    pending_valid[msel] = 1'b1;
                    pending[msel].mgr_sel = vif.mgr_sel;
                    pending[msel].is_write = vif.cmd_write;
                    pending[msel].addr = vif.cmd_addr;
                    pending[msel].data = vif.cmd_wdata;
                end
            end


            if (vif.cmd_done) begin
                msel = int'($unsigned(vif.mgr_sel));
                if (msel >= 0 && msel < NM && pending_valid[msel]) begin
                    t = pending[msel];
                    if (!t.is_write) t.data = vif.cmd_rdata;
                        txn_mbx.put(t);
                        txn_count++;
                        pending_valid[msel] = 1'b0;
                end
                // t.mgr_sel = vif.mgr_sel;
                // t.is_write = 1'b0;
                // t.addr = vif.cmd_addr;
                // txn_mbx.put(t);
                // txn_count++;
            end
        end
    endtask
endclass