class axi_transcation #(parameter ADDR_W, DATA_W = 32, ID_W = 8);
    logic [ID_W-1:0] id;
    logic [ADDR_W-1:0] addr;
    logiv [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;

    logic is_write;

    axi_transfer #(DATA_W) transfer[];

    logic [1:0] resp;

    function new();
        id = '0;
        addr = '0;
        len = '0;
        size = 3'b010;
        burst = 2'b01;
        resp = '0;
    endfunction //new()

    function void print();
        $display("txn: %s id=%0d addr=0x%08x len=%0d size=%0d burst=%0b",
        is_write ? "WRITE" : "READ", id, addr, len, size, burst);
        foreach (transfers[i])
            transfers[i].print();
    endfunction
endclass //axi_transcation