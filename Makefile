RTL_DIR  := rtl
TB_DIR   := tb
SIM_DIR  := sim

TOP      ?= axi_top
VERILATOR := verilator

.PHONY: lint sim clean

lint:
	$(VERILATOR) --lint-only -sv $(RTL_DIR)/*.sv

sim:
	$(VERILATOR) --cc --exe --build -sv \
		$(RTL_DIR)/*.sv \
		$(TB_DIR)/$(TOP)_tb.cpp \
		-o $(SIM_DIR)/$(TOP)_sim
	./$(SIM_DIR)/$(TOP)_sim

clean:
	rm -rf obj_dir $(SIM_DIR)/$(TOP)_sim
