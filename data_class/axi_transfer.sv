class axi_transfer #(parameter DATA_W = 32);

    logic [DATA_W-1:0] data;
    logic [DATA_W/8-1:0] strb;
    logic last;
    function new();
        data = '0;
        strb = '1;
        last = 1'b0;
        
    endfunction //new()

    function void print();
        $display("  transfer: data=0x%08x strb=0x%x last=%0b", data, strb, last);
    endfunction
endclass //axi_transfer