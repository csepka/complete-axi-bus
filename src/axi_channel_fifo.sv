// Two-entry elastic channel stage. READY depends only on registered occupancy;
// VALID and payload depend only on stored state. No combinational path crosses
// the stage in either direction. Full + pop does not also accept a push, so a
// full stage has one recovery bubble; occupancy one sustains a beat per cycle.
module axi_channel_fifo #(
    parameter int WIDTH = 32
) (
    input  logic             ACLK,
    input  logic             ARESETn,
    input  logic             in_valid,
    output logic             in_ready,
    input  logic [WIDTH-1:0] in_payload,
    output logic             out_valid,
    input  logic             out_ready,
    output logic [WIDTH-1:0] out_payload
);
    logic [WIDTH-1:0] payload [0:1];
    logic head, tail;
    logic [1:0] count;
    wire push = in_valid && in_ready;
    wire pop = out_valid && out_ready;

    assign in_ready = ARESETn && count < 2;
    assign out_valid = ARESETn && count != 0;
    assign out_payload = payload[head];

    always_ff @(posedge ACLK) begin
        if (push) payload[tail] <= in_payload;
    end
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            head <= 0;
            tail <= 0;
            count <= 0;
        end else begin
            if (push) tail <= !tail;
            if (pop) head <= !head;
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial assert (WIDTH > 0) else $fatal(1, "WIDTH must be positive");
    ap_bound: assert property (@(posedge ACLK) disable iff (!ARESETn) count <= 2);
    ap_stable: assert property (@(posedge ACLK) disable iff (!ARESETn)
        out_valid && !out_ready |=> out_valid && $stable(out_payload));
`endif
endmodule
