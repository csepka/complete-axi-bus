module axi_ram #(
    parameter int ADDR_W        = 32,
    parameter int DATA_W        = 32,
    parameter int ID_W          = 4,
    parameter int MEM_BYTES     = 4096,
    parameter int ADDR_OFFSET_W = 16
) (
    input  logic                 ACLK,
    input  logic                 ARESETn,

    input  logic                 AWVALID,
    output logic                 AWREADY,
    input  logic [ADDR_W-1:0]    AWADDR,
    input  logic [ID_W-1:0]      AWID,
    input  logic [7:0]           AWLEN,
    input  logic [2:0]           AWSIZE,
    input  logic [1:0]           AWBURST,

    input  logic                 WVALID,
    output logic                 WREADY,
    input  logic [DATA_W-1:0]    WDATA,
    input  logic [DATA_W/8-1:0]  WSTRB,
    input  logic                 WLAST,

    output logic                 BVALID,
    input  logic                 BREADY,
    output logic [1:0]           BRESP,
    output logic [ID_W-1:0]      BID,

    input  logic                 ARVALID,
    output logic                 ARREADY,
    input  logic [ADDR_W-1:0]    ARADDR,
    input  logic [ID_W-1:0]      ARID,
    input  logic [7:0]           ARLEN,
    input  logic [2:0]           ARSIZE,
    input  logic [1:0]           ARBURST,

    output logic                 RVALID,
    input  logic                 RREADY,
    output logic [DATA_W-1:0]    RDATA,
    output logic [1:0]           RRESP,
    output logic [ID_W-1:0]      RID,
    output logic                 RLAST
);
    localparam int BYTES    = DATA_W / 8;
    localparam int BEAT_LG2 = $clog2(BYTES);
    localparam int CALC_W   = ADDR_W + 9;
    localparam logic [2:0] BEAT_SIZE = 3'($clog2(BYTES));
    localparam logic [CALC_W-1:0] MEM_BYTES_CALC = CALC_W'(MEM_BYTES);
    localparam logic [CALC_W-1:0] FOUR_KIB_CALC = CALC_W'(4096);
    localparam int DEPTH    = MEM_BYTES / BYTES;
    localparam int IDX_W    = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;
    localparam logic [1:0] BURST_FIXED = 2'b00;
    localparam logic [1:0] BURST_INCR  = 2'b01;
    localparam logic [1:0] BURST_WRAP  = 2'b10;

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    logic              write_active;
    logic [ADDR_W-1:0] write_addr;
    logic [ID_W-1:0]   write_id;
    logic [8:0]        write_beats_left;
    logic [7:0]        write_len;
    logic [2:0]        write_size;
    logic [1:0]        write_burst;
    logic              write_error;

    logic              read_active;
    logic [ADDR_W-1:0] read_addr;
    logic [8:0]        read_beats_left;
    logic [7:0]        read_len;
    logic [2:0]        read_size;
    logic [1:0]        read_burst;
    logic              read_error;
    logic [ADDR_W-1:0] read_next_addr;

    integer i;
    integer b;
    logic [DATA_W-1:0] write_merged;
    logic write_mem_fire;

    function automatic [IDX_W-1:0] word_index(input logic [ADDR_W-1:0] addr);
        word_index = IDX_W'(addr[ADDR_OFFSET_W-1:0] >> BEAT_LG2);
    endfunction

    function automatic logic request_error(
        input logic [ADDR_W-1:0] addr,
        input logic [7:0]        len,
        input logic [2:0]        size,
        input logic [1:0]        burst
    );
        logic [CALC_W-1:0] beat_bytes;
        logic [CALC_W-1:0] total_bytes;
        logic [CALC_W-1:0] local_start;
        logic [CALC_W-1:0] wrap_base;
        begin
            beat_bytes = {{(CALC_W-1){1'b0}}, 1'b1} << size;
            total_bytes = {{(CALC_W-8){1'b0}}, len};
            total_bytes = (total_bytes + 1'b1) << size;
            local_start = {{(CALC_W-ADDR_OFFSET_W){1'b0}},
                           addr[ADDR_OFFSET_W-1:0]};
            wrap_base = local_start & ~(total_bytes - 1'b1);
            request_error = 1'b0;
            if ((BEAT_LG2 > 7) || (size != BEAT_SIZE))
                request_error = 1'b1;
            if ((local_start & (beat_bytes - 1'b1)) != '0)
                request_error = 1'b1;
            if (burst == 2'b11)
                request_error = 1'b1;
            if (burst == BURST_FIXED && len > 8'd15)
                request_error = 1'b1;
            if (burst == BURST_WRAP && !((len == 8'd1) || (len == 8'd3) ||
                                         (len == 8'd7) || (len == 8'd15)))
                request_error = 1'b1;
            if (local_start >= MEM_BYTES_CALC)
                request_error = 1'b1;
            if (burst == BURST_INCR &&
                (local_start + total_bytes) > MEM_BYTES_CALC)
                request_error = 1'b1;
            if (burst == BURST_WRAP &&
                (wrap_base + total_bytes) > MEM_BYTES_CALC)
                request_error = 1'b1;
            if (burst == BURST_INCR &&
                ({{(CALC_W-12){1'b0}}, addr[11:0]} + total_bytes) >
                FOUR_KIB_CALC)
                request_error = 1'b1;
        end
    endfunction

    function automatic [ADDR_W-1:0] next_address(
        input logic [ADDR_W-1:0] addr,
        input logic [2:0]        size,
        input logic [1:0]        burst,
        input logic [7:0]        len
    );
        logic [ADDR_W-1:0] incremented;
        logic [ADDR_W-1:0] wrap_bytes;
        logic [ADDR_W-1:0] wrap_mask;
        logic [ADDR_W-1:0] wrap_base;
        begin
            if (burst == BURST_FIXED) begin
                next_address = addr;
            end else begin
                incremented = addr + ({{(ADDR_W-1){1'b0}}, 1'b1} << size);
                if (burst == BURST_WRAP) begin
                    wrap_bytes = {{(ADDR_W-8){1'b0}}, len};
                    wrap_bytes = (wrap_bytes + 1'b1) << size;
                    wrap_mask = wrap_bytes - 1'b1;
                    wrap_base = addr & ~wrap_mask;
                    if (incremented >= (wrap_base + wrap_bytes))
                        next_address = wrap_base;
                    else
                        next_address = incremented;
                end else begin
                    next_address = incremented;
                end
            end
        end
    endfunction

    assign AWREADY = !write_active && !BVALID;
    assign WREADY  = write_active && !BVALID;
    assign ARREADY = !read_active && !RVALID;
    assign write_mem_fire = WVALID && WREADY && !write_error;
    assign read_next_addr = next_address(read_addr, read_size, read_burst, read_len);

    always_comb begin
        write_merged = mem[word_index(write_addr)];
        for (b = 0; b < BYTES; b = b + 1)
            if (WSTRB[b])
                write_merged[(8*b) +: 8] = WDATA[(8*b) +: 8];
    end

    // Keep storage writes in an unreset clocked process so memory macros can be inferred.
    always_ff @(posedge ACLK) begin
        if (write_mem_fire)
            mem[word_index(write_addr)] <= write_merged;
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_active     <= 1'b0;
            write_addr       <= '0;
            write_id         <= '0;
            write_beats_left <= '0;
            write_len        <= '0;
            write_size       <= '0;
            write_burst      <= BURST_INCR;
            write_error      <= 1'b0;
            BVALID           <= 1'b0;
            BRESP            <= RESP_OKAY;
            BID              <= '0;
        end else begin
            if (BVALID && BREADY)
                BVALID <= 1'b0;

            if (AWVALID && AWREADY) begin
                write_active     <= 1'b1;
                write_addr       <= AWADDR;
                write_id         <= AWID;
                write_beats_left <= {1'b0, AWLEN} + 9'd1;
                write_len        <= AWLEN;
                write_size       <= AWSIZE;
                write_burst      <= AWBURST;
                write_error      <= request_error(AWADDR, AWLEN, AWSIZE, AWBURST);
            end

            if (WVALID && WREADY) begin
                if (WLAST != (write_beats_left == 9'd1))
                    write_error <= 1'b1;

                if (write_beats_left == 9'd1) begin
                    write_active <= 1'b0;
                    BVALID       <= 1'b1;
                    BID          <= write_id;
                    BRESP        <= (write_error || !WLAST) ? RESP_SLVERR : RESP_OKAY;
                end else begin
                    write_beats_left <= write_beats_left - 9'd1;
                    write_addr <= next_address(write_addr, write_size, write_burst, write_len);
                end
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_active     <= 1'b0;
            read_addr       <= '0;
            read_beats_left <= '0;
            read_len        <= '0;
            read_size       <= '0;
            read_burst      <= BURST_INCR;
            read_error      <= 1'b0;
            RVALID          <= 1'b0;
            RDATA           <= '0;
            RRESP           <= RESP_OKAY;
            RID             <= '0;
            RLAST           <= 1'b0;
        end else begin
            if (ARVALID && ARREADY) begin
                read_active     <= 1'b1;
                read_addr       <= ARADDR;
                read_beats_left <= {1'b0, ARLEN} + 9'd1;
                read_len        <= ARLEN;
                read_size       <= ARSIZE;
                read_burst      <= ARBURST;
                read_error      <= request_error(ARADDR, ARLEN, ARSIZE, ARBURST);
                RVALID          <= 1'b1;
                RDATA           <= request_error(ARADDR, ARLEN, ARSIZE, ARBURST)
                                   ? '0 : mem[word_index(ARADDR)];
                RRESP           <= request_error(ARADDR, ARLEN, ARSIZE, ARBURST)
                                   ? RESP_SLVERR : RESP_OKAY;
                RID             <= ARID;
                RLAST           <= (ARLEN == 8'd0);
            end else if (RVALID && RREADY) begin
                if (read_beats_left == 9'd1) begin
                    read_active <= 1'b0;
                    RVALID      <= 1'b0;
                    RLAST       <= 1'b0;
                end else begin
                    read_beats_left <= read_beats_left - 9'd1;
                    read_addr <= read_next_addr;
                    RDATA <= read_error ? '0 : mem[word_index(read_next_addr)];
                    RLAST <= (read_beats_left == 9'd2);
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = '0;
        assert (DATA_W >= 8 && (DATA_W % 8) == 0 &&
                (BYTES & (BYTES-1)) == 0 && BEAT_LG2 <= 7)
            else $fatal(1, "DATA_W must encode a power-of-two byte width in AxSIZE");
        assert (ADDR_OFFSET_W >= 12 && ADDR_OFFSET_W <= ADDR_W)
            else $fatal(1, "ADDR_OFFSET_W must be between 12 and ADDR_W");
        assert (MEM_BYTES <= (1 << ADDR_OFFSET_W))
            else $fatal(1, "MEM_BYTES must fit within its address window");
        assert (MEM_BYTES >= BYTES && (MEM_BYTES % BYTES) == 0)
            else $fatal(1, "MEM_BYTES must contain a whole number of data beats");
        assert ((MEM_BYTES & (MEM_BYTES-1)) == 0)
            else $fatal(1, "MEM_BYTES must be a power of two");
    end
`endif
endmodule
