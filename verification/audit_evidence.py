#!/usr/bin/env python3
"""Check evidence provenance; optionally require complete physical acceptance.

Default success means evidence is internally consistent, NOT that physical
signoff passed. Physical status is always reported independently.
"""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--require-physical', action='store_true')
a = p.parse_args()
# An interrupted or failed audit must not leave a stale successful release record.
audit_report = ROOT/'verification/reports/evidence.json'
audit_report.unlink(missing_ok=True)

def read(path):
    return json.loads((ROOT/path).read_text())

def digest(path):
    return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()

def hashes(entries):
    for name, expected in entries.items():
        assert digest(name) == expected, f'Stale evidence: {name}'

old = read('synthesis/reports/validation.json')
hashes(old['source_sha256'])
assert len(old['results']) == 17 and all(x['exit_code'] == 0 for x in old['results'])
cells = read('verification/reports/cell-models/summary.json')
hashes(cells['source_sha256'])
assert cells['passed'] and cells['exit_code'] == 0
formal = read('verification/reports/formal-fifo/summary.json')
hashes(formal['source_sha256'])
assert formal['proved'] and formal['exit_code'] == 0
for depth in [1,3,4,5]:
    queue = read(f'verification/reports/formal-request-queue-d{depth}/summary.json')
    hashes(queue['source_sha256'])
    assert queue['proved'] and queue['exit_code'] == 0 and queue['depth'] == depth
mutations = read('verification/diagnostics/request-queue-mutants/summary.json')
hashes(mutations['source_sha256'])
assert mutations['passed'] and all(x['detected'] for x in mutations['results'])
for mutation in mutations['results']:
    assert digest(f"verification/diagnostics/request-queue-mutants/{mutation['mutation']}.vcd") == mutation['counterexample_sha256']
required = {
    '1x1x32-d1-p0-verilator-rtl-seed1',
    '2x2x64-d4-p0-verilator-rtl-seed97',
    '2x2x64-d4-p1-verilator-rtl-seed23',
    '3x2x128-d3-p1-verilator-rtl-seed71',
    '4x4x256-d4-p1-verilator-rtl-seed71',
    '2x2x64-d4-p1-icarus-generic-seed23',
    '2x2x64-d4-p1-icarus-mapped-seed23',
    '2x2x64-d4-p1-icarus-routed-seed23',
    '2x2x64-d4-p1-icarus-routed-seed71',
    'baseline-2x2x64-d1-p0-icarus-routed-seed23',
    '8x8x256-d4-p1-verilator-generic-seed23',
    '8x8x256-d4-p1-icarus-mapped-seed23',
    '8x8x256-d4-p1-icarus-routed-seed23',
    '8x8x256-d4-p1-icarus-routed-seed71',
}
observed = []
for folder in sorted((ROOT/'verification/reports').iterdir()):
    if not folder.is_dir() or folder.name.startswith('formal-') or folder.name == 'cell-models':
        continue
    assert (folder/'manifest.json').exists(), f'Incomplete independent test: {folder.name}'
    manifest = json.loads((folder/'manifest.json').read_text())
    hashes(manifest['source_sha256'])
    assert manifest['test_sha256'] == digest('verification/test_independent.py')
    assert manifest['runner_sha256'] == digest('verification/run_independent.py')
    xml = ET.parse(folder/'results.xml')
    assert xml.findall('.//testcase') and not xml.findall('.//failure') and not xml.findall('.//error')
    coverage = json.loads((folder/'coverage.json').read_text())
    assert coverage['bins']['random_batches'] == 8
    for channel in ['aw', 'w', 'b', 'ar', 'r']:
        assert coverage['bins']['stall_'+channel] > 0
    observed.append(folder.name)
assert required <= set(observed), f'Missing required tests: {required-set(observed)}'
physical = {}
for folder in sorted((ROOT/'synthesis/physical/reports').iterdir()):
    if not folder.is_dir() or not (folder/'summary.json').exists():
        continue
    summary = json.loads((folder/'summary.json').read_text())
    hashes(summary['source_sha256'])
    work = Path('build/physical')/folder.name
    hashes({str(work/name):value for name,value in summary['flow_inputs_sha256'].items()})
    results = work/'orfs/results/nangate45'/folder.name/'base'
    hashes({str(results/name):value for name,value in summary['artifact_sha256'].items()})
    physical[folder.name] = {key:summary[key] for key in
        ['timing_and_router_clean', 'klayout_drc', 'lvs', 'physical_acceptance']}
assert {'2x2x64-d4-p1','baseline-2x2x64-d1-p0'} <= set(physical)
complete = bool(physical) and all(x['physical_acceptance'] and x['timing_and_router_clean'] for x in physical.values())
report = {
    'evidence_consistent': True, 'original_regression_stages_passed': 17,
    'fifo_induction_passed': True, 'request_queue_induction_depths': [1,3,4,5],
    'queue_mutations_detected': len(mutations['results']),
    'cell_model_checks_passed': True, 'independent_tests_passed': observed,
    'physical_results': physical, 'physical_acceptance_complete': complete,
    'source_sha256': {str(f.relative_to(ROOT)):digest(f) for directory in
        ['verification','synthesis/physical'] for f in sorted((ROOT/directory).glob('*'))
        if f.is_file() and f.suffix in ['.py','.sv','.json','.txt']},
}
audit_report.write_text(json.dumps(report, indent=2)+'\n')
print(f'Evidence consistent: 17 original stages, FIFO/queue induction, cell models, mutation checks, {len(observed)} independent test runs.')
print('Physical acceptance: '+('complete' if complete else 'INCOMPLETE (see evidence.json; no signoff claim)'))
if a.require_physical and not complete:
    raise SystemExit(1)
