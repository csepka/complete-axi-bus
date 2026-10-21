#!/usr/bin/env python3
"""Reproduce retained tests, extended verification, and before/after measurements."""
import hashlib
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'synthesis/reports'
REPORTS.mkdir(parents=True,exist_ok=True)
commands=[('final-ci',['make','ci']),('extended',['make','extended']),
          ('netlist-depth3',['python3','synthesis/scripts/check_queue_netlist.py','--depth','3'])]
for label,extra in [('baseline',['--revision','2ec5059cf00b51b40ee441fab273f5a2d1d8f462']),
                    ('concurrent-d1',['--depth','1']),('queued-d4',['--depth','4']),('pipelined-d4',['--depth','4','--pipeline','1'])]:
    commands.append((label+'-bench',['python3','benchmarks/benchmark_runner.py','--label',label,*extra,
        '--config','2x2x64','--config','4x4x128','--config','8x8x256']))
for width in [32,64,128,256]:
    commands.append((f'ram-{width}',['python3','synthesis/scripts/run_synthesis.py','--label','corrected','--width',str(width)]))
for depth in [1,3,4]:
    commands.append((f'queue-{depth}',['python3','synthesis/scripts/run_synthesis.py','--queue','--label','queued','--width','64','--depth',str(depth)]))
for width in [64,256]:
    commands.append((f'slice-{width}',['python3','synthesis/scripts/run_synthesis.py','--slice','--width',str(width),'--label','pipeline']))
commands.append(('waveform',['make','waveform']))
results=[]
for name,cmd in commands:
    print('Running '+name,flush=True)
    log=REPORTS/(name+'.log')
    with log.open('w') as stream:
        result=subprocess.run(cmd,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    results.append(dict(name=name,command=cmd,exit_code=result.returncode,log=str(log.relative_to(ROOT))))
    if result.returncode:
        print(log.read_text()[-6000:]);raise SystemExit(f'{name} failed: {log}')
source_files=[*ROOT.glob('src/*.sv'),*ROOT.glob('tb/*.sv'),*ROOT.glob('benchmarks/*.py'),*ROOT.glob('synthesis/scripts/*.py'),ROOT/'Makefile',Path(__file__).resolve()]
(REPORTS/'validation.json').write_text(json.dumps(dict(
    git_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source_files)},
    results=results),indent=2)+'\n')
print('ALL UPGRADE VALIDATION COMMANDS PASSED',flush=True)
