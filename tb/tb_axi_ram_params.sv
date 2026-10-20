`timescale 1ns/1ps

module tb_axi_ram_params;
    localparam int ADDR_W = 12;
    localparam int DATA_W = 128;
    localparam int ID_W = 4;

    logic ACLK;
    logic ARESETn;
    logic AWVALID;
    logic AWREADY;
    logic [ADDR_W-1:0] AWADDR;
    logic [ID_W-1:0] AWID;
    logic [7:0] AWLEN;
    logic [2:0] AWSIZE;
    logic [1:0] AWBURST;
    logic WVALID;
    logic WREADY;
    logic [DATA_W-1:0] WDATA;
    logic [DATA_W/8-1:0] WSTRB;
    logic WLAST;
    logic BVALID;
    logic BREADY;
    logic [1:0] BRESP;
    logic [ID_W-1:0] BID;
    logic ARREADY;
    logic RVALID;
    logic [DATA_W-1:0] RDATA;
    logic [1:0] RRESP;
    logic [ID_W-1:0] RID;
    logic RLAST;

    initial begin
        ACLK = 1'b0;
        forever #5 ACLK = ~ACLK;
    end

    axi_ram #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .MEM_BYTES(4096),
        .ADDR_OFFSET_W(12)
    ) dut (
        .ACLK, .ARESETn,
        .AWVALID, .AWREADY, .AWADDR, .AWID, .AWLEN, .AWSIZE, .AWBURST,
        .WVALID, .WREADY, .WDATA, .WSTRB, .WLAST,
        .BVALID, .BREADY, .BRESP, .BID,
        .ARVALID(1'b0), .ARREADY, .ARADDR('0), .ARID('0),
        .ARLEN('0), .ARSIZE('0), .ARBURST('0),
        .RVALID, .RREADY(1'b0), .RDATA, .RRESP, .RID, .RLAST
    );

    initial begin
        ARESETn = 1'b0;
        AWVALID = 1'b0;
        AWADDR = '0;
        AWID = '0;
        AWLEN = '0;
        AWSIZE = '0;
        AWBURST = '0;
        WVALID = 1'b0;
        WDATA = '0;
        WSTRB = '1;
        WLAST = 1'b0;
        BREADY = 1'b0;
        repeat (3) @(posedge ACLK);
        ARESETn = 1'b1;

        // 256 beats x 16 bytes is 4096 bytes; starting at 0x10 exceeds RAM.
        @(negedge ACLK);
        AWADDR = 12'h010;
        AWID = 4'hA;
        AWLEN = 8'hFF;
        AWSIZE = 3'd4;
        AWBURST = 2'b01;
        AWVALID = 1'b1;
        do @(posedge ACLK); while (!AWREADY);
        @(negedge ACLK);
        AWVALID = 1'b0;

        for (integer beat = 0; beat < 256; beat = beat + 1) begin
            @(negedge ACLK);
            WDATA = DATA_W'(beat);
            WLAST = (beat == 255);
            WVALID = 1'b1;
            @(posedge ACLK);
            if (!WREADY)
                $fatal(1, "WREADY dropped during parameter boundary test");
            @(negedge ACLK);
            WVALID = 1'b0;
        end

        if (!BVALID || BRESP != 2'b10 || BID != 4'hA)
            $fatal(1, "overflowing burst was not rejected with SLVERR");
        BREADY = 1'b1;
        @(posedge ACLK);
        $display("PARAMETER REGRESSION PASS: burst endpoint carry preserved");
        $finish;
    end
endmodule
