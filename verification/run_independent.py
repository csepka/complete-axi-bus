#!/usr/bin/env python3
"""Independent cocotbext-axi tests on RTL or full-fabric generic netlists."""
import argparse
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET
from cocotb_tools.runner import get_runner
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'synthesis/scripts'))
from axi_ports import WIDTHS, MANAGER_OUTPUTS
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--nm',type=int,default=2);p.add_argument('--ns',type=int,default=2)
p.add_argument('--width',type=int,default=64);p.add_argument('--depth',type=int,default=4)
p.add_argument('--pipeline',type=int,choices=[0,1],default=1)
p.add_argument('--seed',type=int,default=23)
p.add_argument('--baseline',action='store_true',help='preserved globally serialized baseline netlist')
p.add_argument('--netlist',type=Path)
p.add_argument('--cells',type=Path,help='behavioral standard-cell models for a mapped netlist')
p.add_argument('--netlist-kind',choices=['generic','mapped','routed'],default='generic')
p.add_argument('--sim',choices=['verilator','icarus'],default='verilator')
a=p.parse_args()
if not (1<=a.nm<=8 and 1<=a.ns<=8 and 1<=a.depth<=8 and a.width in [32,64,128,256]):p.error('test memory partition supports 1..8 ports/depth and 32/64/128/256-bit data')
if a.sim=='icarus' and not a.netlist:p.error('Icarus requires a lowered full-fabric netlist')
if a.baseline and (not a.netlist or a.depth!=1 or a.pipeline!=0):p.error('baseline requires a netlist, depth 1 and pipeline 0')
label=('baseline-' if a.baseline else '')+f'{a.nm}x{a.ns}x{a.width}-d{a.depth}-p{a.pipeline}-{a.sim}-'+(a.netlist_kind if a.netlist else 'rtl')
build=ROOT/'build/independent'/label;build.mkdir(parents=True,exist_ok=True)
report=ROOT/'verification/reports'/f'{label}-seed{a.seed}'
report.mkdir(parents=True,exist_ok=True)
# A failed rebuild/test must not leave a previous passing manifest or coverage.
for name in ['manifest.json','coverage.json','results.xml','simulation.log']:
    (report/name).unlink(missing_ok=True)
runner_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
test_hash=hashlib.sha256((ROOT/'verification/test_independent.py').read_bytes()).hexdigest()
# Only structural signal splitting. The exact same DUT is used for both models.
ports=['input wire ACLK, ARESETn']
widths={k:eval(v,{},dict(ADDR_W=32,DATA_W=a.width,ID_W=4)) for k,v in WIDTHS.items()}
for side,count in [('m',a.nm),('s',a.ns)]:
    for i in range(count):
        for sig,w in widths.items():
            direction='input' if (sig in MANAGER_OUTPUTS)==(side=='m') else 'output'
            vector=f'[{int(w)-1}:0] ' if w>1 else ''
            ports.append(f'{direction} wire {vector}{side}{i}_{sig.lower()}')
params='' if a.netlist else f'#(.NM({a.nm}),.NS({a.ns}),.DATA_W({a.width}),.MAX_OUTSTANDING({a.depth}),.TARGET_PIPELINE({a.pipeline}))'
connections=['.ACLK(ACLK)','.ARESETn(ARESETn)']
for side,count in [('m',a.nm),('s',a.ns)]:
    for sig in widths:
        connections.append(f'.{side}_{sig}('+"{"+','.join(f'{side}{i}_{sig.lower()}' for i in reversed(range(count)))+"})")
top=build/'tb_independent.sv'
top.write_text('module tb_independent(\n'+',\n'.join(ports)+'\n);\naxi_fabric_flat '+params+' dut(\n'+',\n'.join(connections)+'\n);\nendmodule\n')
if a.netlist:
    sources=([a.cells.resolve()] if a.cells else [])+[a.netlist.resolve(),top]
else:
    subprocess.run([sys.executable,'synthesis/scripts/make_flat_top.py'],cwd=ROOT,check=True)
    sources=[ROOT/name for name in ['src/axi_if.sv','src/axi_channel_fifo.sv','src/axi_register_slice.sv','src/axi_request_queue.sv','src/axi_target_arbiter.sv','src/axi_interconnect.sv','build/axi_fabric_flat.sv']]+[top]
runner=get_runner(a.sim)
# Yosys packs independent bit-level chains into vectors; Verilator's vector-level
# UNOPTFLAT analysis then reports false cycles. The synthesis flow separately
# requires scc -expect 0. This waiver applies only to generated netlists.
netlist_flags=['-Wno-UNOPTFLAT'] if a.netlist else []
runner.build(sources=sources,hdl_toplevel='tb_independent',build_dir=build,
    build_args=['--assert','-Wno-UNUSEDSIGNAL','-Wno-UNSIGNED','-Wno-SYNCASYNCNET','-Wno-DECLFILENAME','-j','4']+netlist_flags if a.sim=='verilator' else ['-g2012'],
    timescale=('1ns','1ps'),log_file=build/'compile.log')
# Runner does not put test_module's source folder on PYTHONPATH automatically.
os.environ['PYTHONPATH']=str(ROOT/'verification')+os.pathsep+os.environ.get('PYTHONPATH','')
xml=runner.test(hdl_toplevel='tb_independent',test_module='test_independent',seed=a.seed,
    test_dir=build,results_xml=str(report/'results.xml'),log_file=report/'simulation.log',
    extra_env={'AXI_CONFIG':json.dumps(dict(nm=a.nm,ns=a.ns,width=a.width,depth=a.depth,pipeline=a.pipeline,seed=a.seed,baseline=a.baseline)),
               'AXI_COVERAGE':str(report/'coverage.json')})
results=ET.parse(xml)
assert results.findall('.//testcase'), 'No tests ran'
assert not results.findall('.//failure') and not results.findall('.//error'), 'Independent test failed; inspect simulation.log'
(report/'manifest.json').write_text(json.dumps({'configuration':vars(a)|{'netlist':str(a.netlist) if a.netlist else None,'cells':str(a.cells) if a.cells else None},
    'source_sha256':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources},
    'packages':{name:version(name) for name in ['cocotb','cocotbext-axi','cocotb-bus']},
    'runner_sha256':runner_hash,
    'test_sha256':test_hash},indent=2)+'\n')
print('Independent verification PASS: '+str(report.relative_to(ROOT)))
