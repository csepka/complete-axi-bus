#!/usr/bin/env python3
"""Flatten only the request queue's interface ports for stock Yosys.

The source logic, packed request vectors, FIFO arrays and state machines are copied
verbatim. This is a structural port expansion, not a replacement queue model.
"""
from pathlib import Path
import runpy
ROOT=Path(__file__).resolve().parents[2]
schema=runpy.run_path(str(ROOT/'synthesis/scripts/make_flat_top.py'))
ports=[]
for side in ['up','down']:
    for sig,w in schema['widths'].items():
        direction='input' if (sig in schema['manager_outputs'])==(side=='up') else 'output'
        ports.append(f'    {direction} logic '+('' if w=='1' else f'[{w}-1:0] ')+f'{side}_{sig}')
s=(ROOT/'src/axi_request_queue.sv').read_text()
s=s.replace('module axi_request_queue #(', 'module axi_request_queue_flat #(')
s=s.replace('    axi_if.sub up,\n    axi_if.mgr down', ',\n'.join(ports))
s=s.replace('up.', 'up_').replace('down.', 'down_')
(ROOT/'build/axi_request_queue_flat.sv').write_text(s)
