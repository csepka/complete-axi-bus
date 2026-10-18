module axi_mgr #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32,
    parameter int ID_W   = 4,
    parameter logic [ID_W-1:0] MANAGER_ID = '0
) (
    input  logic              ACLK,
    input  logic              ARESETn,
    input  logic              cmd_valid,
    input  logic              cmd_write,
    input  logic [ADDR_W-1:0] cmd_addr,
    input  logic [DATA_W-1:0] cmd_wdata,
    output logic              cmd_ready,
    output logic              cmd_done,
    output logic [DATA_W-1:0] cmd_rdata,
    output logic [1:0]        cmd_resp,
    axi_if.mgr axi
);
    localparam int BYTES = DATA_W / 8;
    localparam logic [2:0] AXI_SIZE = 3'($clog2(BYTES));

    typedef enum logic [2:0] {
        IDLE,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state_t;

    state_t state;
    logic [ADDR_W-1:0] saved_addr;
    logic [DATA_W-1:0] saved_wdata;
    logic aw_sent;
    logic w_sent;

    wire aw_fire = axi.AWVALID && axi.AWREADY;
    wire w_fire  = axi.WVALID  && axi.WREADY;
    wire b_fire  = axi.BVALID  && axi.BREADY;
    wire ar_fire = axi.ARVALID && axi.ARREADY;
    wire r_fire  = axi.RVALID  && axi.RREADY;

    assign cmd_ready = (state == IDLE);

    assign axi.AWADDR  = saved_addr;
    assign axi.AWPROT  = 3'b000;
    assign axi.AWID    = MANAGER_ID;
    assign axi.AWLEN   = 8'd0;
    assign axi.AWSIZE  = AXI_SIZE;
    assign axi.AWBURST = 2'b01;
    assign axi.WDATA   = saved_wdata;
    assign axi.WSTRB   = {BYTES{1'b1}};
    assign axi.WLAST   = 1'b1;
    assign axi.ARADDR  = saved_addr;
    assign axi.ARPROT  = 3'b000;
    assign axi.ARID    = MANAGER_ID;
    assign axi.ARLEN   = 8'd0;
    assign axi.ARSIZE  = AXI_SIZE;
    assign axi.ARBURST = 2'b01;

    always_comb begin
        axi.AWVALID = 1'b0;
        axi.WVALID  = 1'b0;
        axi.BREADY  = 1'b0;
        axi.ARVALID = 1'b0;
        axi.RREADY  = 1'b0;
        case (state)
            WRITE_DATA: begin
                axi.AWVALID = !aw_sent;
                axi.WVALID  = !w_sent;
            end
            WRITE_RESP: axi.BREADY = 1'b1;
            READ_ADDR:  axi.ARVALID = 1'b1;
            READ_DATA:  axi.RREADY = 1'b1;
            default: ;
        endcase
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state       <= IDLE;
            saved_addr  <= '0;
            saved_wdata <= '0;
            aw_sent     <= 1'b0;
            w_sent      <= 1'b0;
            cmd_done    <= 1'b0;
            cmd_rdata   <= '0;
            cmd_resp    <= 2'b00;
        end else begin
            cmd_done <= 1'b0;
            case (state)
                IDLE: begin
                    if (cmd_valid) begin
                        saved_addr  <= cmd_addr;
                        saved_wdata <= cmd_wdata;
                        cmd_resp    <= 2'b00;
                        aw_sent     <= 1'b0;
                        w_sent      <= 1'b0;
                        state       <= cmd_write ? WRITE_DATA : READ_ADDR;
                    end
                end

                WRITE_DATA: begin
                    if (aw_fire)
                        aw_sent <= 1'b1;
                    if (w_fire)
                        w_sent <= 1'b1;
                    if ((aw_sent || aw_fire) && (w_sent || w_fire))
                        state <= WRITE_RESP;
                end

                WRITE_RESP: begin
                    if (b_fire) begin
                        cmd_resp <= axi.BRESP;
                        cmd_done <= 1'b1;
                        state    <= IDLE;
                    end
                end

                READ_ADDR: begin
                    if (ar_fire)
                        state <= READ_DATA;
                end

                READ_DATA: begin
                    if (r_fire && axi.RLAST) begin
                        cmd_rdata <= axi.RDATA;
                        cmd_resp  <= axi.RRESP;
                        cmd_done  <= 1'b1;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
