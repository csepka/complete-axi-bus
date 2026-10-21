#!/usr/bin/env python3
"""Run the full directed outstanding bench with a Yosys-lowered queue netlist."""
import argparse
from pathlib import Path
import runpy
import subprocess
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--depth',type=int,default=4);a=p.parse_args()
subprocess.run(['python3','synthesis/scripts/run_synthesis.py','--queue','--width','64','--addr-width','40','--depth',str(a.depth),'--label','netcheck'],cwd=ROOT,check=True)
schema=runpy.run_path(str(ROOT/'synthesis/scripts/make_flat_top.py'))
s='''module axi_request_queue #(
    parameter int ADDR_W=40,DATA_W=64,ID_W=4,MAX_OUTSTANDING=4
)(input logic ACLK,ARESETn,axi_if.sub up,axi_if.mgr down);
'''
s+=f'    initial assert(ADDR_W==40 && DATA_W==64 && ID_W==4 && MAX_OUTSTANDING=={a.depth}) else $fatal(1,"fixed netlist parameter mismatch");\n'
s+='    axi_request_queue_flat netlist(.ACLK,.ARESETn,\n'
s+=',\n'.join(f'        .{side}_{sig}({side}.{sig})' for side in ['up','down'] for sig in schema['widths'])+'\n    );\nendmodule\n'
build=ROOT/'build'/f'queue-netlist-d{a.depth}';build.mkdir(parents=True,exist_ok=True)
(build/'axi_request_queue.sv').write_text(s)
command=['verilator','-sv','--timing','--assert','--Wall','-Wno-UNUSEDSIGNAL','-Wno-UNSIGNED','-Wno-SYNCASYNCNET',
    # Yosys emits noncanonical filenames and local helper signals; RTL lint remains strict.
    '-Wno-DECLFILENAME','--output-split','0','--binary','-j','4','--Mdir',str(build),'--top-module','tb_axi_outstanding',
    '+define+AXI_INTERNAL_CHECKS',f'-GDEPTH={a.depth}','tb/tb_axi_outstanding.sv','src/axi_if.sv','src/axi_protocol_checker.sv',
    'src/axi_interconnect.sv','src/axi_target_arbiter.sv','src/axi_ram.sv','src/axi_sub.sv','tb/axi_stall_sub.sv',
    str(build/'axi_request_queue.sv'),f'synthesis/reports/netcheck-queue-d{a.depth}-w64-a40-netlist.v']
subprocess.run(command,cwd=ROOT,check=True)
subprocess.run([str(build/'Vtb_axi_outstanding')],cwd=ROOT,check=True)
