#!/usr/bin/env python3
"""Ensure queue safety assertions reject payload corruption and early release.

Mutate generated test copies only. Production RTL and passing proof evidence are
not altered. A reachable bounded counterexample is required for each mutation;
an induction timeout or parser/tool failure does not count as detection.
"""
import hashlib
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
build=ROOT/'build/formal-request-queue/3'
source=(build/'observed.sv').read_text()
base=(ROOT/'verification/reports/formal-request-queue-d3/proof.ys').read_text()
mutations={
    'overwrite-head':('if(wpush) wq[wt]<=','if(wpush) wq[wh]<='),
    'early-release':('wire wpop=up_BVALID && up_BREADY;',
                     'wire wpop=down_WVALID && down_WREADY && down_WLAST;'),
}
report=ROOT/'verification/diagnostics/request-queue-mutants';report.mkdir(parents=True,exist_ok=True)
(report/'summary.json').unlink(missing_ok=True)
results=[]
for name,(old,new) in mutations.items():
    (report/f'{name}.vcd').unlink(missing_ok=True)
    assert source.count(old)==1, f'Review mutation {name}'
    target=build/f'{name}.sv';target.write_text(source.replace(old,new))
    script=base.replace('build/formal-request-queue/3/observed.sv',str(target.relative_to(ROOT)))
    script=script.replace('sat -seq 4 -tempinduct -maxsteps 20', 'sat -seq 8')
    # -verify exits before printing the model on this Yosys version. Require
    # an explicit SAT counterexample from a successful solver invocation.
    script=script.replace(' -verify', f' -dump_vcd verification/diagnostics/request-queue-mutants/{name}.vcd')
    ys=report/f'{name}.ys';ys.write_text(script)
    result=subprocess.run(['yosys','-Q','-T','-s',str(ys)],cwd=ROOT,capture_output=True,text=True)
    log=result.stdout+result.stderr
    (report/f'{name}.log').write_text('\n'.join(line.rstrip() for line in log.splitlines()).rstrip()+'\n')
    detected=result.returncode==0 and 'model found: FAIL!' in log and (report/f'{name}.vcd').exists()
    results.append(dict(mutation=name,detected=detected,exit_code=result.returncode,
        counterexample_sha256=hashlib.sha256((report/f'{name}.vcd').read_bytes()).hexdigest() if detected else None))
    print(f'{name}: '+('reachable counterexample detected' if detected else 'NOT verified'))
sources=['src/axi_request_queue.sv','synthesis/scripts/axi_ports.py','verification/formal_request_queue.sv','verification/prove_request_queue.py','verification/check_queue_mutations.py']
passed=all(x['detected'] for x in results)
(report/'summary.json').write_text(json.dumps(dict(passed=passed,results=results,
    source_sha256={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in sources}),indent=2)+'\n')
if not passed:raise SystemExit('Mutation verification failed')
