#!/usr/bin/env python3
"""Mechanically expand interface ports without changing slice behavior."""
from pathlib import Path
from axi_ports import expand_interfaces
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'src/axi_register_slice.sv').read_text()
(ROOT/'build').mkdir(exist_ok=True)
(ROOT/'build/axi_register_slice_flat.sv').write_text(expand_interfaces(source,'axi_register_slice','axi_register_slice_flat'))
