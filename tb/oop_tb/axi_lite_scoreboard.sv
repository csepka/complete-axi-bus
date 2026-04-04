`timescale 1ns/1ps

class axi_lite_scoreboard #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NS = 3,
    parameter DEPTH_WORDS = 1024
);

    logic [DATA_W-1:0] model_mem [NS][DEPTH_WORDS];
    int checks_total;
    int checks_failed;

    function new();
        checks_total = 0;
        checks_failed = 0;
    endfunction

    function int addr_to_sid(logic [ADDR_W-1:0] a);
        case (a[19:16])
            4'h0: return 0;
            4'h1: return 1;
            4'h2: return 2;
            default: return 0;
        endcase
    endfunction

    function int addr_to_widx(logic [ADDR_W-1:0] a);
        return (a >> 2) % DEPTH_WORDS;
    endfunction

    function void init_model();
        for (int s = 0; s < NS; s++)
            for (int i = 0; i < DEPTH_WORDS; i++)
                model_mem[s][i] = 0;
    endfunction

    function void update_model(logic [ADDR_W-1:0] addr, logic [DATA_W-1:0] data);
        int sid = addr_to_sid(addr);
        int widx = addr_to_widx(addr);
        model_mem[sid][widx] = data;
    endfunction

    function void check_read(logic [ADDR_W-1:0] addr, logic [DATA_W-1:0] rdata);
        int sid = addr_to_sid(addr);
        int widx = addr_to_widx(addr);
        logic [DATA_W-1:0] exp = model_mem[sid][widx];
        checks_total++;
        if (rdata !== exp) begin
            checks_failed++;
            $error("Scoreboard: addr=0x%08x exp=0x%08x got=0x%08x", addr, exp, rdata);
        end
    endfunction

    function void report();
        if (checks_failed == 0)
            $display("Scoreboard PASS: %0d checks", checks_total);
        else
            $display("Scoreboard FAIL: %0d/%0d", checks_failed, checks_total);
    endfunction

endclass