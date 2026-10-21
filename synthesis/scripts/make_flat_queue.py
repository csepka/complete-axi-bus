#!/usr/bin/env python3
"""Mechanically expand interface ports without changing queue behavior."""
from pathlib import Path
from axi_ports import expand_interfaces
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'src/axi_request_queue.sv').read_text()
(ROOT/'build').mkdir(exist_ok=True)
(ROOT/'build/axi_request_queue_flat.sv').write_text(expand_interfaces(source,'axi_request_queue','axi_request_queue_flat'))
