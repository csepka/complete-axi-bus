VERILATOR ?= verilator
YOSYS     ?= yosys
PYTHON    ?= python3
BUILD_DIR ?= build
TRACE     ?= 0
RUN_ARGS  ?=

RTL := src/axi_if.sv \
       src/axi_ram.sv \
       src/axi_sub.sv \
       src/axi_mgr.sv \
       src/axi_interconnect.sv \
       src/axi_top.sv

CHECKER := src/axi_protocol_checker.sv
VFLAGS  := -sv --timing --assert --Wall -Wno-UNUSEDSIGNAL -Wno-UNSIGNED -Wno-SYNCASYNCNET

ifeq ($(TRACE),1)
VFLAGS += --trace --trace-depth 6
endif

.PHONY: all lint test test-top test-burst test-params synth ci waves waveform clean help

all: ci

lint:
	$(VERILATOR) $(VFLAGS) --lint-only --top-module axi_top $(RTL)

test: test-top test-burst test-params

test-top:
	mkdir -p $(BUILD_DIR)/obj_top
	$(VERILATOR) $(VFLAGS) --binary --Mdir $(BUILD_DIR)/obj_top \
		--top-module tb_top tb/tb_top.sv $(RTL) -o Vtb_top
	$(BUILD_DIR)/obj_top/Vtb_top

test-burst:
	mkdir -p $(BUILD_DIR)/obj_burst
	$(VERILATOR) $(VFLAGS) --binary --Mdir $(BUILD_DIR)/obj_burst \
		--top-module tb_axi_burst tb/tb_axi_burst.sv $(CHECKER) $(RTL) tb/axi_stall_sub.sv -o Vtb_axi_burst
	$(BUILD_DIR)/obj_burst/Vtb_axi_burst $(RUN_ARGS)

test-params:
	mkdir -p $(BUILD_DIR)/obj_params
	$(VERILATOR) $(VFLAGS) --binary --Mdir $(BUILD_DIR)/obj_params \
		--top-module tb_axi_ram_params tb/tb_axi_ram_params.sv src/axi_ram.sv -o Vtb_axi_ram_params
	$(BUILD_DIR)/obj_params/Vtb_axi_ram_params

synth:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -q -l $(BUILD_DIR)/yosys.log -p \
		'read_verilog -sv -DSYNTHESIS src/axi_ram.sv; hierarchy -check -top axi_ram; synth -top axi_ram -run begin:coarse; stat'
	@grep -E '^[[:space:]]+[0-9]+ (wires|wire bits|memories|memory bits|cells)' $(BUILD_DIR)/yosys.log

ci: lint test synth

waves:
	$(MAKE) TRACE=1 RUN_ARGS=+trace test-burst

waveform: waves
	$(PYTHON) tools/vcd_to_svg.py $(BUILD_DIR)/tb_axi_burst.vcd docs/images/axi-aw-backpressure.svg

clean:
	rm -rf $(BUILD_DIR)

help:
	@echo "make lint        Lint the complete integrated RTL"
	@echo "make test        Run command-level and burst regressions"
	@echo "make synth       Synthesize the flat AXI RAM core with Yosys"
	@echo "make ci          Run the full local CI flow"
	@echo "make waves       Run burst regression with VCD tracing"
	@echo "make waveform    Regenerate the documented SVG from the VCD"
	@echo "make clean       Remove generated build products"
