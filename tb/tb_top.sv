`timescale 1ns/1ps

module tb_top;
    localparam int ADDR_W       = 32;
    localparam int DATA_W       = 32;
    localparam int ID_W         = 4;
    localparam int NM           = 3;
    localparam int NS           = 3;
    localparam int MGR_SEL_W    = $clog2(NM);
    localparam int S_ADDR_WIDTH = 16;
    localparam int MEM_BYTES    = 4096;
    localparam int WORDS        = MEM_BYTES / (DATA_W/8);
    localparam int TIMEOUT      = 2000;

    logic ACLK;
    logic ARESETn;
    logic [MGR_SEL_W-1:0] mgr_sel;
    logic cmd_valid;
    logic cmd_write;
    logic [ADDR_W-1:0] cmd_addr;
    logic [DATA_W-1:0] cmd_wdata;
    logic cmd_ready;
    logic cmd_done;
    logic [DATA_W-1:0] cmd_rdata;
    logic [1:0] cmd_resp;

    logic [DATA_W-1:0] model [0:NS-1][0:WORDS-1];
    integer checks;
    integer failures;

    initial begin
        ACLK = 1'b0;
        forever #5 ACLK = ~ACLK;
    end

    axi_top #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .NM(NM),
        .NS(NS),
        .S_ADDR_WIDTH(S_ADDR_WIDTH),
        .MEM_BYTES(MEM_BYTES)
    ) dut (.*);

    task automatic check_result(input logic condition, input string message);
        checks = checks + 1;
        if (!condition) begin
            failures = failures + 1;
            $error("CHECK FAILED: %s", message);
        end
    endtask

    task automatic reset_dut;
        ARESETn = 1'b0;
        mgr_sel = '0;
        cmd_valid = 1'b0;
        cmd_write = 1'b0;
        cmd_addr = '0;
        cmd_wdata = '0;
        for (integer s = 0; s < NS; s = s + 1)
            for (integer w = 0; w < WORDS; w = w + 1)
                model[s][w] = '0;
        repeat (5) @(posedge ACLK);
        ARESETn = 1'b1;
        repeat (2) @(posedge ACLK);
    endtask

    task automatic command(
        input  integer manager,
        input  logic is_write,
        input  logic [ADDR_W-1:0] address,
        input  logic [DATA_W-1:0] write_data,
        output logic [DATA_W-1:0] read_data,
        output logic [1:0] response
    );
        integer cycles;
        cycles = 0;
        mgr_sel = MGR_SEL_W'(manager);
        while (!cmd_ready && cycles < TIMEOUT) begin
            @(posedge ACLK);
            cycles = cycles + 1;
        end
        if (cycles == TIMEOUT)
            $fatal(1, "Timeout waiting for command readiness");

        @(negedge ACLK);
        cmd_write = is_write;
        cmd_addr = address;
        cmd_wdata = write_data;
        cmd_valid = 1'b1;
        @(posedge ACLK);
        @(negedge ACLK);
        cmd_valid = 1'b0;
        // Completion must remain associated with the accepted command, not live selection.
        mgr_sel = MGR_SEL_W'((manager + 1) % NM);

        cycles = 0;
        while (!cmd_done && cycles < TIMEOUT) begin
            @(posedge ACLK);
            cycles = cycles + 1;
        end
        if (cycles == TIMEOUT)
            $fatal(1, "Timeout waiting for command completion: manager=%0d addr=%h", manager, address);
        read_data = cmd_rdata;
        response = cmd_resp;
        @(negedge ACLK);
    endtask

    task automatic write_word(
        input integer manager,
        input integer subordinate,
        input integer word,
        input logic [DATA_W-1:0] data
    );
        logic [DATA_W-1:0] unused;
        logic [1:0] response;
        logic [ADDR_W-1:0] address;
        address = (subordinate << S_ADDR_WIDTH) | (word * (DATA_W/8));
        command(manager, 1'b1, address, data, unused, response);
        check_result(response == 2'b00, $sformatf("write response manager=%0d address=%h", manager, address));
        model[subordinate][word] = data;
    endtask

    task automatic read_word(
        input integer manager,
        input integer subordinate,
        input integer word
    );
        logic [DATA_W-1:0] data;
        logic [1:0] response;
        logic [ADDR_W-1:0] address;
        address = (subordinate << S_ADDR_WIDTH) | (word * (DATA_W/8));
        command(manager, 1'b0, address, '0, data, response);
        check_result(response == 2'b00, $sformatf("read response manager=%0d address=%h", manager, address));
        check_result(data === model[subordinate][word],
               $sformatf("read data manager=%0d address=%h check_resulted=%h actual=%h",
                         manager, address, model[subordinate][word], data));
    endtask

    initial begin
        logic [DATA_W-1:0] data;
        logic [1:0] response;
        integer manager;
        integer subordinate;
        integer word;
        logic [DATA_W-1:0] value;

        checks = 0;
        failures = 0;
        reset_dut();

        // Directed routing and isolation checks across every endpoint.
        for (manager = 0; manager < NM; manager = manager + 1)
            for (subordinate = 0; subordinate < NS; subordinate = subordinate + 1) begin
                word = (manager * NS) + subordinate;
                value = 32'hA500_0000 | (manager << 8) | subordinate;
                write_word(manager, subordinate, word, value);
                read_word((manager + 1) % NM, subordinate, word);
            end

        // Unmapped windows terminate locally with DECERR.
        command(0, 1'b1, 32'h0003_0000, 32'hDEAD_BEEF, data, response);
        check_result(response == 2'b11, "unmapped write must return DECERR");
        command(1, 1'b0, 32'h0003_0040, '0, data, response);
        check_result(response == 2'b11, "unmapped read must return DECERR");
        check_result(data == '0, "unmapped read data must be zero");

        // A mapped address outside implemented RAM terminates with SLVERR.
        command(2, 1'b0, 32'h0000_2000, '0, data, response);
        check_result(response == 2'b10, "out-of-range RAM read must return SLVERR");

        // Invalid command-port manager selections are rejected without side effects.
        mgr_sel = MGR_SEL_W'(3);
        cmd_valid = 1'b1;
        @(posedge ACLK);
        check_result(!cmd_ready && !cmd_done, "invalid manager selection must be rejected");
        cmd_valid = 1'b0;

        // Reproducible pseudo-random traffic checks address isolation and arbitration state.
        void'($urandom(32'h41A5_C0DE));
        for (integer n = 0; n < 250; n = n + 1) begin
            manager = $urandom_range(0, NM-1);
            subordinate = $urandom_range(0, NS-1);
            word = $urandom_range(0, WORDS-1);
            if ($urandom_range(0, 1) != 0) begin
                value = $urandom;
                write_word(manager, subordinate, word, value);
            end else begin
                read_word(manager, subordinate, word);
            end
        end

        if (failures != 0)
            $fatal(1, "TOP REGRESSION FAILED: %0d of %0d checks", failures, checks);
        $display("TOP REGRESSION PASS: %0d checks", checks);
        $finish;
    end
endmodule
