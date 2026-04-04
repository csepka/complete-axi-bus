# Testbenches and verification

## Recommended (Makefile shortcuts)

From project root:

```sh
make tb-sub-run   # AXI-Lite subordinate testbench
make tb-mgr-run   # AXI-Lite manager testbench
make tb-run-all   # Run both standalone testbenches
```

## AXI-Lite subordinate testbench (manual)

- Testbench file: `tb/axi_lite_sub_tb.sv`
- DUT file: `src/axi_lite_sub.sv`

Run with Icarus Verilog:

```sh
iverilog -g2012 -o /tmp/axi_lite_sub_tb.out src/axi_lite_sub.sv tb/axi_lite_sub_tb.sv
vvp /tmp/axi_lite_sub_tb.out
```

## AXI-Lite manager testbench (manual)

- Testbench file: `tb/axi_lite_mgr_tb.sv`
- DUT files: `src/axi_lite_mgr.sv`, `src/axi_lite_sub.sv`

Run with Icarus Verilog:

```sh
iverilog -g2012 -o /tmp/axi_lite_mgr_tb.out src/axi_lite_mgr.sv src/axi_lite_sub.sv tb/axi_lite_mgr_tb.sv
vvp /tmp/axi_lite_mgr_tb.out
```
