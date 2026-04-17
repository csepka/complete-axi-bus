# AXI5 Manager/Subordinate Implementation

A complete SystemVerilog implementation of the full AXI5 protocol, including both Manager (Master) and Subordinate (Slave) interfaces. This is a full AXI5 implementation — not AXI5-Lite.

## Overview

This project implements the full AXI4 bus protocol with all five channels:

- **AW** — Write Address Channel
- **W** — Write Data Channel
- **B** — Write Response Channel
- **AR** — Read Address Channel
- **R** — Read Data Channel

Supports AXI5 features including burst transfers, outstanding transactions, all burst types (FIXED, INCR, WRAP), atomic transactions, and poison signals.

## Requirements

- [Verilator](https://www.veripool.org/verilator/) v5.0+
- A C++ compiler (GCC or Clang)
- `make`

## Project Structure

```
.
├── rtl/              # SystemVerilog source files
│   ├── axi_manager.sv
│   └── axi_subordinate.sv
├── tb/               # Testbenches
├── sim/              # Simulation scripts and output
└── README.md
```

## Getting Started

```bash
# Lint/compile with Verilator
verilator --lint-only -sv rtl/*.sv

# Run simulation
make sim
```

## AXI5 Protocol Reference

- [ARM AXI5 Specification (IHI0022H)](https://developer.arm.com/documentation/ihi0022/latest)
