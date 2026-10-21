VERILATOR ?= verilator
YOSYS     ?= yosys
PYTHON    ?= python3
BUILD_DIR ?= build
TRACE     ?= 0
DEPTH     ?= 4
PIPELINE  ?= 0
RUN_ARGS  ?=

RTL := src/axi_if.sv \
       src/axi_ram.sv \
       src/axi_sub.sv \
       src/axi_mgr.sv \
       src/axi_channel_fifo.sv \
       src/axi_register_slice.sv \
       src/axi_request_queue.sv \
       src/axi_target_arbiter.sv \
       src/axi_interconnect.sv \
       src/axi_top.sv

CHECKER := src/axi_protocol_checker.sv
VFLAGS  := -sv --timing --assert --Wall -Wno-UNUSEDSIGNAL -Wno-UNSIGNED -Wno-SYNCASYNCNET

ifeq ($(TRACE),1)
VFLAGS += --trace --trace-depth 6
endif

.PHONY: all lint test test-top test-burst test-params test-outstanding test-channel-fifo test-page-boundary synth synth-queue test-queue-netlist benchmark extended ci waves waveform clean help

all: ci

lint:
	$(VERILATOR) $(VFLAGS) --lint-only --top-module axi_top $(RTL)

test: test-top test-burst test-params test-outstanding test-channel-fifo test-page-boundary

test-top:
	mkdir -p $(BUILD_DIR)/obj_top
	$(VERILATOR) $(VFLAGS) --binary --Mdir $(BUILD_DIR)/obj_top \
		--top-module tb_top tb/tb_top.sv $(RTL) -o Vtb_top
	$(BUILD_DIR)/obj_top/Vtb_top

test-burst:
	mkdir -p $(BUILD_DIR)/obj_burst_p$(PIPELINE)
	$(VERILATOR) $(VFLAGS) --binary --Mdir $(BUILD_DIR)/obj_burst_p$(PIPELINE) \
		--top-module tb_axi_burst -GPIPELINE=$(PIPELINE) tb/tb_axi_burst.sv $(CHECKER) $(RTL) tb/axi_stall_sub.sv -o Vtb_axi_burst
	$(BUILD_DIR)/obj_burst_p$(PIPELINE)/Vtb_axi_burst$(if $(strip $(RUN_ARGS)), $(RUN_ARGS))

test-params:
	mkdir -p $(BUILD_DIR)/obj_params
	$(VERILATOR) $(VFLAGS) --binary --Mdir $(BUILD_DIR)/obj_params \
		--top-module tb_axi_ram_params tb/tb_axi_ram_params.sv src/axi_ram.sv -o Vtb_axi_ram_params
	$(BUILD_DIR)/obj_params/Vtb_axi_ram_params

test-outstanding:
	mkdir -p $(BUILD_DIR)/obj_outstanding_d$(DEPTH)_p$(PIPELINE)
	$(VERILATOR) $(VFLAGS) --binary -j 4 --Mdir $(BUILD_DIR)/obj_outstanding_d$(DEPTH)_p$(PIPELINE) \
		--output-split 0 +define+AXI_INTERNAL_CHECKS --top-module tb_axi_outstanding -GDEPTH=$(DEPTH) -GPIPELINE=$(PIPELINE) tb/tb_axi_outstanding.sv $(CHECKER) $(RTL) tb/axi_stall_sub.sv -o Vtb_axi_outstanding
	$(BUILD_DIR)/obj_outstanding_d$(DEPTH)_p$(PIPELINE)/Vtb_axi_outstanding

synth:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -q -l $(BUILD_DIR)/yosys.log -p \
		'read_verilog -sv -DSYNTHESIS src/axi_ram.sv; hierarchy -check -top axi_ram; synth -top axi_ram -run begin:fine; check -assert; stat' || \
		{ cat $(BUILD_DIR)/yosys.log; exit 1; }
	@grep -E '^[[:space:]]+[0-9]+ (wires|wire bits|memories|memory bits|cells)' $(BUILD_DIR)/yosys.log

test-page-boundary:
	mkdir -p $(BUILD_DIR)/obj_page_boundary
	$(VERILATOR) $(VFLAGS) --binary -j 4 --Mdir $(BUILD_DIR)/obj_page_boundary \
		--top-module tb_axi_page_boundary tb/tb_axi_page_boundary.sv $(CHECKER) src/axi_if.sv src/axi_sub.sv src/axi_ram.sv
	$(BUILD_DIR)/obj_page_boundary/Vtb_axi_page_boundary

test-channel-fifo:
	mkdir -p $(BUILD_DIR)/obj_channel_fifo
	$(VERILATOR) $(VFLAGS) --binary -j 4 --Mdir $(BUILD_DIR)/obj_channel_fifo \
		--top-module tb_axi_channel_fifo tb/tb_axi_channel_fifo.sv src/axi_channel_fifo.sv
	$(BUILD_DIR)/obj_channel_fifo/Vtb_axi_channel_fifo

synth-queue:
	$(PYTHON) synthesis/scripts/run_synthesis.py --queue --depth $(DEPTH) --width 64 --label queued

test-queue-netlist:
	$(PYTHON) synthesis/scripts/check_queue_netlist.py --depth $(DEPTH)

benchmark:
	$(PYTHON) benchmarks/benchmark_runner.py --label queued-d4 --depth 4 --config 2x2x64 --config 4x4x128 --config 8x8x256

extended:
	$(MAKE) DEPTH=1 test-outstanding
	$(MAKE) DEPTH=3 test-outstanding
	$(MAKE) DEPTH=5 test-outstanding
	$(MAKE) test-queue-netlist
	$(MAKE) PIPELINE=1 test-burst
	$(MAKE) PIPELINE=1 test-outstanding
	$(PYTHON) synthesis/scripts/check_queue_netlist.py --slice
	$(PYTHON) benchmarks/verify_matrix.py

ci: lint test synth

waves:
	$(MAKE) TRACE=1 RUN_ARGS=+trace test-burst

waveform: waves
	$(PYTHON) tools/vcd_to_svg.py $(BUILD_DIR)/tb_axi_burst.vcd docs/images/axi-aw-backpressure.svg

clean:
	rm -rf $(BUILD_DIR)

help:
	@echo "make lint        Lint the complete integrated RTL"
	@echo "make test        Run integration, burst, parameter, and outstanding regressions"
	@echo "make synth       Run actual coarse Yosys RAM synthesis and structural checks"
	@echo "make extended    Queue-depth, netlist, and seeded parameter matrix"
	@echo "make benchmark   Run measured fabric performance scenarios"
	@echo "make ci          Run the full local CI flow"
	@echo "make waves       Run burst regression with VCD tracing"
	@echo "make waveform    Regenerate the documented SVG from the VCD"
	@echo "make clean       Remove generated build products"
