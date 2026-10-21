#!/usr/bin/env python3
"""Compile and measure real AXI simulations; no third-party Python dependencies."""
import argparse
import csv
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '2ec5059cf00b51b40ee441fab273f5a2d1d8f462'
FLAGS = ['-sv', '--timing', '--assert', '--Wall', '-Wno-UNUSEDSIGNAL',
         '-Wno-UNSIGNED', '-Wno-SYNCASYNCNET']


def run(command, log=None):
    p = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(p.stdout)
    if p.returncode:
        raise RuntimeError(f"Command failed: {' '.join(command)}\n{p.stdout[-6000:]}")
    return p.stdout


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--revision', help='Read immutable RTL from git (e.g. '+BASELINE+'); working tree by default')
    p.add_argument('--label', default='current')
    p.add_argument('--config', action='append', help='NMxNSxDATA_W, repeatable; default 2x2x64')
    p.add_argument('--depth', type=int, default=4)
    p.add_argument('--addr-width', type=int, default=32)
    p.add_argument('--clock-mhz', type=float, default=100)
    p.add_argument('--transactions', type=int, default=32)
    p.add_argument('--seed', type=int, default=7)
    p.add_argument('--burst', type=int, help='Run only a custom scenario')
    p.add_argument('--mode', type=int, choices=[0, 1, 2], default=2, help='0 read, 1 write, 2 both')
    p.add_argument('--distribution', type=int, choices=[0, 1, 2], default=0, help='0 independent, 1 hotspot, 2 rotating')
    p.add_argument('--ready', type=int, default=100)
    p.add_argument('--arrival', type=int, default=100)
    a = p.parse_args()
    if not a.label.replace('-', '').replace('_', '').isalnum():
        p.error('label must contain only letters, digits, hyphens, underscores')
    if a.clock_mhz <= 0:
        p.error('clock must be positive')
    results = ROOT/'benchmarks/results'/a.label
    results.mkdir(parents=True, exist_ok=True)
    revision = run(['git', 'rev-parse', a.revision or 'HEAD']).strip()
    names = ['axi_if.sv', 'axi_ram.sv', 'axi_sub.sv', 'axi_interconnect.sv']
    rtl_dir = ROOT/'src'
    if a.revision:
        rtl_dir = ROOT/'build'/('rtl-'+revision[:12])
        rtl_dir.mkdir(parents=True, exist_ok=True)
        available = run(['git', 'ls-tree', '-r', '--name-only', revision, 'src']).splitlines()
        names = [Path(f).name for f in available if f.endswith('.sv') and 'checker' not in f]
        names.sort(key=lambda f: f != 'axi_if.sv')
        for f in names:
            (rtl_dir/f).write_text(run(['git', 'show', f'{revision}:src/{f}']))
    else:
        names = [f.name for f in sorted(rtl_dir.glob('*.sv')) if 'checker' not in f.name]
        names.sort(key=lambda f: f != 'axi_if.sv')
    queued = 'MAX_OUTSTANDING' in (rtl_dir/'axi_interconnect.sv').read_text()
    rows, ports = [], []
    for cfg in a.config or ['2x2x64']:
        nm, ns, width = map(int, cfg.split('x'))
        build = ROOT/'build'/f'bench-{a.label}-{cfg}-d{a.depth}-a{a.addr_width}'
        build.mkdir(parents=True, exist_ok=True)
        command = ['verilator', *FLAGS, '--binary', '-j', '4', '--Mdir', str(build),
                   '--top-module', 'tb_axi_benchmark', f'-GNM={nm}', f'-GNS={ns}',
                   f'-GDATA_W={width}', f'-GADDR_W={a.addr_width}', f'-GDEPTH={a.depth}']
        if queued:
            command += ['+define+QUEUED_FABRIC']
        command += ['tb/tb_axi_benchmark.sv', 'src/axi_protocol_checker.sv'] + [str(rtl_dir/f) for f in names]
        run(command, results/f'{cfg}-build.log')
        max_burst = min(256, 4096//(width//8))
        cases = [('single-read', 16, 0, 0, 100, 100, 1),
                 ('single-write', 16, 1, 0, 100, 100, 1),
                 ('single-mixed', 16, 2, 0, 100, 100, 1),
                 ('independent', 16, 2, 0, 100, 100, nm),
                 ('hotspot', 16, 2, 1, 100, 100, nm),
                 ('backpressure', 16, 2, 0, 45, 100, nm),
                 ('sparse', 16, 2, 2, 100, 25, nm),
                 ('burst-1', 1, 2, 0, 100, 100, nm),
                 ('burst-64', 64, 2, 0, 100, 100, nm),
                 ('burst-max', max_burst, 2, 0, 100, 100, nm)]
        if a.burst:
            cases = [('custom', a.burst, a.mode, a.distribution, a.ready, a.arrival, nm)]
        for case, burst, mode, dist, ready, arrival, managers in cases:
            output = run([str(build/'Vtb_axi_benchmark'), f'+burst={burst}', f'+mode={mode}',
                          f'+distribution={dist}', f'+ready={ready}', f'+arrival={arrival}',
                          f'+managers={managers}', f'+transactions={a.transactions}', f'+seed={a.seed}'],
                         results/f'{cfg}-{case}.log')
            if 'BENCHMARK PASS' not in output:
                raise RuntimeError('Missing benchmark completion')
            total = next(list(map(int, l.split(',')[1:])) for l in output.splitlines() if l.startswith('TOTAL,'))
            cycles, peak_w, peak_r, peak_ow, peak_or = total
            ms = [list(map(int, l.split(',')[1:])) for l in output.splitlines() if l.startswith('MANAGER,')]
            ts = [list(map(int, l.split(',')[1:])) for l in output.splitlines() if l.startswith('TARGET,')]
            wbeats, rbeats = sum(m[1] for m in ms), sum(m[2] for m in ms)
            count = sum(m[9] for m in ms)
            gbps = (wbeats+rbeats)*(width//8)/cycles*a.clock_mhz/1000
            row = dict(label=a.label, config=cfg, case=case, depth=a.depth if queued else 1,
                       burst=burst, mode=mode, distribution=dist, ready_percent=ready,
                       arrival_percent=arrival, seed=a.seed, transactions=a.transactions,
                       active_managers=managers, cycles=cycles, write_beats=wbeats, read_beats=rbeats,
                       useful_bytes=(wbeats+rbeats)*(width//8), bus_bytes=(wbeats+rbeats)*(width//8),
                       write_GBs=wbeats*(width//8)/cycles*a.clock_mhz/1000,
                       read_GBs=rbeats*(width//8)/cycles*a.clock_mhz/1000,
                       aggregate_GBs=gbps, aggregate_Gbs=gbps*8,
                       assumed_clock_MHz=a.clock_mhz,
                       fabric_full_duplex_peak_GBs=2*(min(nm,ns) if queued else 1)*(width//8)*a.clock_mhz/1000,
                       write_utilization=wbeats/cycles/(min(nm,ns) if queued else 1),
                       read_utilization=rbeats/cycles/(min(nm,ns) if queued else 1),
                       avg_accepted_latency=sum(m[7] for m in ms)/count,
                       max_accepted_latency=max(m[8] for m in ms),
                       avg_offered_latency=sum(m[10] for m in ms)/count,
                       max_offered_latency=max(m[11] for m in ms),
                       aw_wait=sum(m[3] for m in ms), ar_wait=sum(m[4] for m in ms),
                       w_stalls=sum(m[5] for m in ms), r_stalls=sum(m[6] for m in ms),
                       peak_w_beats_per_cycle=peak_w, peak_r_beats_per_cycle=peak_r,
                       peak_outstanding_w=peak_ow, peak_outstanding_r=peak_or)
            rows.append(row)
            for kind, values in [('manager', ms), ('target', ts)]:
                for v in values:
                    ports.append(dict(config=cfg, case=case, kind=kind, index=v[0], write_beats=v[1],
                                      read_beats=v[2], GBs=(v[1]+v[2])*(width//8)/cycles*a.clock_mhz/1000))
            print(f'{a.label} {cfg} {case}: {cycles} cycles, {gbps:.4f} GB/s (assumed clock)', flush=True)
    for name, data in [('summary.csv', rows), ('ports.csv', ports)]:
        with (results/name).open('w', newline='') as f:
            writer=csv.DictWriter(f, fieldnames=list(data[0]));writer.writeheader();writer.writerows(data)
    (results/'metadata.json').write_text(json.dumps(dict(revision=revision, dirty=bool(run(['git','status','--porcelain'])),
        rtl_from_git=bool(a.revision), verilator=run(['verilator','--version']).strip(),
        arguments=vars(a)), indent=2)+'\n')
    md = '# Measured simulation results\n\nClock assumption: '+str(a.clock_mhz)+' MHz; no STA/Fmax claim.\n\n'
    md += '| Config | Scenario | Cycles | GB/s | Gb/s | Avg / max accepted latency | Peak W / R beats per cycle |\n|---|---|---:|---:|---:|---:|---:|\n'
    for r in rows:
        md += f"| {r['config']} | {r['case']} | {r['cycles']} | {r['aggregate_GBs']:.4f} | {r['aggregate_Gbs']:.4f} | {r['avg_accepted_latency']:.1f} / {r['max_accepted_latency']} | {r['peak_w_beats_per_cycle']} / {r['peak_r_beats_per_cycle']} |\n"
    (results/'summary.md').write_text(md)
    # Portable static plot; exact values remain available in CSV.
    selected=[r for r in rows if r['case'] in ('independent','hotspot','backpressure','burst-1')]
    if selected:
        maximum=max(r['aggregate_GBs'] for r in selected)
        svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="900" height="{80+len(selected)*36}"><rect width="100%" height="100%" fill="white"/><g font-family="sans-serif" font-size="14"><text x="20" y="25">{a.label}: simulated aggregate GB/s at assumed {a.clock_mhz:g} MHz</text>']
        for i,r in enumerate(selected):
            y=50+i*36;bar=450*r['aggregate_GBs']/maximum
            svg += [f'<text x="20" y="{y+18}">{r["config"]} {r["case"]}</text><rect x="260" y="{y}" width="{bar}" height="24" fill="#247caa"/><text x="{270+bar}" y="{y+18}">{r["aggregate_GBs"]:.3f}</text>']
        svg+=['</g></svg>'];(ROOT/'benchmarks/plots'/f'{a.label}.svg').write_text(''.join(svg))

if __name__ == '__main__':
    main()
