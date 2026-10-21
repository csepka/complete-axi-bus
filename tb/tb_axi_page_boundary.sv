`timescale 1ns/1ps
// Separates 4-KiB rejection from RAM-extent rejection using an 8-KiB target.
module tb_axi_page_boundary;
    logic ACLK,ARESETn;
    initial begin ACLK=0;forever #5 ACLK=~ACLK;end
    axi_if #(.ADDR_W(16),.DATA_W(64),.ID_W(4)) bus(.ACLK,.ARESETn);
    axi_sub #(.ADDR_W(16),.DATA_W(64),.MEM_BYTES(8192),.ADDR_OFFSET_W(16)) dut(.ACLK,.ARESETn,.axi(bus));
    axi_protocol_checker checker_inst(.ACLK,.ARESETn,.axi(bus));
    initial begin #10000;$fatal(1,"page-boundary timeout");end
    task automatic write_burst(input logic[15:0] addr,input int beats,input logic[63:0] data,input logic[1:0] resp);
        @(negedge ACLK);bus.AWADDR=addr;bus.AWLEN=8'(beats-1);bus.AWVALID=1;
        do @(posedge ACLK);while(!bus.AWREADY);
        @(negedge ACLK);bus.AWVALID=0;
        for(int b=0;b<beats;b++)begin
            bus.WVALID=1;bus.WDATA=data;bus.WLAST=(b==beats-1);
            do @(posedge ACLK);while(!bus.WREADY);
            @(negedge ACLK);bus.WVALID=0;
        end
        bus.BREADY=1;
        do @(posedge ACLK);while(!bus.BVALID);
        assert(bus.BRESP==resp && bus.BID==4'hA)else $fatal(1,"page write status/ID");
        @(negedge ACLK);bus.BREADY=0;
    endtask
    task automatic read_burst(input logic[15:0] addr,input int beats,input logic[63:0] data,input logic[1:0] resp);
        @(negedge ACLK);bus.ARADDR=addr;bus.ARLEN=8'(beats-1);bus.ARVALID=1;
        do @(posedge ACLK);while(!bus.ARREADY);
        @(negedge ACLK);bus.ARVALID=0;bus.RREADY=1;
        for(int b=0;b<beats;b++)begin
            do @(posedge ACLK);while(!bus.RVALID);
            assert(bus.RRESP==resp && bus.RID==4'hB && bus.RLAST==(b==beats-1) && bus.RDATA===data)
                else $fatal(1,"page read response/data");
            @(negedge ACLK);
        end
        bus.RREADY=0;
    endtask
    initial begin
        ARESETn=0;
        bus.AWVALID=0;bus.AWADDR=0;bus.AWPROT=0;bus.AWID=4'hA;bus.AWLEN=0;bus.AWSIZE=3;bus.AWBURST=1;
        bus.WVALID=0;bus.WDATA=0;bus.WSTRB='1;bus.WLAST=0;bus.BREADY=0;
        bus.ARVALID=0;bus.ARADDR=0;bus.ARPROT=0;bus.ARID=4'hB;bus.ARLEN=0;bus.ARSIZE=3;bus.ARBURST=1;bus.RREADY=0;
        repeat(3)@(negedge ACLK);ARESETn=1;
        write_burst(16'h0FF8,1,64'h1234,0);
        write_burst(16'h1000,1,64'h5678,0);
        write_burst(16'h0FF8,2,64'hBAD,2'b10);
        read_burst(16'h0FF8,2,0,2'b10);
        read_burst(16'h0FF8,1,64'h1234,0);
        read_burst(16'h1000,1,64'h5678,0);
        $display("PAGE BOUNDARY REGRESSION PASS: 4-KiB rule isolated from 8-KiB memory extent; rejected write preserved neighbors");
        $finish;
    end
endmodule
