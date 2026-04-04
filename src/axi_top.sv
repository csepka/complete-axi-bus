`timescale 1ns/1ps


module axi_top #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NM = 3,
    parameter NS = 3,
    parameter BYTES = (DATA_W/8)

)(
    input logic ACLK,
    input logic ARESETn,

    input logic [1:0] mgr_sel,
    input logic cmd_valid,
    input logic cmd_write,
    input logic [ADDR_W-1:0] cmd_addr,
    input logic [DATA_W-1:0] cmd_wdata,

    output logic cmd_ready,
    output logic cmd_done,
    output logic [DATA_W-1:0] cmd_rdata
);

    // Manager command sideband
    logic [NM-1:0] m_cmd_valid;
    logic [NM-1:0] m_cmd_write;
    logic [NM-1:0][ADDR_W-1:0] m_cmd_addr;
    logic [NM-1:0][DATA_W-1:0] m_cmd_wdata;

    logic [NM-1:0] m_cmd_ready;
    logic [NM-1:0] m_cmd_done;
    logic [NM-1:0][DATA_W-1:0] m_cmd_rdata;

    // Declaring interface arrays
    axi_lite_if #(ADDR_W, DATA_W) m_if [NM] (.ACLK(ACLK), .ARESETn(ARESETn));
    axi_lite_if #(ADDR_W, DATA_W) s_if [NS] (.ACLK(ACLK), .ARESETn(ARESETn));

    always_comb begin
        for (int m = 0; m < NM; m++) begin
            m_cmd_valid[m] = 1'b0;
            m_cmd_write[m] = 1'b0;
            m_cmd_addr[m] = 0;
            m_cmd_wdata[m] = 0;
        end

        if (int'($unsigned(mgr_sel)) < $unsigned(NM)) begin
            m_cmd_valid[mgr_sel] = cmd_valid;
            m_cmd_write[mgr_sel] = cmd_write;
            m_cmd_addr[mgr_sel] = cmd_addr;
            m_cmd_wdata[mgr_sel] = cmd_wdata;
        end
    end

    // mux back status from selected manager

    always_comb begin
        cmd_ready = 1'b0;
        cmd_done = 1'b0;
        cmd_rdata = 0;


        if (int'($unsigned(mgr_sel)) < $unsigned(NM)) begin
            cmd_ready = m_cmd_ready[mgr_sel];
            cmd_done = m_cmd_done[mgr_sel];
            cmd_rdata = m_cmd_rdata[mgr_sel];
        end
    end


    for (genvar m = 0; m < NM; m++) begin : GEN_MGR
        axi_lite_mgr #(
            .ADDR_W(ADDR_W),
            .DATA_W(DATA_W)
        ) u_mgr (
            .ACLK(ACLK),
            .ARESETn(ARESETn),

            .cmd_valid(m_cmd_valid[m]),
            .cmd_write(m_cmd_write[m]),
            .cmd_addr(m_cmd_addr[m]),
            .cmd_wdata(m_cmd_wdata[m]),
            .cmd_ready(m_cmd_ready[m]),
            .cmd_done(m_cmd_done[m]),
            .cmd_rdata(m_cmd_rdata[m]),

            .axi(m_if[m].mgr)
        );
    end

    for (genvar s = 0; s < NS; s++) begin : GEN_SUB
        axi_lite_sub #(
            .ADDR_W(ADDR_W),
            .DATA_W(DATA_W)
        ) u_sub (
            .ACLK(ACLK),
            .ARESETn(ARESETn),
            .axi(s_if[s].sub)
        );
    end

    axi_lite_bus #(
        .NM(NM), .NS(NS), .ADDR_W(ADDR_W), .DATA_W(DATA_W), .BYTES(BYTES)
    ) u_bus (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .m_axi(m_if),
        .s_axi(s_if)
    );

endmodule