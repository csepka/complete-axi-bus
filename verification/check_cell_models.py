#!/usr/bin/env python3
"""Check refined MUX models against exhaustive binary-completion semantics."""
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
build=ROOT/'build/cell-models';build.mkdir(parents=True,exist_ok=True)
report=ROOT/'verification/reports/cell-models';report.mkdir(parents=True,exist_ok=True)
# Fail closed even if model extraction or compilation fails before simulation.
for name in ['summary.json','test.log']:
    (report/name).unlink(missing_ok=True)
raw=ROOT/'build/physical/nangate45_models_raw.v'
models=ROOT/'build/physical/nangate45_models.v'
text=raw.read_text();blocks=[]
for name in ['MUX2_X1','MUX2_X2']:
    found=re.findall(rf'module {name}\(.*?endmodule',text,re.S)
    assert len(found)==1
    blocks.append(found[0].replace('module '+name+'(', 'module '+name+'_RAW(',1))
(build/'raw_mux.v').write_text('\n'.join(blocks)+'\n')
subprocess.run(['iverilog','-g2012','-s','test_cell_models','-o',str(build/'sim.vvp'),
                str(models),str(build/'raw_mux.v'),'verification/test_cell_models.sv'],cwd=ROOT,check=True)
result=subprocess.run(['vvp',str(build/'sim.vvp')],cwd=ROOT,capture_output=True,text=True)
(report/'test.log').write_text(result.stdout+result.stderr)
passed=result.returncode==0 and 'PASS: 128' in result.stdout
(report/'summary.json').write_text(json.dumps({'passed':passed,'exit_code':result.returncode,
    'four_state_cases':128,'binary_equivalence_cases':16,
    'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in
        [raw,models,ROOT/'verification/test_cell_models.sv',Path(__file__).resolve(),ROOT/'synthesis/physical/refine_mux_models.py']},
    'scope':'zero-delay MUX truth tables only; Z input treated as unknown; no timing claims'},indent=2)+'\n')
print(result.stdout,end='')
if not passed:raise SystemExit('Cell model check failed')
