#!/usr/bin/env python3
"""Archive reference implementation evidence; fail on timing or route violations."""
from collections import Counter
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('label')
a=p.parse_args()
if not a.label.replace('-','').isalnum():p.error('invalid label')
work=ROOT/'build/physical'/a.label
manifest=json.loads((work/'manifest.json').read_text())
assert manifest['commands'], 'No flow commands recorded'
logs=work/'orfs/logs/nangate45'/a.label/'base'
rpts=work/'orfs/reports/nangate45'/a.label/'base'
results=work/'orfs/results/nangate45'/a.label/'base'
final=json.loads((logs/'6_report.json').read_text())
route=json.loads((logs/'5_2_route.json').read_text())
# ORFS emits repeated metric keys while updating statistics. Use the final
# specific stdcell field, which excludes filler area, rather than total die area.
summary={'configuration':manifest['configuration'],'image':manifest['image'],
         'library':'NangateOpenCellLibrary_typical.lib','voltage_V':1.1,'temperature_C':25,
         'stdcell_area_um2':final['finish__design__instance__area__stdcell'],
         'die_area_um2':final['finish__design__die__area'],
         'setup_worst_slack_ns':final['finish__timing__setup__ws'],
         'hold_worst_slack_ns':final['finish__timing__hold__ws'],
         'setup_violations':final['finish__timing__drv__setup_violation_count'],
         'hold_violations':final['finish__timing__drv__hold_violation_count'],
         'route_drc_errors':route['detailedroute__route__drc_errors'],
         'max_cap_violations':final['finish__timing__drv__max_cap'],
         'max_slew_violations':final['finish__timing__drv__max_slew'],
         'max_fanout_violations':final['finish__timing__drv__max_fanout'],
         'source_sha256':manifest['source_sha256'],
         'limitations':['Reference library, one typical corner; not foundry signoff',
                        'External reset recovery/removal excluded; synchronous deassertion required',
                        'Fabric macro only: no RAMs, package, pads, or endpoint implementation',
                        'Reported clock is constrained period, not independently optimized Fmax']}
summary['command_failures']=[c for c in manifest['commands'] if c['exit_code']!=0]
drc=rpts/'6_drc.lyrdb'
summary['klayout_drc']={'status':'not_run'}
if not drc.exists() and any(' drc' in ' '.join(c['command']) for c in summary['command_failures']):
    summary['klayout_drc']={'status':'incomplete','reason':'DRC command failed before producing a complete report'}
if drc.exists():
    try:
        items=ET.parse(drc).findall('.//items/item')
        summary['klayout_drc']={'status':'pass' if not items else 'fail',
            'marker_count':len(items),'categories':dict(Counter(item.findtext('category') for item in items)),
            'note':'Count XML items, not value elements; each antenna marker has multiple values.'}
    except ET.ParseError as error:
        summary['klayout_drc']={'status':'incomplete','reason':str(error)}
# Do not infer LVS success from routing, netlist simulation or GDS generation.
summary['lvs']={'status':'unavailable','reason':'Pinned Nangate45 platform names but does not supply FreePDK45.lylvs'}
summary['physical_acceptance']=(not summary['command_failures'] and summary['klayout_drc']['status']=='pass' and summary['lvs']['status']=='pass')
summary['artifact_sha256']={}
for name in ['6_final.v','6_final.sdc','6_final.gds','6_final.def','6_final.spef']:
    path=results/name
    assert path.exists() and path.stat().st_size>0, f'Missing {name}'
    summary['artifact_sha256'][name]=hashlib.sha256(path.read_bytes()).hexdigest()
summary['flow_inputs_sha256']={name:hashlib.sha256((work/name).read_bytes()).hexdigest() for name in ['generic.ys','constraints.sdc','config.mk','repair_budget.tcl']}
summary['timing_and_router_clean']=(summary['setup_worst_slack_ns']>=0 and summary['hold_worst_slack_ns']>=0 and summary['setup_violations']==0 and summary['hold_violations']==0 and summary['route_drc_errors']==0 and all(summary[key]==0 for key in ['max_cap_violations','max_slew_violations','max_fanout_violations']))
archive=ROOT/'synthesis/physical/reports'/a.label
archive.mkdir(parents=True,exist_ok=True)
for name in ['manifest.json','generic.ys','constraints.sdc','config.mk','repair_budget.tcl','generic.log']:
    shutil.copy2(work/name,archive/name)
for name in ['flow.log','lvs.log']:
    if (work/name).exists():shutil.copy2(work/name,archive/name)
for name in ['1_2_yosys.log','6_report.json','6_report.log','5_2_route.json','6_final_lec.log']:
    if (logs/name).exists():shutil.copy2(logs/name,archive/name)
for name in ['synth_stat.txt','synth_check.txt','6_finish.rpt','5_route_drc.rpt','drt_antennas.log','final_all.webp','final_worst_path.webp','6_drc.lyrdb','6_drc_count.rpt']:
    if (rpts/name).exists():shutil.copy2(rpts/name,archive/name)
# Strip trailing whitespace from text logs only; numerical content is unchanged.
for path in archive.iterdir():
    if path.suffix in ['.log','.txt','.rpt']:
        path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines()).rstrip()+'\n')
(archive/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
if not summary['timing_and_router_clean'] or not summary['physical_acceptance']:
    raise SystemExit('Reference evidence archived; physical acceptance incomplete. Inspect summary.json.')
