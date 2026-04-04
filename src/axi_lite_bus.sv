
`timescale 1ns/1ps

module axi_lite_bus #(
    parameter NM = 3,
    parameter NS = 3,
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter BYTES = (DATA_W/8)

    // Optional parameters
    // parameter logic [ADDR_W-1:0] S_BASE [NS] = '{default:'0},
    // parameter logic [ADDR_W-1:0] S_MASK [NS] = '{default:'0}
) (
    input logic ACLK,
    input logic ARESETn,

    axi_lite_if #(ADDR_W, DATA_W) m_axi [NM],
    axi_lite_if #(ADDR_W, DATA_W) s_axi [NS]


);

    localparam M_IDX_W = (NM > 1) ? $clog2(NM) : 1;
    localparam S_IDX_W = (NS > 1) ? $clog2(NS) : 1;

    typedef enum logic [2:0] {
        IDLE,
        W_SEND,
        W_RESP,
        R_SEND,
        R_RESP

    } state_t;

    state_t state, next_state;


    // logic [M_IDX_W-1:0] rr_ptr;
    logic [M_IDX_W-1:0] owner_m;
    logic [S_IDX_W-1:0] tgt_s;

    logic [ADDR_W-1:0] dec_addr;
    logic [S_IDX_W-1:0] dec_s;

    logic have_owner;
    logic [M_IDX_W-1:0] pick_m;
    logic [M_IDX_W-1:0] rr_ptr;

    logic aw_done, w_done;


    // flattened arrays for verilator

    // Manager

    logic [NM-1:0] M_AWVALID, M_AWREADY;
    logic [NM-1:0][ADDR_W-1:0] M_AWADDR;
    logic [NM-1:0][2:0] M_AWPROT;

    logic [NM-1:0] M_WVALID, M_WREADY;
    logic [NM-1:0][DATA_W-1:0] M_WDATA;
    logic [NM-1:0][BYTES-1:0] M_WSTRB;

    logic [NM-1:0] M_BVALID, M_BREADY;
    logic [NM-1:0][1:0] M_BRESP;

    logic [NM-1:0] M_ARVALID, M_ARREADY;
    logic [NM-1:0][ADDR_W-1:0] M_ARADDR;
    logic [NM-1:0][2:0] M_ARPROT;

    // R
    logic [NM-1:0] M_RVALID;
    logic [NM-1:0] M_RREADY;
    logic [NM-1:0][DATA_W-1:0] M_RDATA;
    logic [NM-1:0][1:0] M_RRESP;

    // Subordinate

    // AW
    logic [NS-1:0] S_AWVALID;
    logic [NS-1:0] S_AWREADY;
    logic [NS-1:0][ADDR_W-1:0] S_AWADDR;
    logic [NS-1:0][2:0] S_AWPROT;

    // W
    logic [NS-1:0] S_WVALID;
    logic [NS-1:0] S_WREADY;
    logic [NS-1:0][DATA_W-1:0] S_WDATA;
    logic [NS-1:0][BYTES-1:0] S_WSTRB;

    // B
    logic [NS-1:0] S_BVALID;
    logic [NS-1:0] S_BREADY;
    logic [NS-1:0][1:0] S_BRESP;

    // AR
    logic [NS-1:0] S_ARVALID;
    logic [NS-1:0] S_ARREADY;
    logic [NS-1:0][ADDR_W-1:0] S_ARADDR;
    logic [NS-1:0][2:0] S_ARPROT;

    // R
    logic [NS-1:0] S_RVALID;
    logic [NS-1:0] S_RREADY;
    logic [NS-1:0][DATA_W-1:0] S_RDATA;
    logic [NS-1:0][1:0] S_RRESP;


    genvar gi;
    generate
        for (gi = 0; gi < NM; gi++) begin : GEN_M_MAP
            // AW
            assign M_AWVALID[gi] = m_axi[gi].AWVALID;
            assign M_AWADDR[gi] = m_axi[gi].AWADDR;
            assign M_AWPROT[gi] = m_axi[gi].AWPROT;
            assign m_axi[gi].AWREADY = M_AWREADY[gi];

            // W
            assign M_WVALID[gi] = m_axi[gi].WVALID;
            assign M_WDATA[gi] = m_axi[gi].WDATA;
            assign M_WSTRB[gi] = m_axi[gi].WSTRB;
            assign m_axi[gi].WREADY = M_WREADY[gi];

            // B
            assign m_axi[gi].BVALID = M_BVALID[gi];
            assign m_axi[gi].BRESP = M_BRESP[gi];
            assign M_BREADY[gi] = m_axi[gi].BREADY;

            // AR
            assign M_ARVALID[gi] = m_axi[gi].ARVALID;
            assign M_ARADDR[gi] = m_axi[gi].ARADDR;
            assign M_ARPROT[gi] = m_axi[gi].ARPROT;
            assign m_axi[gi].ARREADY = M_ARREADY[gi];

            // R
            assign m_axi[gi].RVALID = M_RVALID[gi];
            assign m_axi[gi].RDATA = M_RDATA[gi];
            assign m_axi[gi].RRESP = M_RRESP[gi];
            assign M_RREADY[gi] = m_axi[gi].RREADY;

        end


        for (gi = 0; gi < NS; gi++) begin : GEN_S_MAP
            // AW
            assign s_axi[gi].AWVALID = S_AWVALID[gi];
            assign s_axi[gi].AWADDR = S_AWADDR[gi];
            assign s_axi[gi].AWPROT = S_AWPROT[gi];
            assign S_AWREADY[gi] = s_axi[gi].AWREADY;

            // W
            assign s_axi[gi].WVALID = S_WVALID[gi];
            assign s_axi[gi].WDATA = S_WDATA[gi];
            assign s_axi[gi].WSTRB = S_WSTRB[gi];
            assign S_WREADY[gi] = s_axi[gi].WREADY;

            // B
            assign S_BVALID[gi] = s_axi[gi].BVALID;
            assign S_BRESP[gi] = s_axi[gi].BRESP;
            assign s_axi[gi].BREADY = S_BREADY[gi];

            // AR
            assign s_axi[gi].ARVALID = S_ARVALID[gi];
            assign s_axi[gi].ARADDR = S_ARADDR[gi];
            assign s_axi[gi].ARPROT = S_ARPROT[gi];
            assign S_ARREADY[gi] = s_axi[gi].ARREADY;

            // R
            assign S_RVALID[gi] = s_axi[gi].RVALID;
            assign S_RDATA[gi] = s_axi[gi].RDATA;
            assign S_RRESP[gi] = s_axi[gi].RRESP;
            assign s_axi[gi].RREADY = S_RREADY[gi];
        end

    endgenerate

    always_comb begin
        dec_addr = 0;
        if (have_owner) begin
            if (M_AWVALID[pick_m]) dec_addr = M_AWADDR[pick_m];
            else dec_addr = M_ARADDR[pick_m];
        end
    end

    always_comb begin
        int idx;
        have_owner = 1'b0;
        // code from before
        // pick_m = 0;
        pick_m = rr_ptr;

        for (int k = 0; k < NM; k++) begin
            idx = (int'($unsigned(rr_ptr)) + k) % NM;
            if (!have_owner && (M_AWVALID[idx] || M_ARVALID[idx])) begin
                have_owner = 1'b1;
                pick_m = M_IDX_W'(idx);
            end
        end
    end

    always_comb begin
        dec_s = 0;

        unique case (dec_addr[19:16])
            4'h0: dec_s = S_IDX_W'(0);
            4'h1: dec_s = S_IDX_W'(1);
            4'h2: dec_s = S_IDX_W'(2);
            default: begin
                dec_s = 0;
            end
        endcase
    end

    // Defining the FSM
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            owner_m <= 0;
            tgt_s <= 0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            rr_ptr <= 0;
        end else begin
            if (state == IDLE && next_state != IDLE) begin
                owner_m <= pick_m;
                tgt_s <= dec_s;
                aw_done <= 1'b0;
                w_done <= 1'b0;
                rr_ptr <= (pick_m == NM-1) ? 0 : (pick_m + 1);
            end

            if (state == W_SEND) begin
                if (!aw_done && M_AWVALID[owner_m] && S_AWREADY[tgt_s]) aw_done <= 1'b1;
                if (!w_done && M_WVALID[owner_m] && S_WREADY[tgt_s]) w_done <= 1'b1;
            end

        end
    end

    // Going into state transitions
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (have_owner) begin
                    if (M_AWVALID[pick_m]) next_state = W_SEND;
                    else next_state = R_SEND;
                end
            end

            W_SEND: begin
                if (aw_done && w_done) next_state = W_RESP;
            end

            W_RESP: begin
                if (S_BVALID[tgt_s] && M_BREADY[owner_m]) next_state = IDLE;
            end

            R_SEND: begin
                if (S_ARREADY[tgt_s] && M_ARVALID[owner_m]) next_state = R_RESP;
            end

            R_RESP: begin
                if (S_RVALID[tgt_s] && M_RREADY[owner_m]) next_state = IDLE;
            end

            default: next_state = IDLE;


        endcase
    end

    // Driving the outputs

        // setting output signals
    always_comb begin
        // creating the defaults

        for (int m = 0; m < NM; m++) begin
            M_AWREADY[m] = 1'b0;
            M_WREADY[m] = 1'b0;
            M_BVALID[m] = 1'b0;
            M_BRESP[m] = 2'b00;

            M_ARREADY[m] = 1'b0;
            M_RVALID[m] = 1'b0;
            M_RDATA[m] = 0;
            M_RRESP[m] = 2'b00;
        end

        for (int s = 0; s < NS; s++) begin
            S_AWVALID[s] = 1'b0;
            S_AWADDR[s] = 0;
            S_AWPROT[s] = 0;

            S_WVALID[s] = 1'b0;
            S_WDATA[s] = 0;
            S_WSTRB[s] = 0;

            S_BREADY[s] = 1'b0;

            S_ARVALID[s] = 1'b0;
            S_ARADDR[s] = 0;
            S_ARPROT[s] = 0;

            S_RREADY[s] = 1'b0;
        end

        unique case (state)
            IDLE: begin
            end

            W_SEND: begin
                // AW
                S_AWVALID[tgt_s] = M_AWVALID[owner_m] && !aw_done;
                S_AWADDR[tgt_s] = M_AWADDR[owner_m];
                S_AWPROT[tgt_s] = M_AWPROT[owner_m];
                M_AWREADY[owner_m] = S_AWREADY[tgt_s] && !aw_done;

                // W
                S_WVALID[tgt_s] = M_WVALID[owner_m] && !w_done;
                S_WDATA[tgt_s] = M_WDATA[owner_m];
                S_WSTRB[tgt_s] = M_WSTRB[owner_m];
                M_WREADY[owner_m] = S_WREADY[tgt_s] && !w_done;
            end

            W_RESP: begin
                M_BVALID[owner_m] = S_BVALID[tgt_s];
                M_BRESP[owner_m] = S_BRESP[tgt_s];
                S_BREADY[tgt_s] = M_BREADY[owner_m];
            end

            R_SEND: begin
                S_ARVALID[tgt_s] = M_ARVALID[owner_m];
                S_ARADDR[tgt_s] = M_ARADDR[owner_m];
                S_ARPROT[tgt_s] = M_ARPROT[owner_m];
                M_ARREADY[owner_m] = S_ARREADY[tgt_s];
            end

            R_RESP: begin
                M_RVALID[owner_m] = S_RVALID[tgt_s];
                M_RDATA[owner_m] = S_RDATA[tgt_s];
                M_RRESP[owner_m] = S_RRESP[tgt_s];
                S_RREADY[tgt_s] = M_RREADY[owner_m];
            end
        endcase
    end





endmodule
