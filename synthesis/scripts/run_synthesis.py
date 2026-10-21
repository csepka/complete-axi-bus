#!/usr/bin/env python3
"""RAM coarse synthesis with stock Yosys; optional whole-fabric synthesis with slang."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--fabric',action='store_true',help='requires yosys-slang; fails explicitly if unavailable')
p.add_argument('--nm',type=int,default=2);p.add_argument('--ns',type=int,default=2)
p.add_argument('--width',type=int,default=64);p.add_argument('--depth',type=int,default=4)
p.add_argument('--label',default='current');a=p.parse_args()
if any(v<=0 for v in (a.nm,a.ns,a.width,a.depth)) or not a.label.replace('-','').isalnum():p.error('invalid parameters')
reports=ROOT/'synthesis/reports'; reports.mkdir(exist_ok=True)
name=f'{a.label}-'+(f'fabric-{a.nm}x{a.ns}-d{a.depth}' if a.fabric else 'ram')+f'-w{a.width}'
if a.fabric:
    probe=subprocess.run(['yosys','-Q','-T','-m','slang','-p','help read_slang'],capture_output=True,text=True)
    if probe.returncode:
        (reports/(name+'-unavailable.txt')).write_text(probe.stderr)
        raise SystemExit('Full-fabric synthesis unavailable: install yosys-slang. RAM-only synthesis is not fabric evidence.')
    subprocess.run(['python3','synthesis/scripts/make_flat_top.py'],cwd=ROOT,check=True)
    sources=' '.join(str(f.relative_to(ROOT)) for f in (ROOT/'src').glob('*.sv') if 'checker' not in f.name)
    command=f'read_slang -D SYNTHESIS --top axi_fabric_flat -G NM={a.nm} -G NS={a.ns} -G DATA_W={a.width} -G MAX_OUTSTANDING={a.depth} {sources} build/axi_fabric_flat.sv; synth -top axi_fabric_flat -run begin:coarse; stat'
    plugin=['-m','slang']
else:
    command=f'read_verilog -sv -DSYNTHESIS src/axi_ram.sv; chparam -set DATA_W {a.width} axi_ram; hierarchy -check -top axi_ram; synth -top axi_ram -run begin:coarse; stat'
    plugin=[]
(reports/(name+'.ys')).write_text(command+'\n')
result=subprocess.run(['yosys',*plugin,'-Q','-T','-p',command],cwd=ROOT,capture_output=True,text=True)
(reports/(name+'.log')).write_text(result.stdout+result.stderr)
(reports/(name+'.json')).write_text(json.dumps(dict(arguments=vars(a),command=command,
    yosys=subprocess.check_output(['yosys','-V'],text=True).strip(),exit_code=result.returncode),indent=2)+'\n')
if result.returncode:raise SystemExit(result.stderr)
print('\n'.join(result.stdout.splitlines()[-30:]))
