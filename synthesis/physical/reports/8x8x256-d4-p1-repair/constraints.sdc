create_clock -name ACLK -period 10.0 [get_ports ACLK]
set_clock_uncertainty 0.20 [get_clocks ACLK]
set_clock_transition 0.10 [get_clocks ACLK]
set data_inputs [get_ports {m_AWVALID* m_AWADDR* m_AWPROT* m_AWID* m_AWLEN* m_AWSIZE* m_AWBURST* m_WVALID* m_WDATA* m_WSTRB* m_WLAST* m_BREADY* m_ARVALID* m_ARADDR* m_ARPROT* m_ARID* m_ARLEN* m_ARSIZE* m_ARBURST* m_RREADY* s_AWREADY* s_WREADY* s_BVALID* s_BRESP* s_BID* s_ARREADY* s_RVALID* s_RDATA* s_RRESP* s_RID* s_RLAST*}]
set_input_delay -clock ACLK -max 1.0 $data_inputs
set_input_delay -clock ACLK -min 0.2 $data_inputs
set_input_transition 0.10 $data_inputs
set_output_delay -clock ACLK -max 1.0 [all_outputs]
set_output_delay -clock ACLK -min 0.2 [all_outputs]
# Nangate45 declares capacitance in fF, not pF.
set_load 5.0 [all_outputs]
# Integration contract: asynchronous assertion, synchronized deassertion outside
# this block. Recovery/removal of this external reset is NOT signed off here.
set_false_path -from [get_ports ARESETn]
