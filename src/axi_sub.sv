// AXI5 Subordinate
`timescale 1ns/1ps

module axi_sub #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter ID_W = 8,
    parameter int BYTES  = DATA_W/8,

    parameter int MEM_BYTES = 256 //reduced for PnR
)(
    input logic ACLK,
    input logic ARESETn,

    axi_if.sub axi
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
    logic [ID_W-1:0] saved_AWID;
    logic [7:0] saved_AWLEN;
    logic [2:0] saved_AWSIZE;
    logic [1:0] saved_AWBURST;

    // Write Data Latches
    logic [DATA_W-1:0] saved_WDATA;
    logic [DATA_W/8-1:0] saved_WSTRB;

    // Read Address Latches
    logic [ADDR_W-1:0] saved_ARADDR;
    logic [ID_W-1:0] saved_ARID;
    logic [7:0] saved_ARLEN;
    logic [2:0] saved_ARSIZE;
    logic [1:0] saved_ARBURST;

    // Burst read states
    logic [7:0] r_beat_cnt;
    logic [ADDR_W-1:0] r_cur_addr;

    // decode word index from saved addresses (use wire so continuous assign is valid)
    wire [IDX_W-1:0] widx = saved_AWADDR[IDX_W+1:2];
    wire [IDX_W-1:0] ridx = saved_ARADDR[IDX_W+1:2];

    // output ready signals (single outstanding write/read)
    assign axi.AWREADY = !aw_pending && !axi.BVALID;
    assign axi.WREADY  = !w_pending && !axi.BVALID;
    assign axi.ARREADY = !ar_pending && !axi.RVALID;

    // fire signals
    logic write_fire, read_fire;
    assign write_fire = aw_pending && w_pending && !axi.BVALID;
    assign read_fire  = ar_pending && !axi.RVALID;

    // Default responses: OKAY
    // Keep as simple combinational drive so BRESP/RRESP are always valid values
    always_comb begin
        axi.BRESP = 2'b00; // OKAY
        axi.RRESP = 2'b00; // OKAY
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
                if (axi.BVALID && axi.BREADY)
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
                if (axi.RVALID && axi.RREADY && axi.RLAST)
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
            if (axi.AWREADY && axi.AWVALID)
                aw_pending <= 1;

            if (axi.WREADY && axi.WVALID)
                w_pending <= 1;

            if (axi.ARREADY && axi.ARVALID)
                ar_pending <= 1;

            // clear write pendings on response acceptance
            if (axi.BREADY && axi.BVALID) begin
                aw_pending <= 0;
                w_pending  <= 0;
            end

            if (axi.RREADY && axi.RVALID && axi.RLAST)
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

            saved_AWID <= '0;
            saved_AWLEN <= '0;
            saved_AWSIZE <= '0;
            saved_AWBURST <= '0;

            saved_ARID <= '0;
            saved_ARLEN <= '0;
            saved_ARSIZE <= '0;
            saved_ARBURST <= '0;

        end else begin
            case (curr_write_state)
                W_IDLE: begin
                    if (axi.AWVALID && axi.AWREADY) begin
                        saved_AWADDR <= axi.AWADDR;
                        
                        saved_AWID <= axi.AWID;
                        saved_AWLEN <= axi.AWLEN;
                        saved_AWSIZE <= axi.AWSIZE;
                        saved_AWBURST <= axi.AWBURST;
                    end

                    if (axi.WVALID && axi.WREADY) begin
                        saved_WDATA <= axi.WDATA;
                        saved_WSTRB <= axi.WSTRB;
                    end
                end
                default: begin
                end
            endcase

            case (curr_read_state)
                R_IDLE: begin
                    if (axi.ARVALID && axi.ARREADY) begin
                        saved_ARADDR  <= axi.ARADDR;
                        saved_ARID    <= axi.ARID;
                        saved_ARLEN   <= axi.ARLEN;
                        saved_ARSIZE  <= axi.ARSIZE;
                        saved_ARBURST <= axi.ARBURST;
                    end
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

            r_beat_cnt <= '0;
            r_cur_addr <= '0;
            axi.RLAST <= '0;

            axi.BID <= '0;
            axi.RID <= '0;
            axi.BVALID <= 0;
            axi.RDATA <= '0;
            axi.RVALID <= 0;
        end else begin
            // WRITE: apply saved_WSTRB to only update selected bytes
            if (write_fire) begin
                // apply byte strobes
                // each byte chunk is 8 bits
                logic [DATA_W-1:0] new_word;
                new_word = regs[widx]; // current word
                for (int b = 0; b < BYTES; b++) begin
                    if (saved_WSTRB[b]) begin
                        new_word[8*b +: 8] = saved_WDATA[8*b +: 8];
                    end
                end
                regs[widx] <= new_word;
                axi.BVALID <= 1;

                axi.BID <= saved_AWID;
            end

            if (axi.BVALID && axi.BREADY)
                axi.BVALID <= 0;

            // READ
            if (read_fire) begin
                r_beat_cnt <= saved_ARLEN;
                r_cur_addr <= saved_ARADDR;
                axi.RDATA <= regs[saved_ARADDR[IDX_W+1:2]];
                axi.RID <= saved_ARID;
                axi.RLAST <= (saved_ARLEN == 0);
                axi.RVALID <= 1;
            end

            if (axi.RVALID && axi.RREADY)
                if (r_beat_cnt > 0) begin
                    r_beat_cnt <= r_beat_cnt - 1;
                    r_cur_addr <= r_cur_addr + (1 << saved_ARSIZE); // INCR
                    axi.RDATA <= regs[(r_cur_addr + (1 << saved_ARSIZE))[IDX_W+1:2]];
                    axi.RLAST <= (r_beat_cnt == 1);
                end else begin
                    axi.RVALID <= 0;
                    axi.RLAST <= 0;
                end
        end
    end

endmodule
