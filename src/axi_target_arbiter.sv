// Baseline route-locking arbiter, reused once per target and once for DECERR.
module axi_target_arbiter #(
    parameter bit FORCE_DECERR    = 0,
    parameter int NM             = 2,
    parameter int NS             = 2,
    parameter int ADDR_W         = 32,
    parameter int DATA_W         = 32,
    parameter int ID_W           = 4,
    parameter int S_ADDR_WIDTH   = 16,
    parameter logic [ADDR_W-1:0] BASE_ADDR = '0
) (
    input logic ACLK,
    input logic ARESETn,
    axi_if m_axi [NM],
    axi_if s_axi [NS]
);
    localparam int BYTES   = DATA_W / 8;
    localparam int M_IDX_W = (NM > 1) ? $clog2(NM) : 1;
    localparam int S_IDX_W = (NS > 1) ? $clog2(NS) : 1;
    localparam logic [ADDR_W-1:0] WINDOW_MASK =
        {ADDR_W{1'b1}} >> (ADDR_W - S_ADDR_WIDTH);

    localparam logic [1:0] RESP_DECERR = 2'b11;

    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_t;
    typedef enum logic       {R_IDLE, R_DATA} r_state_t;

    w_state_t w_state;
    r_state_t r_state;

    logic [M_IDX_W-1:0] w_rr_ptr, r_rr_ptr;
    logic [M_IDX_W-1:0] w_owner, r_owner;
    logic [S_IDX_W-1:0] w_target, r_target;
    logic                w_decode_error, r_decode_error;
    logic [ID_W-1:0]     w_error_id, r_error_id;
    logic [8:0]          w_beats_left, r_beats_left;

    // Address grants are retained while a selected subordinate applies backpressure.
    logic                w_addr_hold, r_addr_hold;
    logic [M_IDX_W-1:0]  w_hold_owner, r_hold_owner;
    logic [S_IDX_W-1:0]  w_hold_target, r_hold_target;
    logic                w_hold_dec_ok, r_hold_dec_ok;

    logic                w_have_grant, r_have_grant;
    logic [M_IDX_W-1:0]  w_pick, r_pick;
    logic                w_dec_ok, r_dec_ok;
    logic [S_IDX_W-1:0]  w_dec_target, r_dec_target;
    logic [ADDR_W-1:0]   w_dec_slot, r_dec_slot;
    wire                  w_addr_present = w_addr_hold || w_have_grant;
    wire                  r_addr_present = r_addr_hold || r_have_grant;
    wire [M_IDX_W-1:0]    w_sel_owner = w_addr_hold ? w_hold_owner : w_pick;
    wire [M_IDX_W-1:0]    r_sel_owner = r_addr_hold ? r_hold_owner : r_pick;
    wire [S_IDX_W-1:0]    w_sel_target = w_addr_hold ? w_hold_target : w_dec_target;
    wire [S_IDX_W-1:0]    r_sel_target = r_addr_hold ? r_hold_target : r_dec_target;
    wire                  w_sel_dec_ok = w_addr_hold ? w_hold_dec_ok : w_dec_ok;
    wire                  r_sel_dec_ok = r_addr_hold ? r_hold_dec_ok : r_dec_ok;

    logic [NM-1:0] M_AWVALID, M_AWREADY;
    logic [NM-1:0][ADDR_W-1:0] M_AWADDR;
    logic [NM-1:0][2:0] M_AWPROT;
    logic [NM-1:0][ID_W-1:0] M_AWID;
    logic [NM-1:0][7:0] M_AWLEN;
    logic [NM-1:0][2:0] M_AWSIZE;
    logic [NM-1:0][1:0] M_AWBURST;

    logic [NM-1:0] M_WVALID, M_WREADY, M_WLAST;
    logic [NM-1:0][DATA_W-1:0] M_WDATA;
    logic [NM-1:0][BYTES-1:0] M_WSTRB;

    logic [NM-1:0] M_BVALID, M_BREADY;
    logic [NM-1:0][1:0] M_BRESP;
    logic [NM-1:0][ID_W-1:0] M_BID;

    logic [NM-1:0] M_ARVALID, M_ARREADY;
    logic [NM-1:0][ADDR_W-1:0] M_ARADDR;
    logic [NM-1:0][2:0] M_ARPROT;
    logic [NM-1:0][ID_W-1:0] M_ARID;
    logic [NM-1:0][7:0] M_ARLEN;
    logic [NM-1:0][2:0] M_ARSIZE;
    logic [NM-1:0][1:0] M_ARBURST;

    logic [NM-1:0] M_RVALID, M_RREADY, M_RLAST;
    logic [NM-1:0][DATA_W-1:0] M_RDATA;
    logic [NM-1:0][1:0] M_RRESP;
    logic [NM-1:0][ID_W-1:0] M_RID;

    logic [NS-1:0] S_AWVALID, S_AWREADY;
    logic [NS-1:0][ADDR_W-1:0] S_AWADDR;
    logic [NS-1:0][2:0] S_AWPROT;
    logic [NS-1:0][ID_W-1:0] S_AWID;
    logic [NS-1:0][7:0] S_AWLEN;
    logic [NS-1:0][2:0] S_AWSIZE;
    logic [NS-1:0][1:0] S_AWBURST;

    logic [NS-1:0] S_WVALID, S_WREADY, S_WLAST;
    logic [NS-1:0][DATA_W-1:0] S_WDATA;
    logic [NS-1:0][BYTES-1:0] S_WSTRB;

    logic [NS-1:0] S_BVALID, S_BREADY;
    logic [NS-1:0][1:0] S_BRESP;
    logic [NS-1:0][ID_W-1:0] S_BID;

    logic [NS-1:0] S_ARVALID, S_ARREADY;
    logic [NS-1:0][ADDR_W-1:0] S_ARADDR;
    logic [NS-1:0][2:0] S_ARPROT;
    logic [NS-1:0][ID_W-1:0] S_ARID;
    logic [NS-1:0][7:0] S_ARLEN;
    logic [NS-1:0][2:0] S_ARSIZE;
    logic [NS-1:0][1:0] S_ARBURST;

    logic [NS-1:0] S_RVALID, S_RREADY, S_RLAST;
    logic [NS-1:0][DATA_W-1:0] S_RDATA;
    logic [NS-1:0][1:0] S_RRESP;
    logic [NS-1:0][ID_W-1:0] S_RID;

    generate
        for (genvar m = 0; m < NM; m++) begin : g_manager_map
            assign M_AWVALID[m] = m_axi[m].AWVALID;
            assign M_AWADDR[m] = m_axi[m].AWADDR;
            assign M_AWPROT[m] = m_axi[m].AWPROT;
            assign M_AWID[m] = m_axi[m].AWID;
            assign M_AWLEN[m] = m_axi[m].AWLEN;
            assign M_AWSIZE[m] = m_axi[m].AWSIZE;
            assign M_AWBURST[m] = m_axi[m].AWBURST;
            assign m_axi[m].AWREADY = M_AWREADY[m];

            assign M_WVALID[m] = m_axi[m].WVALID;
            assign M_WDATA[m] = m_axi[m].WDATA;
            assign M_WSTRB[m] = m_axi[m].WSTRB;
            assign M_WLAST[m] = m_axi[m].WLAST;
            assign m_axi[m].WREADY = M_WREADY[m];

            assign m_axi[m].BVALID = M_BVALID[m];
            assign m_axi[m].BRESP = M_BRESP[m];
            assign m_axi[m].BID = M_BID[m];
            assign M_BREADY[m] = m_axi[m].BREADY;

            assign M_ARVALID[m] = m_axi[m].ARVALID;
            assign M_ARADDR[m] = m_axi[m].ARADDR;
            assign M_ARPROT[m] = m_axi[m].ARPROT;
            assign M_ARID[m] = m_axi[m].ARID;
            assign M_ARLEN[m] = m_axi[m].ARLEN;
            assign M_ARSIZE[m] = m_axi[m].ARSIZE;
            assign M_ARBURST[m] = m_axi[m].ARBURST;
            assign m_axi[m].ARREADY = M_ARREADY[m];

            assign m_axi[m].RVALID = M_RVALID[m];
            assign m_axi[m].RDATA = M_RDATA[m];
            assign m_axi[m].RRESP = M_RRESP[m];
            assign m_axi[m].RID = M_RID[m];
            assign m_axi[m].RLAST = M_RLAST[m];
            assign M_RREADY[m] = m_axi[m].RREADY;
        end

        for (genvar s = 0; s < NS; s++) begin : g_subordinate_map
            assign s_axi[s].AWVALID = S_AWVALID[s];
            assign s_axi[s].AWADDR = S_AWADDR[s];
            assign s_axi[s].AWPROT = S_AWPROT[s];
            assign s_axi[s].AWID = S_AWID[s];
            assign s_axi[s].AWLEN = S_AWLEN[s];
            assign s_axi[s].AWSIZE = S_AWSIZE[s];
            assign s_axi[s].AWBURST = S_AWBURST[s];
            assign S_AWREADY[s] = s_axi[s].AWREADY;

            assign s_axi[s].WVALID = S_WVALID[s];
            assign s_axi[s].WDATA = S_WDATA[s];
            assign s_axi[s].WSTRB = S_WSTRB[s];
            assign s_axi[s].WLAST = S_WLAST[s];
            assign S_WREADY[s] = s_axi[s].WREADY;

            assign S_BVALID[s] = s_axi[s].BVALID;
            assign S_BRESP[s] = s_axi[s].BRESP;
            assign S_BID[s] = s_axi[s].BID;
            assign s_axi[s].BREADY = S_BREADY[s];

            assign s_axi[s].ARVALID = S_ARVALID[s];
            assign s_axi[s].ARADDR = S_ARADDR[s];
            assign s_axi[s].ARPROT = S_ARPROT[s];
            assign s_axi[s].ARID = S_ARID[s];
            assign s_axi[s].ARLEN = S_ARLEN[s];
            assign s_axi[s].ARSIZE = S_ARSIZE[s];
            assign s_axi[s].ARBURST = S_ARBURST[s];
            assign S_ARREADY[s] = s_axi[s].ARREADY;

            assign S_RVALID[s] = s_axi[s].RVALID;
            assign S_RDATA[s] = s_axi[s].RDATA;
            assign S_RRESP[s] = s_axi[s].RRESP;
            assign S_RID[s] = s_axi[s].RID;
            assign S_RLAST[s] = s_axi[s].RLAST;
            assign s_axi[s].RREADY = S_RREADY[s];
        end
    endgenerate

    always_comb begin : write_arbiter
        integer idx;
        w_have_grant = 1'b0;
        w_pick = w_rr_ptr;
        for (integer k = 0; k < NM; k = k + 1) begin
            idx = (int'(w_rr_ptr) + k) % NM;
            if (!w_have_grant && M_AWVALID[idx]) begin
                w_have_grant = 1'b1;
                w_pick = M_IDX_W'(idx);
            end
        end
        w_dec_ok = 1'b0;
        w_dec_target = '0;
        w_dec_slot = '0;
        if (!FORCE_DECERR && w_have_grant && M_AWADDR[w_pick] >= BASE_ADDR) begin
            w_dec_slot = (M_AWADDR[w_pick] - BASE_ADDR) >> S_ADDR_WIDTH;
            if (w_dec_slot < ADDR_W'(NS)) begin
                w_dec_ok = 1'b1;
                w_dec_target = S_IDX_W'(w_dec_slot);
            end
        end
    end

    always_comb begin : read_arbiter
        integer idx;
        r_have_grant = 1'b0;
        r_pick = r_rr_ptr;
        for (integer k = 0; k < NM; k = k + 1) begin
            idx = (int'(r_rr_ptr) + k) % NM;
            if (!r_have_grant && M_ARVALID[idx]) begin
                r_have_grant = 1'b1;
                r_pick = M_IDX_W'(idx);
            end
        end
        r_dec_ok = 1'b0;
        r_dec_target = '0;
        r_dec_slot = '0;
        if (!FORCE_DECERR && r_have_grant && M_ARADDR[r_pick] >= BASE_ADDR) begin
            r_dec_slot = (M_ARADDR[r_pick] - BASE_ADDR) >> S_ADDR_WIDTH;
            if (r_dec_slot < ADDR_W'(NS)) begin
                r_dec_ok = 1'b1;
                r_dec_target = S_IDX_W'(r_dec_slot);
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_state        <= W_IDLE;
            w_rr_ptr       <= '0;
            w_owner        <= '0;
            w_target       <= '0;
            w_decode_error <= 1'b0;
            w_error_id     <= '0;
            w_beats_left   <= '0;
            w_addr_hold     <= 1'b0;
            w_hold_owner    <= '0;
            w_hold_target   <= '0;
            w_hold_dec_ok   <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (w_addr_present && M_AWVALID[w_sel_owner] && M_AWREADY[w_sel_owner]) begin
                        w_owner        <= w_sel_owner;
                        w_target       <= w_sel_target;
                        w_decode_error <= !w_sel_dec_ok;
                        w_error_id     <= M_AWID[w_sel_owner];
                        w_beats_left   <= {1'b0, M_AWLEN[w_sel_owner]} + 9'd1;
                        w_rr_ptr       <= (w_sel_owner == M_IDX_W'(NM-1))
                                          ? '0 : w_sel_owner + 1'b1;
                        w_addr_hold    <= 1'b0;
                        w_state        <= W_DATA;
                    end else if (!w_addr_hold && w_have_grant) begin
                        w_addr_hold   <= 1'b1;
                        w_hold_owner  <= w_pick;
                        w_hold_target <= w_dec_target;
                        w_hold_dec_ok <= w_dec_ok;
                    end
                end
                W_DATA: begin
                    if (M_WVALID[w_owner] && M_WREADY[w_owner]) begin
                        if (w_beats_left == 9'd1)
                            w_state <= W_RESP;
                        else
                            w_beats_left <= w_beats_left - 9'd1;
                    end
                end
                W_RESP: begin
                    if (M_BVALID[w_owner] && M_BREADY[w_owner])
                        w_state <= W_IDLE;
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            r_state        <= R_IDLE;
            r_rr_ptr       <= '0;
            r_owner        <= '0;
            r_target       <= '0;
            r_decode_error <= 1'b0;
            r_error_id     <= '0;
            r_beats_left   <= '0;
            r_addr_hold     <= 1'b0;
            r_hold_owner    <= '0;
            r_hold_target   <= '0;
            r_hold_dec_ok   <= 1'b0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (r_addr_present && M_ARVALID[r_sel_owner] && M_ARREADY[r_sel_owner]) begin
                        r_owner        <= r_sel_owner;
                        r_target       <= r_sel_target;
                        r_decode_error <= !r_sel_dec_ok;
                        r_error_id     <= M_ARID[r_sel_owner];
                        r_beats_left   <= {1'b0, M_ARLEN[r_sel_owner]} + 9'd1;
                        r_rr_ptr       <= (r_sel_owner == M_IDX_W'(NM-1))
                                          ? '0 : r_sel_owner + 1'b1;
                        r_addr_hold    <= 1'b0;
                        r_state        <= R_DATA;
                    end else if (!r_addr_hold && r_have_grant) begin
                        r_addr_hold   <= 1'b1;
                        r_hold_owner  <= r_pick;
                        r_hold_target <= r_dec_target;
                        r_hold_dec_ok <= r_dec_ok;
                    end
                end
                R_DATA: begin
                    if (M_RVALID[r_owner] && M_RREADY[r_owner]) begin
                        if (M_RLAST[r_owner]) begin
                            r_state <= R_IDLE;
                        end else if (r_decode_error) begin
                            r_beats_left <= r_beats_left - 9'd1;
                        end
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

    always_comb begin : route_channels
        for (integer m = 0; m < NM; m = m + 1) begin
            M_AWREADY[m] = 1'b0;
            M_WREADY[m]  = 1'b0;
            M_BVALID[m]  = 1'b0;
            M_BRESP[m]   = 2'b00;
            M_BID[m]     = '0;
            M_ARREADY[m] = 1'b0;
            M_RVALID[m]  = 1'b0;
            M_RDATA[m]   = '0;
            M_RRESP[m]   = 2'b00;
            M_RID[m]     = '0;
            M_RLAST[m]   = 1'b0;
        end

        for (integer s = 0; s < NS; s = s + 1) begin
            S_AWVALID[s] = 1'b0;
            S_AWADDR[s]  = '0;
            S_AWPROT[s]  = '0;
            S_AWID[s]    = '0;
            S_AWLEN[s]   = '0;
            S_AWSIZE[s]  = '0;
            S_AWBURST[s] = '0;
            S_WVALID[s]  = 1'b0;
            S_WDATA[s]   = '0;
            S_WSTRB[s]   = '0;
            S_WLAST[s]   = 1'b0;
            S_BREADY[s]  = 1'b0;
            S_ARVALID[s] = 1'b0;
            S_ARADDR[s]  = '0;
            S_ARPROT[s]  = '0;
            S_ARID[s]    = '0;
            S_ARLEN[s]   = '0;
            S_ARSIZE[s]  = '0;
            S_ARBURST[s] = '0;
            S_RREADY[s]  = 1'b0;
        end

        if (w_state == W_IDLE && w_addr_present) begin
            if (w_sel_dec_ok) begin
                S_AWVALID[w_sel_target] = M_AWVALID[w_sel_owner];
                S_AWADDR[w_sel_target]  = M_AWADDR[w_sel_owner];
                S_AWPROT[w_sel_target]  = M_AWPROT[w_sel_owner];
                S_AWID[w_sel_target]    = M_AWID[w_sel_owner];
                S_AWLEN[w_sel_target]   = M_AWLEN[w_sel_owner];
                S_AWSIZE[w_sel_target]  = M_AWSIZE[w_sel_owner];
                S_AWBURST[w_sel_target] = M_AWBURST[w_sel_owner];
                M_AWREADY[w_sel_owner]  = S_AWREADY[w_sel_target];
            end else begin
                M_AWREADY[w_sel_owner] = 1'b1;
            end
        end

        if (w_state == W_DATA) begin
            if (w_decode_error) begin
                M_WREADY[w_owner] = 1'b1;
            end else begin
                S_WVALID[w_target] = M_WVALID[w_owner];
                S_WDATA[w_target]  = M_WDATA[w_owner];
                S_WSTRB[w_target]  = M_WSTRB[w_owner];
                S_WLAST[w_target]  = M_WLAST[w_owner];
                M_WREADY[w_owner]  = S_WREADY[w_target];
            end
        end

        if (w_state == W_RESP) begin
            if (w_decode_error) begin
                M_BVALID[w_owner] = 1'b1;
                M_BRESP[w_owner]  = RESP_DECERR;
                M_BID[w_owner]    = w_error_id;
            end else begin
                M_BVALID[w_owner] = S_BVALID[w_target];
                M_BRESP[w_owner]  = S_BRESP[w_target];
                M_BID[w_owner]    = S_BID[w_target];
                S_BREADY[w_target] = M_BREADY[w_owner];
            end
        end

        if (r_state == R_IDLE && r_addr_present) begin
            if (r_sel_dec_ok) begin
                S_ARVALID[r_sel_target] = M_ARVALID[r_sel_owner];
                S_ARADDR[r_sel_target]  = M_ARADDR[r_sel_owner];
                S_ARPROT[r_sel_target]  = M_ARPROT[r_sel_owner];
                S_ARID[r_sel_target]    = M_ARID[r_sel_owner];
                S_ARLEN[r_sel_target]   = M_ARLEN[r_sel_owner];
                S_ARSIZE[r_sel_target]  = M_ARSIZE[r_sel_owner];
                S_ARBURST[r_sel_target] = M_ARBURST[r_sel_owner];
                M_ARREADY[r_sel_owner]  = S_ARREADY[r_sel_target];
            end else begin
                M_ARREADY[r_sel_owner] = 1'b1;
            end
        end

        if (r_state == R_DATA) begin
            if (r_decode_error) begin
                M_RVALID[r_owner] = 1'b1;
                M_RDATA[r_owner]  = '0;
                M_RRESP[r_owner]  = RESP_DECERR;
                M_RID[r_owner]    = r_error_id;
                M_RLAST[r_owner]  = (r_beats_left == 9'd1);
            end else begin
                M_RVALID[r_owner] = S_RVALID[r_target];
                M_RDATA[r_owner]  = S_RDATA[r_target];
                M_RRESP[r_owner]  = S_RRESP[r_target];
                M_RID[r_owner]    = S_RID[r_target];
                M_RLAST[r_owner]  = S_RLAST[r_target];
                S_RREADY[r_target] = M_RREADY[r_owner];
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (NM > 0 && NS > 0) else $fatal(1, "NM and NS must be positive");
        assert (S_ADDR_WIDTH >= 12 && S_ADDR_WIDTH < ADDR_W)
            else $fatal(1, "S_ADDR_WIDTH must be between 12 and ADDR_W-1");
        assert ((BASE_ADDR & WINDOW_MASK) == '0)
            else $fatal(1, "BASE_ADDR must align to a subordinate window");
        assert (({1'b0, BASE_ADDR} + ((ADDR_W+1)'(NS) << S_ADDR_WIDTH)) <=
                ((ADDR_W+1)'(1) << ADDR_W))
            else $fatal(1, "Subordinate windows exceed the address space");
    end
`endif
endmodule
