
# Definitions for files

# OOP top defintions
OOP_TB_DIR ?= tb/oop_tb
OOP_TB_TOP ?= axi_lite_tb_top_oop
OOP_TB_OUT ?= sim_oop
OOP_TB_SRCS ?= $(OOP_TB_DIR)/cmd_if.sv \
			   $(OOP_TB_DIR)/axi_lite_monitor.sv \
			   $(OOP_TB_DIR)/axi_lite_scoreboard.sv \
			   $(OOP_TB_DIR)/axi_lite_driver.sv \
			   $(OOP_TB_DIR)/axi_lite_env.sv \
			   $(OOP_TB_DIR)/axi_lite_test.sv \
			   $(OOP_TB_DIR)/axi_lite_top_tb_oop.sv

# First top definitions
TOP       ?= tb_top
OUT       ?= sim_top
TB_OUTDIR ?= sim

TB        ?= tb/$(TOP).sv
VCD       ?= $(TB_OUTDIR)/$(TOP).vcd
SRCS      ?= src/axi_if.sv src/axi_top.sv src/axi_lite_bus.sv src/axi_lite_mgr.sv src/axi_lite_sub.sv

# Standalone testbench flow (Icarus Verilog)
IVERILOG  ?= iverilog
VVP       ?= vvp
SUB_TB_OUT ?= $(TB_OUTDIR)/axi_lite_sub_tb.out
MGR_TB_OUT ?= $(TB_OUTDIR)/axi_lite_mgr_tb.out

# Verilator
VERILATOR ?= verilator
VFLAGS    ?= -sv --timing -Wno-fatal --binary --top-module $(TOP)

# mac specific
SDKROOT   ?= $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
CFLAGS    ?= -isysroot $(SDKROOT) -isystem $(SDKROOT)/usr/include/c++/v1

# Tracing
TRACE     ?= 0
ifeq ($(TRACE),1)
	VFLAGS += --trace --trace-depth 10 --trace-max-array 2048
endif

# targets
.PHONY: all build run waves tb-sub-build tb-sub-run tb-mgr-build tb-mgr-run tb-run-all oop-run oop-waves clean help

all: build

build:
	mkdir -p $(TB_OUTDIR)
	$(VERILATOR) $(VFLAGS) \
	  $(TB) $(SRCS) \
	  -CFLAGS "$(CFLAGS)" \
	  -o $(OUT)

run: build
	./obj_dir/$(OUT)

waves:
	$(MAKE) TRACE=1 run

tb-sub-build:
	mkdir -p $(TB_OUTDIR)
	$(IVERILOG) -g2012 -o $(SUB_TB_OUT) src/legacy/axi_lite_sub.sv tb/axi_lite_sub_tb.sv

tb-sub-run: tb-sub-build
	$(VVP) $(SUB_TB_OUT)

tb-mgr-build:
	mkdir -p $(TB_OUTDIR)
	$(IVERILOG) -g2012 -o $(MGR_TB_OUT) src/legacy/axi_lite_mgr.sv src/legacy/axi_lite_sub.sv tb/axi_lite_mgr_tb.sv

tb-mgr-run: tb-mgr-build
	$(VVP) $(MGR_TB_OUT)

tb-run-all: tb-sub-run tb-mgr-run

oop-run:
	mkdir -p $(TB_OUTDIR)
	$(VERILATOR) -sv --timing --trace -Wno-fatal --binary --top-module $(OOP_TB_TOP) \
		$(OOP_TB_SRCS) $(SRCS) \
		-CFLAGS "$(CFLAGS)" \
		-o $(OOP_TB_OUT)
	./obj_dir/$(OOP_TB_OUT)

oop-waves:
	mkdir -p $(TB_OUTDIR)
	$(VERILATOR) -sv --timing --trace -Wno-fatal --binary --top-module $(OOP_TB_TOP) \
		$(OOP_TB_SRCS) $(SRCS) \
		-CFLAGS "$(CFLAGS)" \
		-o $(OOP_TB_OUT)
	./obj_dir/$(OOP_TB_OUT)



clean:
	rm -rf obj_dir $(OUT) *.vcd $(TB_OUTDIR)/*.vcd $(SUB_TB_OUT) $(MGR_TB_OUT)

help:
	@echo "make build        # build simulator"
	@echo "make run          # build  + run"
	@echo "make waves        # build + run with --trace"
	@echo "make tb-sub-run   # build + run axi_lite_sub_tb (iverilog)"
	@echo "make tb-mgr-run   # build + run axi_lite_mgr_tb (iverilog)"
	@echo "make tb-run-all   # run both standalone testbenches"
	@echo "make clean        # remove build products"
	@echo ""
	@echo "Knobs:"
	@echo "  TOP=tb_top OUT=sim_top TRACE=1"
