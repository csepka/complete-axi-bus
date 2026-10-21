# EXAMPLE integration constraints, not executed timing evidence.
# Adapt input/output delays, clock uncertainty, fanout/load, PVT and library paths
# to the actual target before STA. A 10ns request is not an achieved clock period.
create_clock -name ACLK -period 10.0 [get_ports ACLK]
set_clock_uncertainty 0.2 [get_clocks ACLK]
set_input_delay 1.0 -clock ACLK [get_ports {m_* s_*}]
set_output_delay 1.0 -clock ACLK [get_ports {m_* s_*}]
# ARESETn must be synchronously deasserted externally; recovery/removal analysis
# and reset-domain constraints belong to the technology-specific integration.
