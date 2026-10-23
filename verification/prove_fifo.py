#!/usr/bin/env python3
"""Inductive safety proof of FIFO order, occupancy and stalled output stability."""
from pathlib import Path
import hashlib
import json
import subprocess
ROOT=Path(__file__).resolve().parents[1]
report=ROOT/'verification/reports/formal-fifo';report.mkdir(parents=True,exist_ok=True)
# Add read-only observation ports to the actual source. No datapath/control text
# is replaced; these expose inductive invariants for the shift-register oracle.
source=(ROOT/'src/axi_channel_fifo.sv').read_text()
needle='    output logic [WIDTH-1:0] out_payload\n);'
assert source.count(needle)==1, 'Review instrumentation after RTL interface edit'
source=source.replace(needle,'''    output logic [WIDTH-1:0] out_payload,
    output wire [1:0] formal_count,
    output wire formal_head, formal_tail,
    output wire [WIDTH-1:0] formal_second
);
    assign formal_count=count;
    assign formal_head=head;
    assign formal_tail=tail;
    assign formal_second=payload[!head];''')
build=ROOT/'build/formal-fifo';build.mkdir(parents=True,exist_ok=True)
(build/'observed.sv').write_text(source)
script='''read_verilog -formal -sv -DSYNTHESIS build/formal-fifo/observed.sv verification/formal_fifo.sv
prep -top formal_fifo -flatten
async2sync
memory_map
opt
sat -seq 4 -tempinduct -maxsteps 20 -set-assumes -prove-asserts -verify
'''
(report/'proof.ys').write_text(script)
result=subprocess.run(['yosys','-Q','-T','-s',str(report/'proof.ys')],cwd=ROOT,capture_output=True,text=True)
(report/'proof.log').write_text('\n'.join(line.rstrip() for line in (result.stdout+result.stderr).splitlines()).rstrip()+'\n')
proved=result.returncode==0 and 'Induction step proven: SUCCESS!' in result.stdout
(report/'summary.json').write_text(json.dumps({'proved':proved,'exit_code':result.returncode,
    'yosys':subprocess.check_output(['yosys','-V'],text=True).strip(),
    'source_sha256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in ['src/axi_channel_fifo.sv','verification/formal_fifo.sv','verification/prove_fifo.py']},
    'scope':'WIDTH=8 FIFO safety under sampled-reset model, arbitrary input data/valid and output ready; not fabric equivalence or liveness'},indent=2)+'\n')
if not proved:
    print(result.stdout[-3000:]+result.stderr)
    raise SystemExit('FIFO inductive proof failed')
print('FIFO inductive safety proof PASS')
