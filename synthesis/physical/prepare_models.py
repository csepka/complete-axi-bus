#!/usr/bin/env python3
"""Build zero-delay functional models from the exact reference Liberty library."""
from refine_mux_models import refine
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
config=json.loads((ROOT/'synthesis/physical/toolchain.json').read_text())
output=ROOT/'build/physical';output.mkdir(parents=True,exist_ok=True)
cmd=['docker','run','--rm','--platform',config['platform'],'--network','none',
     '-v',f'{ROOT}:/work',config['image'],'bash','-lc',
     'set -e; source env.sh; yosys -Q -T -p "read_liberty -ignore_miss_func flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib; write_verilog -noattr /work/build/physical/nangate45_models_raw.v"; sha256sum flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib flow/platforms/nangate45/lef/*.lef']
with (output/'models.log').open('w') as log:
    result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
if result.returncode:raise SystemExit(result.returncode)
(output/'nangate45_models.v').write_text(refine((output/'nangate45_models_raw.v').read_text()))
print('Prepared zero-delay standard-cell models; timing is checked separately by STA')
