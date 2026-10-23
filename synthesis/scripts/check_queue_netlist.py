#!/usr/bin/env python3
"""Run the full directed outstanding bench with a Yosys-lowered queue netlist."""
import argparse
from pathlib import Path
from axi_ports import WIDTHS, MANAGER_OUTPUTS
import subprocess
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--depth',type=int,default=4);p.add_argument('--slice',action='store_true');a=p.parse_args()
subprocess.run(['python3','synthesis/scripts/run_synthesis.py','--slice' if a.slice else '--queue','--width','64','--addr-width','40','--depth',str(a.depth),'--label','netcheck'],cwd=ROOT,check=True)
module='axi_register_slice' if a.slice else 'axi_request_queue'
param='parameter bit ENABLE=0' if a.slice else 'parameter int MAX_OUTSTANDING=4'
condition='ENABLE==1' if a.slice else f'MAX_OUTSTANDING=={a.depth}'
s=f"module {module} #(parameter int ADDR_W=40,DATA_W=64,ID_W=4,{param})(input logic ACLK,ARESETn,axi_if.sub up,axi_if.mgr down);\n"
s+=f'    initial assert(ADDR_W==40 && DATA_W==64 && ID_W==4 && {condition}) else $fatal(1,"fixed netlist parameter mismatch");\n'
s+=f'    {module}_flat netlist(.ACLK,.ARESETn,\n'
s+=',\n'.join(f'        .{side}_{sig}({side}.{sig})' for side in ['up','down'] for sig in WIDTHS)+'\n    );\nendmodule\n'
build=ROOT/'build'/f'{module}-netlist-d{a.depth}';build.mkdir(parents=True,exist_ok=True)
(build/(module+'.sv')).write_text(s)
command=['verilator',str(ROOT/'tools/verilator_waivers.vlt'),'-sv','--timing','--assert','--Wall','-Wno-UNUSEDSIGNAL','-Wno-UNSIGNED','-Wno-SYNCASYNCNET',
    # Yosys emits noncanonical filenames and local helper signals; RTL lint remains strict.
    '-Wno-DECLFILENAME','--output-split','0','--binary','-j','4','--Mdir',str(build),'--top-module','tb_axi_outstanding',
    '+define+AXI_INTERNAL_CHECKS',f'-GDEPTH={a.depth}',f'-GPIPELINE={int(a.slice)}','tb/tb_axi_outstanding.sv','src/axi_if.sv','src/axi_protocol_checker.sv',
    'src/axi_interconnect.sv','src/axi_channel_fifo.sv','src/axi_request_queue.sv' if a.slice else 'src/axi_register_slice.sv','src/axi_target_arbiter.sv','src/axi_ram.sv','src/axi_sub.sv','tb/axi_stall_sub.sv',
    str(build/(module+'.sv')),f'synthesis/reports/netcheck-'+('slice' if a.slice else f'queue-d{a.depth}')+'-w64-a40-netlist.v']
subprocess.run(command,cwd=ROOT,check=True)
subprocess.run([str(build/'Vtb_axi_outstanding')],cwd=ROOT,check=True)
