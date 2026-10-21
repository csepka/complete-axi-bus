#!/usr/bin/env python3
"""RAM coarse synthesis with stock Yosys; optional whole-fabric synthesis with slang."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--slice',action='store_true',help='synthesize enabled target register slice')
p.add_argument('--pipeline',type=int,choices=[0,1],default=0)
p.add_argument('--queue',action='store_true',help='synthesize mechanically expanded queue ports with stock Yosys')
p.add_argument('--fabric',action='store_true',help='requires yosys-slang; fails explicitly if unavailable')
p.add_argument('--nm',type=int,default=2);p.add_argument('--ns',type=int,default=2)
p.add_argument('--addr-width',type=int,default=32)
p.add_argument('--width',type=int,default=64);p.add_argument('--depth',type=int,default=4)
p.add_argument('--label',default='current');a=p.parse_args()
if sum((a.fabric,a.queue,a.slice))>1:p.error('choose fabric, queue or slice')
if a.addr_width<16 or a.width<32 or a.width>1024 or a.width&(a.width-1) or any(v<=0 for v in (a.nm,a.ns,a.width,a.depth)) or not a.label.replace('-','').isalnum():p.error('invalid parameters')
reports=ROOT/'synthesis/reports'; reports.mkdir(exist_ok=True)
name=f'{a.label}-'+(f'fabric-{a.nm}x{a.ns}-d{a.depth}' if a.fabric else f'queue-d{a.depth}' if a.queue else 'slice' if a.slice else 'ram')+f'-w{a.width}'+(f'-a{a.addr_width}' if a.addr_width!=32 else '')
if a.fabric:
    native=subprocess.run(['yosys','-Q','-T','-p','help read_slang'],capture_output=True,text=True)
    plugin=[]
    if native.returncode or 'No such command' in native.stdout or 'read_slang' not in native.stdout:
        probe=subprocess.run(['yosys','-Q','-T','-m','slang','-p','help read_slang'],capture_output=True,text=True)
        if probe.returncode:
            (reports/(name+'-unavailable.txt')).write_text(native.stdout+probe.stderr)
            raise SystemExit('Full-fabric synthesis unavailable: install yosys-slang. RAM-only synthesis is not fabric evidence.')
        plugin=['-m','slang']
    subprocess.run(['python3','synthesis/scripts/make_flat_top.py'],cwd=ROOT,check=True)
    sources=' '.join(str(f.relative_to(ROOT)) for f in (ROOT/'src').glob('*.sv') if 'checker' not in f.name)
    command=f'read_slang -D SYNTHESIS --top axi_fabric_flat -G NM={a.nm} -G NS={a.ns} -G DATA_W={a.width} -G ADDR_W={a.addr_width} -G TARGET_PIPELINE={a.pipeline} -G MAX_OUTSTANDING={a.depth} {sources} build/axi_fabric_flat.sv; synth -flatten -top axi_fabric_flat -run begin:fine; check -assert; select -assert-none t:$dlatch t:$adlatch; select -assert-none p:*; stat'
elif a.slice:
    subprocess.run(['python3','synthesis/scripts/make_flat_slice.py'],cwd=ROOT,check=True)
    command=f'read_verilog -sv -DSYNTHESIS src/axi_channel_fifo.sv build/axi_register_slice_flat.sv; chparam -set ADDR_W {a.addr_width} -set DATA_W {a.width} -set ENABLE 1 axi_register_slice_flat; hierarchy -check -top axi_register_slice_flat; synth -flatten -top axi_register_slice_flat -run begin:fine; check -assert; select -assert-none t:$dlatch t:$adlatch; select -assert-none p:*; stat'
    plugin=[]
elif a.queue:
    subprocess.run(['python3','synthesis/scripts/make_flat_queue.py'],cwd=ROOT,check=True)
    command=f'read_verilog -sv -DSYNTHESIS build/axi_request_queue_flat.sv; chparam -set ADDR_W {a.addr_width} -set DATA_W {a.width} -set MAX_OUTSTANDING {a.depth} axi_request_queue_flat; hierarchy -check -top axi_request_queue_flat; synth -top axi_request_queue_flat -run begin:fine; check -assert; select -assert-none t:$dlatch t:$adlatch; select -assert-none p:*; stat'
    plugin=[]
else:
    command=f'read_verilog -sv -DSYNTHESIS src/axi_ram.sv; chparam -set ADDR_W {a.addr_width} -set DATA_W {a.width} axi_ram; hierarchy -check -top axi_ram; synth -top axi_ram -run begin:fine; check -assert; select -assert-none t:$dlatch t:$adlatch; select -assert-none p:*; stat'
    plugin=[]
command+=f'; write_json synthesis/reports/{name}-netlist.json; techmap; opt_clean; check -assert; write_verilog -noattr synthesis/reports/{name}-netlist.v'
(reports/(name+'.ys')).write_text(command+'\n')
result=subprocess.run(['yosys',*plugin,'-Q','-T','-p',command],cwd=ROOT,capture_output=True,text=True)
(reports/(name+'.log')).write_text(result.stdout+result.stderr)
summary={}
if result.returncode==0:
    netlist=json.loads((reports/(name+'-netlist.json')).read_text())
    cells=[c for m in netlist['modules'].values() for c in m.get('cells',{}).values()]
    def parameter(c,key):return int(c['parameters'][key],2)
    summary=dict(generic_cells=len(cells),register_bits=sum(len(c['connections'].get('Q',[])) for c in cells if 'dff' in c['type'].lower()),
        memory_bits=sum(parameter(c,'WIDTH')*parameter(c,'SIZE') for c in cells if c['type']=='$mem_v2'))
    if a.queue:
        expected_payload_bits=2*a.depth*(a.addr_width+3+4+8+3+2)
        assert summary['register_bits']+summary['memory_bits']>=expected_payload_bits, 'Synthesis lost queue storage'
(reports/(name+'.json')).write_text(json.dumps(dict(arguments=vars(a),command=command,summary=summary,
    yosys=subprocess.check_output(['yosys','-V'],text=True).strip(),exit_code=result.returncode),indent=2)+'\n')
if result.returncode:raise SystemExit(result.stderr)
print('\n'.join(result.stdout.splitlines()[-30:]))
