#!/usr/bin/env python3
"""Inductively prove actual request-queue order/accounting at selected depths."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'synthesis/scripts'))
from axi_ports import expand_interfaces, WIDTHS, MANAGER_OUTPUTS
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--depth',type=int,choices=[1,3,4,5],default=4)
a=p.parse_args()
build=ROOT/'build/formal-request-queue'/str(a.depth);build.mkdir(parents=True,exist_ok=True)
report=ROOT/'verification/reports'/f'formal-request-queue-d{a.depth}';report.mkdir(parents=True,exist_ok=True)
(report/'summary.json').unlink(missing_ok=True)
source=expand_interfaces((ROOT/'src/axi_request_queue.sv').read_text(),'axi_request_queue','axi_request_queue_flat')
# Read-only observation ports expose ring storage for inductive invariants. All
# original datapath and control statements are retained exactly by expansion.
needle='    input logic down_RLAST\n);'
assert source.count(needle)==1
extra='''    input logic down_RLAST,
    output wire [$clog2(MAX_OUTSTANDING+1)-1:0] formal_wc,formal_rc,
    output wire [(MAX_OUTSTANDING>1?$clog2(MAX_OUTSTANDING):1)-1:0] formal_wh,formal_wt,formal_rh,formal_rt,
    output wire formal_w_sent,formal_r_sent,formal_w_done,
    output wire [8:0] formal_wleft,
    output wire [MAX_OUTSTANDING*(ADDR_W+3+ID_W+8+3+2)-1:0] formal_wq,formal_rq
);
    assign formal_wc=wc,formal_rc=rc;
    assign formal_wh=wh,formal_wt=wt,formal_rh=rh,formal_rt=rt;
    assign formal_w_sent=w_sent,formal_r_sent=r_sent,formal_w_done=w_done;
    assign formal_wleft=wleft;
    for(genvar k=0;k<MAX_OUTSTANDING;k=k+1) begin
        assign formal_wq[k*REQUEST_W+:REQUEST_W]=wq[k];
        assign formal_rq[k*REQUEST_W+:REQUEST_W]=rq[k];
    end
'''
(build/'observed.sv').write_text(source.replace(needle,extra))
ports=['input wire ACLK, ARESETn']
for side in ['up','down']:
    for signal,width in WIDTHS.items():
        direction='input' if (signal in MANAGER_OUTPUTS)==(side=='up') else 'output'
        vector='' if width=='1' else f'[{width}-1:0] '
        ports.append(f'{direction} wire {vector}{side}_{signal}')
(build/'ports.vh').write_text(',\n'.join(ports)+'\n')
folder=str(build.relative_to(ROOT))
script=f'''read_verilog -formal -sv -DSYNTHESIS -I{folder} {folder}/observed.sv verification/formal_request_queue.sv
chparam -set DEPTH {a.depth} formal_request_queue
prep -top formal_request_queue -flatten
async2sync
memory_map
opt
sat -seq 4 -tempinduct -maxsteps 20 -set-assumes -prove-asserts -verify
'''
(report/'proof.ys').write_text(script)
with (report/'proof.log').open('w') as log:
    result=subprocess.run(['yosys','-Q','-T','-s',str(report/'proof.ys')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
log=(report/'proof.log').read_text()
(report/'proof.log').write_text('\n'.join(line.rstrip() for line in log.splitlines()).rstrip()+'\n')
proved=result.returncode==0 and 'Induction step proven: SUCCESS!' in log
sources=['src/axi_request_queue.sv','synthesis/scripts/axi_ports.py','verification/formal_request_queue.sv','verification/prove_request_queue.py']
(report/'summary.json').write_text(json.dumps(dict(proved=proved,exit_code=result.returncode,depth=a.depth,
    yosys=subprocess.check_output(['yosys','-V'],text=True).strip(),
    source_sha256={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in sources},
    scope='ADDR_W=32 DATA_W=32 ID_W=4; sampled reset; arbitrary inputs; address order, retention, ownership and accounting safety; not full fabric, response legality or liveness'),indent=2)+'\n')
if not proved:
    print(log[-5000:]);raise SystemExit('Request queue proof failed')
print(f'Request queue depth {a.depth} inductive safety proof PASS')
