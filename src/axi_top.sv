module axi_top #(
    parameter int ADDR_W       = 32,
    parameter int DATA_W       = 32,
    parameter int ID_W         = 4,
    parameter int NM           = 3,
    parameter int NS           = 3,
    parameter int MGR_SEL_W    = (NM > 1) ? $clog2(NM) : 1,
    parameter int S_ADDR_WIDTH = 16,
    parameter int MEM_BYTES    = 4096
) (
    input  logic                 ACLK,
    input  logic                 ARESETn,
    input  logic [MGR_SEL_W-1:0] mgr_sel,
    input  logic                 cmd_valid,
    input  logic                 cmd_write,
    input  logic [ADDR_W-1:0]    cmd_addr,
    input  logic [DATA_W-1:0]    cmd_wdata,
    output logic                 cmd_ready,
    output logic                 cmd_done,
    output logic [DATA_W-1:0]    cmd_rdata,
    output logic [1:0]           cmd_resp
);
    logic [NM-1:0] m_cmd_valid;
    logic [NM-1:0] m_cmd_ready;
    logic [NM-1:0] m_cmd_done;
    logic [NM-1:0][DATA_W-1:0] m_cmd_rdata;
    logic [NM-1:0][1:0] m_cmd_resp;
    logic command_active;
    logic [MGR_SEL_W-1:0] active_mgr;

    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W))
        m_if [NM] (.ACLK, .ARESETn);
    axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W))
        s_if [NS] (.ACLK, .ARESETn);

    always_comb begin
        m_cmd_valid = '0;
        cmd_ready = 1'b0;
        cmd_done = 1'b0;
        cmd_rdata = '0;
        cmd_resp = 2'b11;
        if (command_active) begin
            cmd_done = m_cmd_done[active_mgr];
            cmd_rdata = m_cmd_rdata[active_mgr];
            cmd_resp = m_cmd_resp[active_mgr];
        end else if (int'(mgr_sel) < NM) begin
            m_cmd_valid[mgr_sel] = cmd_valid;
            cmd_ready = m_cmd_ready[mgr_sel];
            cmd_rdata = m_cmd_rdata[mgr_sel];
            cmd_resp = m_cmd_resp[mgr_sel];
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            command_active <= 1'b0;
            active_mgr <= '0;
        end else begin
            if (!command_active && cmd_valid && cmd_ready) begin
                command_active <= 1'b1;
                active_mgr <= mgr_sel;
            end else if (command_active && m_cmd_done[active_mgr]) begin
                command_active <= 1'b0;
            end
        end
    end

    generate
        for (genvar m = 0; m < NM; m++) begin : g_managers
            axi_mgr #(
                .ADDR_W(ADDR_W),
                .DATA_W(DATA_W),
                .ID_W(ID_W),
                .MANAGER_ID(ID_W'(m))
            ) u_mgr (
                .ACLK,
                .ARESETn,
                .cmd_valid(m_cmd_valid[m]),
                .cmd_write,
                .cmd_addr,
                .cmd_wdata,
                .cmd_ready(m_cmd_ready[m]),
                .cmd_done(m_cmd_done[m]),
                .cmd_rdata(m_cmd_rdata[m]),
                .cmd_resp(m_cmd_resp[m]),
                .axi(m_if[m].mgr)
            );
        end

        for (genvar s = 0; s < NS; s++) begin : g_subordinates
            axi_sub #(
                .ADDR_W(ADDR_W),
                .DATA_W(DATA_W),
                .ID_W(ID_W),
                .MEM_BYTES(MEM_BYTES),
                .ADDR_OFFSET_W(S_ADDR_WIDTH)
            ) u_sub (
                .ACLK,
                .ARESETn,
                .axi(s_if[s].sub)
            );
        end
    endgenerate

    axi_interconnect #(
        .NM(NM),
        .NS(NS),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .S_ADDR_WIDTH(S_ADDR_WIDTH)
    ) u_interconnect (
        .ACLK,
        .ARESETn,
        .m_axi(m_if),
        .s_axi(s_if)
    );
endmodule
