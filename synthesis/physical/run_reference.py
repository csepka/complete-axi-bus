#!/usr/bin/env python3
"""Full-interface synthesis and Nangate45 reference implementation in pinned ORFS.

Run on the host. Docker Desktop must be running. The container has no network,
only this repository is mounted. Nangate45 is an educational reference, not a
foundry signoff platform. Outputs live under build/physical/<configuration>.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'synthesis/scripts'))
from axi_ports import WIDTHS, MANAGER_OUTPUTS
IMAGE = json.loads((ROOT/'synthesis/physical/toolchain.json').read_text())['image']
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', action='store_true', help='synthesize preserved v1.0.0 fabric; requires depth=1 and pipeline=0')
p.add_argument('--nm', type=int, default=2)
p.add_argument('--ns', type=int, default=2)
p.add_argument('--width', type=int, default=64)
p.add_argument('--depth', type=int, default=4)
p.add_argument('--pipeline', type=int, choices=[0, 1], default=1)
p.add_argument('--period', type=float, default=10.0)
p.add_argument('--hold-margin', type=float, default=0.03, help='positive hold repair margin in ns')
p.add_argument('--cap-margin', type=float, default=0.0, help='capacitance repair margin in percent')
p.add_argument('--max-repair-passes', type=int, help='explicit resizer pass budget; requires a distinct --variant')
p.add_argument('--closure-rounds', type=int, default=0, help='extra electrical/hold repair rounds after global routing; requires a distinct --variant')
p.add_argument('--variant', default='', help='separate physical trial label; lowercase letters, digits, hyphens')
p.add_argument('--resume', action='store_true', help='reuse generic synthesis only if source hashes/configuration match')
p.add_argument('--stage', choices=['generic', 'synth', 'finish', 'checks'], default='finish')
a = p.parse_args()
if min(a.nm, a.ns, a.depth) < 1 or a.width < 32 or a.width & (a.width-1) or a.period <= 0:
    p.error('positive counts/period and power-of-two data width >=32 required')
if a.hold_margin<0 or not 0<=a.cap_margin<100 or (a.variant and not re.fullmatch('[a-z0-9-]+',a.variant)):
    p.error('nonnegative hold margin, cap margin in [0,100), and safe variant required')
if a.max_repair_passes is not None and (a.max_repair_passes<1 or not a.variant):
    p.error('--max-repair-passes requires a positive count and a distinct --variant')
if a.closure_rounds<0 or (a.closure_rounds and not a.variant):
    p.error('--closure-rounds requires a nonnegative count and a distinct --variant')
if a.baseline and (a.depth!=1 or a.pipeline!=0):p.error('baseline requires --depth 1 --pipeline 0')
label = ('baseline-' if a.baseline else '')+f'{a.nm}x{a.ns}x{a.width}-d{a.depth}-p{a.pipeline}'
if a.variant:label+='-'+a.variant
out = ROOT/'build/physical'/label
out.mkdir(parents=True, exist_ok=True)
inside = '/work/'+str(out.relative_to(ROOT))
previous = json.loads((out/'manifest.json').read_text()) if (out/'manifest.json').exists() else None
# Reject a different experiment before touching its constraints or checkpoints.
# Older manifests predate these optional controls; preserve their actual defaults.
if previous:
    defaults={'hold_margin':0.03,'cap_margin':0.0,'max_repair_passes':None,'closure_rounds':0}
    for key in ['nm','ns','width','depth','pipeline','baseline','period',*defaults]:
        if previous['configuration'].get(key,defaults.get(key)) != getattr(a,key):
            p.error(f'{label}: {key} differs from saved trial; choose a new --variant')
def put(path, text):
    if not path.exists() or path.read_text()!=text:path.write_text(text)
subprocess.run(['python3', 'synthesis/scripts/make_flat_top.py'], cwd=ROOT, check=True)
rtl = ['src/axi_if.sv', 'src/axi_channel_fifo.sv', 'src/axi_register_slice.sv',
       'src/axi_request_queue.sv', 'src/axi_target_arbiter.sv', 'src/axi_interconnect.sv',
       'build/axi_fabric_flat.sv']
if a.baseline:
    revision='2ec5059cf00b51b40ee441fab273f5a2d1d8f462'
    for name in ['axi_if.sv','axi_interconnect.sv']:
        put(out/name,subprocess.check_output(['git','show',f'{revision}:src/{name}'],cwd=ROOT,text=True))
    wrapper=(ROOT/'build/axi_fabric_flat.sv').read_text().replace('.MAX_OUTSTANDING(MAX_OUTSTANDING),.TARGET_PIPELINE(TARGET_PIPELINE),','')
    put(out/'axi_fabric_flat.sv',wrapper)
    rtl=[str((out/name).relative_to(ROOT)) for name in ['axi_if.sv','axi_interconnect.sv','axi_fabric_flat.sv']]
ys = f'''read_slang --top axi_fabric_flat -G NM={a.nm} -G NS={a.ns} -G DATA_W={a.width} -G MAX_OUTSTANDING={a.depth} -G TARGET_PIPELINE={a.pipeline} {' '.join(rtl)}
hierarchy -check -top axi_fabric_flat
synth -flatten -top axi_fabric_flat -noabc
check -assert
scc -expect 0
select -assert-none t:$dlatch t:$adlatch t:$_DLATCH_* p:*
stat
write_json {inside}/generic.json
write_verilog -noattr {inside}/generic.v
'''
put(out/'generic.ys', ys)
# Explicit interface assumptions: synchronous external endpoints, bounded I/O
# delays, 5-fF output load, 100-ps input slew, reset externally synchronized.
input_patterns = ' '.join(f'{side}_{sig}*' for side in ['m','s'] for sig in WIDTHS if (sig in MANAGER_OUTPUTS)==(side=='m'))
sdc = f'''create_clock -name ACLK -period {a.period} [get_ports ACLK]
set_clock_uncertainty 0.20 [get_clocks ACLK]
set_clock_transition 0.10 [get_clocks ACLK]
set data_inputs [get_ports {{{input_patterns}}}]
set_input_delay -clock ACLK -max 1.0 $data_inputs
set_input_delay -clock ACLK -min 0.2 $data_inputs
set_input_transition 0.10 $data_inputs
set_output_delay -clock ACLK -max 1.0 [all_outputs]
set_output_delay -clock ACLK -min 0.2 [all_outputs]
# Nangate45 declares capacitance in fF, not pF.
set_load 5.0 [all_outputs]
# Integration contract: asynchronous assertion, synchronized deassertion outside
# this block. Recovery/removal of this external reset is NOT signed off here.
set_false_path -from [get_ports ARESETn]
'''
put(out/'constraints.sdc', sdc)
repair_budget = '''# Preserve timing constraints; permit hold buffering beyond ORFS's default cap.
rename repair_timing_helper repair_timing_helper_original
proc repair_timing_helper { args } {
    # A cap exception leaves the inserted buffers in the design. A second
    # bounded repair pass can finish using the enlarged design as its budget.
    for {set attempt 0} {$attempt < 3} {incr attempt} {
        if {![catch {repair_timing_helper_original -max_buffer_percent 100 {*}$args} msg opts]} { return }
        if {![string match {*RSZ-0060*} $msg] || $attempt == 2} { return -options $opts $msg }
        puts "Retry hold repair after buffer cap; constraints unchanged"
    }
}
'''
if a.max_repair_passes is not None:
    repair_budget=repair_budget.replace('-max_buffer_percent 100 {*}$args',
        f'-max_buffer_percent 100 -max_passes {a.max_repair_passes} {{*}}$args')
put(out/'repair_budget.tcl', repair_budget)
# Explicit die size accommodates wide parallel external buses; cell area is
# reported separately and must not be confused with the deliberately roomy die.
die = max(250, 125*max(a.nm, a.ns))
put(out/'config.mk', f'''export DESIGN_NAME = axi_fabric_flat
export DESIGN_NICKNAME = {label}
export PLATFORM = nangate45
export VERILOG_FILES = {inside}/generic.v
export SDC_FILE = {inside}/constraints.sdc
export DIE_AREA = 0 0 {die} {die}
export CORE_AREA = 10 10 {die-10} {die-10}
export PLACE_DENSITY = 0.30
export TNS_END_PERCENT = 100
export HOLD_SLACK_MARGIN = {a.hold_margin}
export CAP_MARGIN = {a.cap_margin}
export PLACE_PINS_ARGS = -min_distance 1 -min_distance_in_tracks
export NUM_CORES = 4
export SYNTH_REPEATABLE_BUILD = 1
export PRE_CTS_TCL = {inside}/repair_budget.tcl
export PRE_GLOBAL_ROUTE_TCL = {inside}/repair_budget.tcl
''' + (f'export POST_GLOBAL_ROUTE_TCL = {inside}/closure.tcl\n' if a.closure_rounds else ''))
if a.closure_rounds:
    put(out/'closure.tcl', f'set closure_rounds {a.closure_rounds}\n'+'''# Re-estimate routed parasitics after legalization before the next repair.
# No clock, load, uncertainty, DRC or endpoint constraint is relaxed.
for {set round 1} {$round <= $closure_rounds} {incr round} {
    foreach kind {electrical hold} {
        puts "Closure round $round: $kind"
        log_cmd global_route -start_incremental
        if {$kind eq "electrical"} {
            repair_design_helper
        } else {
            repair_timing_helper -hold
        }
        detailed_placement_helper -quiet
        log_cmd check_placement -verbose
        log_cmd global_route -end_incremental -congestion_report_file $::env(REPORTS_DIR)/closure_${round}_${kind}.rpt
        log_cmd estimate_parasitics -global_routing
    }
    report_metrics 5 "global route closure round $round"
}
# POST_GLOBAL_ROUTE runs after the stock metrics and guide output. Refresh both
# so reports/guides describe the actual saved checkpoint, not the pre-hook state.
report_metrics 5 "global route after closure"
write_guides $::env(RESULTS_DIR)/route.guide
source [file join $::env(SCRIPTS_DIR) "write_ref_sdc.tcl"]
''')
meta = dict(image=IMAGE, configuration=vars(a), source_sha256={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in rtl}, commands=[])
def run(command, logfile):
    docker = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
              '-v', f'{ROOT}:/work', '-w', '/work', IMAGE, 'bash', '-lc',
              'set -e; source /OpenROAD-flow-scripts/env.sh; cd /work; '+command]
    print('Running '+logfile, flush=True)
    # Persist before launching: an interrupted host/container must not erase the
    # fact that a check was attempted or leave a previous successful exit code.
    record = dict(command=docker, exit_code=None, status='running', log=logfile)
    meta['commands'].append(record)
    (out/'manifest.json').write_text(json.dumps(meta, indent=2)+'\n')
    try:
        with (out/logfile).open('w') as log:
            result = subprocess.run(docker, stdout=log, stderr=subprocess.STDOUT)
    except BaseException as error:
        record.update(status='interrupted', error=type(error).__name__)
        (out/'manifest.json').write_text(json.dumps(meta, indent=2)+'\n')
        raise
    record.update(exit_code=result.returncode, status='completed')
    (out/'manifest.json').write_text(json.dumps(meta, indent=2)+'\n')
    if result.returncode:
        print((out/logfile).read_text()[-6000:])
        raise SystemExit(result.returncode)
if a.resume:
    assert previous and previous['source_sha256']==meta['source_sha256'], 'Resume sources changed'
    assert all(previous['configuration'].get(k,False)==getattr(a,k) for k in ['nm','ns','width','depth','pipeline','baseline']), 'Resume configuration changed'
    assert (out/'generic.json').exists() and (out/'generic.v').exists()
    meta['reused_generic_from']=previous['reused_generic_from'] if 'reused_generic_from' in previous else previous['commands'][0]
else:
    run('yosys -V; openroad -version; yosys -Q -T -s '+inside+'/generic.ys', 'generic.log')
net = json.loads((out/'generic.json').read_text())['modules']['axi_fabric_flat']
meta['generic_cells'] = len(net['cells'])
meta['generic_cell_types'] = {}
for cell in net['cells'].values():
    typ = cell['type']
    meta['generic_cell_types'][typ] = meta['generic_cell_types'].get(typ, 0)+1
assert len(net['ports']) == 64, 'Unexpected external interface; review wrapper'
assert all(not m.get('attributes', {}).get('blackbox') for m in json.loads((out/'generic.json').read_text())['modules'].values()), 'Blackbox found'
(out/'manifest.json').write_text(json.dumps(meta, indent=2)+'\n')
if a.stage != 'generic':
    target='finish drc' if a.stage=='checks' else a.stage
    run(f'make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG={inside}/config.mk WORK_HOME={inside}/orfs {target}', 'flow.log')
    if a.stage=='checks':
        # Missing platform collateral is an explicit failure, never a waived pass.
        run(f'test -f /OpenROAD-flow-scripts/flow/platforms/nangate45/lvs/FreePDK45.lylvs || {{ echo "LVS unavailable: pinned platform has no FreePDK45.lylvs"; exit 2; }}; make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG={inside}/config.mk WORK_HOME={inside}/orfs lvs', 'lvs.log')
print('Completed '+label+' stage '+a.stage, flush=True)
