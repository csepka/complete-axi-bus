// Making this for AXI5-LITE
`timescale 1ns/1ps

module axi_lite_sub #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter int BYTES  = DATA_W/8,

    parameter int MEM_BYTES = 256 //reduced for PnR
)(
    input logic ACLK,
    input logic ARESETn,

    // Write address channel (AW)
    input logic AWVALID,
    output logic AWREADY,
    input logic [ADDR_W-1:0] AWADDR,


    // Write data channel (W)
    input logic WVALID,
    output logic WREADY,
    input logic [DATA_W-1:0] WDATA,
    input logic [DATA_W/8-1:0] WSTRB,


    // Write response channel (B)
    input logic BREADY,
    output logic BVALID,
    output logic [1:0]  BRESP,

    // Read address channel (AR)
    input logic ARVALID,
    output logic ARREADY,
    input logic [ADDR_W-1:0] ARADDR,

    // Read data channel (R)
    output logic RVALID,
    input logic RREADY,
    output logic [DATA_W-1:0] RDATA,
    output logic [1:0]   RRESP
);

    // memory parameters 
    localparam DEPTH = MEM_BYTES / BYTES; // e.g., 4096 / 4 = 1024 words
    localparam IDX_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    logic [DATA_W-1:0] regs [DEPTH];

    enum {W_IDLE, W_RESP} curr_write_state, next_write_state;
    enum {R_IDLE, R_RESP} curr_read_state, next_read_state;

    logic aw_pending, w_pending, ar_pending;

    // Write Address Latches
    logic [ADDR_W-1:0] saved_AWADDR;

    // Write Data Latches
    logic [DATA_W-1:0] saved_WDATA;
    logic [DATA_W/8-1:0] saved_WSTRB;

    // Read Address Latches
    logic [ADDR_W-1:0] saved_ARADDR;

    // decode word index from saved addresses (use wire so continuous assign is valid)
    wire [IDX_W-1:0] widx = saved_AWADDR[IDX_W+1:2];
    wire [IDX_W-1:0] ridx = saved_ARADDR[IDX_W+1:2];

    // output ready signals (single outstanding write/read)
    assign AWREADY = !aw_pending && !BVALID;
    assign WREADY  = !w_pending && !BVALID;
    assign ARREADY = !ar_pending && !RVALID;

    // fire signals
    logic write_fire, read_fire;
    assign write_fire = aw_pending && w_pending && !BVALID;
    assign read_fire  = ar_pending && !RVALID;

    // Default responses: OKAY
    // Keep as simple combinational drive so BRESP/RRESP are always valid values
    always_comb begin
        BRESP = 2'b00; // OKAY
        RRESP = 2'b00; // OKAY
    end


    // ARESETn may be asserted asynchronously but only deasserted synchronous
    // Two FSMs one for WRITE and one for READ
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            curr_write_state <= W_IDLE;
            curr_read_state  <= R_IDLE;
        end
        else begin
            curr_write_state <= next_write_state;
            curr_read_state  <= next_read_state;
        end
    end

    // comb logic purely for state transitions
    always_comb begin
        next_write_state = curr_write_state;
        case(curr_write_state)
            W_IDLE: begin
                if (write_fire)
                    next_write_state = W_RESP;
            end

            W_RESP: begin
                if (BVALID & BREADY)
                    next_write_state = W_IDLE;
            end
        endcase

        next_read_state = curr_read_state;
        case(curr_read_state)
            R_IDLE: begin
                if (read_fire)
                    next_read_state = R_RESP;
            end

            R_RESP: begin
                if (RVALID && RREADY)
                    next_read_state = R_IDLE;
            end
        endcase
    end

    // setting internal pending signals
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            aw_pending <= 0;
            w_pending  <= 0;
            ar_pending <= 0;
        end else begin
            if (AWREADY & AWVALID)
                aw_pending <= 1;

            if (WREADY & WVALID)
                w_pending <= 1;

            if (ARREADY & ARVALID)
                ar_pending <= 1;

            // clear write pendings on response acceptance
            if (BREADY & BVALID) begin
                aw_pending <= 0;
                w_pending  <= 0;
            end

            if (RREADY & RVALID)
                ar_pending <= 0;
        end
    end

    // capturing addresses, data, and ids (only on handshakes)
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            saved_AWADDR <= '0;
            saved_WDATA  <= '0;
            saved_WSTRB  <= '0;
            saved_ARADDR <= '0;
        end else begin
            case (curr_write_state)
                W_IDLE: begin
                    if (AWVALID && AWREADY) begin
                        saved_AWADDR <= AWADDR;
                    end

                    if (WVALID && WREADY) begin
                        saved_WDATA <= WDATA;
                        saved_WSTRB <= WSTRB;
                    end
                end
                default: begin
                end
            endcase

            case (curr_read_state)
                R_IDLE: begin
                    if (ARVALID && ARREADY)
                        saved_ARADDR <= ARADDR;
                end
            endcase
        end
    end

    // changing internal memory and response generation
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            // initialize entire memory using DEPTH
            for (int i = 0; i < DEPTH; i = i + 1)
                regs[i] = '0;

            BVALID <= 0;
            RDATA <= '0;
            RVALID <= 0;
        end else begin
            // WRITE: apply saved_WSTRB to only update selected bytes
            if (write_fire) begin
                // apply byte strobes
                // each byte chunk is 8 bits
                logic [DATA_W-1:0] new_word;
                new_word = regs[widx]; // current word
                for (int b = 0; b < BYTES; b = b + 1) begin
                    if (saved_WSTRB[b]) begin
                        new_word[8*b +: 8] = saved_WDATA[8*b +: 8];
                    end
                end
                regs[widx] <= new_word;
                BVALID <= 1;
            end

            if (BVALID && BREADY)
                BVALID <= 0;

            // READ
            if (read_fire) begin
                RDATA <= regs[ridx];
                RVALID <= 1;
            end

            if (RVALID && RREADY)
                RVALID <= 0;
        end
    end

endmodule
