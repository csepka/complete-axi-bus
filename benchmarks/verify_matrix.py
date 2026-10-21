#!/usr/bin/env python3
"""Additional seeded, asymmetric, width/address/depth verification cases."""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
cases=[('edge-1x1','1x1x32',1,32,13,0),('asym-3x2','3x2x64',3,40,42,2),
       ('asym-2x3','2x3x128',5,32,31,2),('stress-1','4x4x128',4,32,1,2),
       ('stress-23','4x4x128',4,32,23,1),('stress-97','4x4x128',4,32,97,2)]
for label,cfg,depth,addr,seed,distribution in cases:
    subprocess.run(['python3','benchmarks/benchmark_runner.py','--label',label,'--config',cfg,
        '--depth',str(depth),'--addr-width',str(addr),'--burst','8','--transactions','128',
        '--distribution',str(distribution),'--ready','47','--arrival','39','--seed',str(seed)],cwd=ROOT,check=True)

subprocess.run(['python3','benchmarks/benchmark_runner.py','--label','mixed75','--config','3x2x64',
    '--depth','3','--burst','8','--transactions','64','--read-percent','75','--distribution','2',
    '--ready','57','--arrival','63','--seed','42'],cwd=ROOT,check=True)

subprocess.run(['python3','benchmarks/benchmark_runner.py','--label','pipeline-stress','--config','3x2x64',
    '--depth','3','--pipeline','1','--burst','8','--transactions','128','--distribution','2',
    '--ready','37','--arrival','61','--seed','71'],cwd=ROOT,check=True)
