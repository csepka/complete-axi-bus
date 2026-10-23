#!/usr/bin/env python3
"""Reproduce independent BFM tests and the FIFO safety proof (local tools only)."""
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
commands=[['verification/prove_fifo.py']]
for options in [[],['--pipeline','0','--seed','97'],
                ['--nm','3','--ns','2','--width','128','--depth','3','--seed','71'],
                ['--nm','1','--ns','1','--width','32','--depth','1','--pipeline','0','--seed','1']]:
    commands.append(['verification/run_independent.py',*options])
for command in commands:
    subprocess.run([sys.executable,*command],cwd=ROOT,check=True)
print('Independent RTL matrix and FIFO proof PASS')
