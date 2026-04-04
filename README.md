# AXI4 Manager/Subordinate Implementation

A complete SystemVerilog implementation of the full AXI4 protocol, including both Manager (Master) and Subordinate (Slave) interfaces. This is a full AXI4 implementation — not AXI4-Lite.

## Overview

This project implements the full AXI4 bus protocol with all five channels:

- **AW** — Write Address Channel
- **W** — Write Data Channel
- **B** — Write Response Channel
- **AR** — Read Address Channel
- **R** — Read Data Channel

Supports AXI4 features including burst transfers, outstanding transactions, and all burst types (FIXED, INCR, WRAP).

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

## AXI4 Protocol Reference

- [ARM AXI4 Specification (IHI0022)](https://developer.arm.com/documentation/ihi0022/latest)
