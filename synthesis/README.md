# Synthesis

`make synth` performs tool-independent Yosys elaboration and coarse synthesis of the flat-port `axi_ram` core. The checked default result retains one 32-Kbit inferred memory.

`synthesis/subordinate/config.json` provides an OpenLane configuration for technology-mapped exploration of the same core. The interface-based integrated top is linted and simulated with Verilator; its SystemVerilog interface arrays require a synthesis frontend with interface support or a project-specific flat wrapper.
