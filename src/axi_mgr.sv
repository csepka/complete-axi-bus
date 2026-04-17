
// Making this for AXI5-LITE
`timescale 1ns/1ps

module axi_lite_mgr #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter ID_W = 8

)(
    input logic ACLK,
    input logic ARESETn,

    // // Write address channel (AW)
    // // dir reflects mgr
    // output logic AWVALID,
    // input logic AWREADY,
    // output logic [2:0] AWPROT,
    // output logic [ADDR_W-1:0] AWADDR,


    // // Write data channel (W)
    // output logic WVALID,
    // input logic WREADY,
    // output logic [DATA_W-1:0] WDATA,
    // output logic [DATA_W/8-1:0] WSTRB,

    // // Write response channel (B)
    // // dir reflects mgr
    // output logic BREADY,
    // input logic BVALID,


    // // Read address channel (AR)
    // // dir reflects mgr
    // output logic ARVALID,
    // input logic ARREADY,
    // output logic [ADDR_W-1:0] ARADDR,
    // output logic [2:0] ARPROT,

    // // Read data channel (R)
    // // dir reflects mgr
    // input logic RVALID,
    // output logic RREADY,
    // input logic [DATA_W-1:0] RDATA,

    // // signals to communicate with testbench
    input logic cmd_valid,
    input logic cmd_write,
    input logic [ADDR_W-1:0] cmd_addr,
    input logic [DATA_W-1:0] cmd_wdata,

    output logic cmd_ready,
    output logic cmd_done,
    output logic [DATA_W-1:0] cmd_rdata,


    axi_if.mgr axi


);

    logic [DATA_W-1:0] saved_rdata;

    // Assert AWVALID and WVALID
    // 

    typedef enum logic [2:0] {
        S_IDLE,
        S_W_SEND,
        S_W_RESP,
        S_R_SEND,
        S_R_RESP
    } state_t;

    state_t state, next_state;
    
    // Write Address Latches
    logic [ADDR_W-1:0] saved_AWADDR;

    // Write Data Latches
    logic [DATA_W-1:0] saved_WDATA;

    // Read Address Latches
    logic [ADDR_W-1:0] saved_ARADDR;

    // Read Data Latches
    logic [DATA_W-1:0] saved_RDATA;

    // always_ff @(posedge ACLK or negedge ARESETn) begin
    //     if (!ARESETn) begin
    //         curr_write_state <= W_IDLE;
    //         curr_read_state <= R_IDLE;
    //     end else begin
    //         curr_write_state <= next_write_state;
    //         curr_read_state <= next_read_state;
    //     end
    // end

    //Track whether AW/W have already handshaken for current write
    logic aw_sent, w_sent;

    assign axi.AWPROT = 3'b000;
    assign axi.ARPROT = 3'b000;

    //full word writes by default
    assign axi.WSTRB = {(DATA_W/8) {1'b1}};

    //command interface
    assign cmd_ready = (state == S_IDLE);

    // Drive address/data outputs from saved latches (stable while VALID is asserted)
    assign axi.AWADDR = saved_AWADDR;
    assign axi.WDATA  = saved_WDATA;
    assign axi.ARADDR = saved_ARADDR; 

    // VALID/READY channel driving (simple single-outstanding manager)
    always_comb begin
        // defaults
        axi.AWVALID = 1'b0;
        axi.WVALID  = 1'b0;
        axi.BREADY  = 1'b0;
        axi.ARVALID = 1'b0;
        axi.RREADY  = 1'b0;

        case (state)
            S_IDLE: begin
                // nothing asserted
            end

            // Send write address and data (independent handshakes)
            S_W_SEND: begin
                axi.AWVALID = ~aw_sent;
                axi.WVALID  = ~w_sent;
            end

            // Wait for write response
            S_W_RESP: begin
                axi.BREADY = 1'b1;
            end

            // Send read address
            S_R_SEND: begin
                axi.ARVALID = 1'b1;
            end

            // Wait for read data
            S_R_RESP: begin
                axi.RREADY = 1'b1;
            end

            default: begin
                // keep defaults
            end
        endcase
    end

    // Next-state logic
    always_comb begin
        next_state = state;

        case (state)
            S_IDLE: begin
                if (cmd_valid) begin
                    if (cmd_write)
                        next_state = S_W_SEND;
                    else
                        next_state = S_R_SEND;
                end
            end

            S_W_SEND: begin
                // Move to response stage once BOTH AW and W have handshaken
                if (aw_sent && w_sent)
                    next_state = S_W_RESP;
            end

            S_W_RESP: begin
                // Complete when BVALID && BREADY (BREADY is 1 in this state)
                if (axi.BVALID)
                    next_state = S_IDLE;
            end

            S_R_SEND: begin
                // Handshake ARVALID && ARREADY (ARVALID is 1 in this state)
                if (axi.ARREADY)
                    next_state = S_R_RESP;
            end

            S_R_RESP: begin
                // Complete when RVALID && RREADY (RREADY is 1 in this state)
                if (axi.RVALID)
                    next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // Sequential: state, latches, handshake tracking, cmd_done pulse, cmd_rdata capture
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state        <= S_IDLE;

            saved_AWADDR <= '0;
            saved_WDATA  <= '0;
            saved_ARADDR <= '0;

            aw_sent      <= 1'b0;
            w_sent       <= 1'b0;

            cmd_done     <= 1'b0;
            cmd_rdata    <= '0;

        end else begin
            state    <= next_state;
            //cmd_done <= 1'b0; // default: pulse for 1 cycle when finishing

            if (state == S_IDLE && cmd_valid)
                cmd_done <= 1'b0;

            // Accept a new command only in IDLE when cmd_valid is high
            if (state == S_IDLE && cmd_valid) begin
                if (cmd_write) begin
                    saved_AWADDR <= cmd_addr;
                    saved_WDATA  <= cmd_wdata;
                    aw_sent      <= 1'b0;
                    w_sent       <= 1'b0;
                end else begin
                    saved_ARADDR <= cmd_addr;
                end
            end

            // Track write channel handshakes while in S_W_SEND
            if (state == S_W_SEND) begin
                if (!aw_sent && axi.AWVALID && axi.AWREADY)
                    aw_sent <= 1'b1;

                if (!w_sent && axi.WVALID && axi.WREADY)
                    w_sent <= 1'b1;
            end

            // Write complete: in S_W_RESP when BVALID observed (BREADY is 1 here)
            if (state == S_W_RESP && axi.BVALID) begin
                cmd_done <= 1'b1;
                // (optional) could clear aw_sent/w_sent here, but we reset them on next cmd anyway
            end

            // Read data capture + complete: in S_R_RESP when RVALID observed (RREADY is 1 here)
            if (state == S_R_RESP && axi.RVALID) begin
                cmd_rdata <= axi.RDATA;
                cmd_done  <= 1'b1;
            end
        end
    end
    
endmodule