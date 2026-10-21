#!/usr/bin/env python3
"""Render the deterministic AW-backpressure interval from tb_axi_burst VCD.

This uses only the Python standard library. Run `make waveform` to regenerate
both the ignored VCD and the committed SVG.
"""

from __future__ import annotations

import argparse
import html
import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Signal:
    path: str
    label: str
    width: int = 0
    code: str = ""
    changes: list[tuple[int, str]] = field(default_factory=list)


SIGNALS = [
    Signal("tb_axi_burst.ACLK", "ACLK"),
    Signal("tb_axi_burst.stall_aw", "AW stall"),
    Signal("tb_axi_burst.m_axi[1].AWVALID", "M1 AWVALID"),
    Signal("tb_axi_burst.m_axi[1].AWREADY", "M1 AWREADY"),
    Signal("tb_axi_burst.m_axi[1].AWADDR", "M1 AWADDR"),
    Signal("tb_axi_burst.m_axi[0].AWVALID", "M0 AWVALID"),
    Signal("tb_axi_burst.m_axi[0].AWREADY", "M0 AWREADY"),
    Signal("tb_axi_burst.s_axi[0].AWVALID", "S0 AWVALID"),
    Signal("tb_axi_burst.s_axi[0].AWREADY", "S0 AWREADY"),
    Signal("tb_axi_burst.dut.g_target[0].u_arbiter.w_addr_hold", "Grant held"),
    Signal("tb_axi_burst.dut.g_target[0].u_arbiter.w_hold_owner", "Held owner"),
]

UNIT_FS = {
    "s": 10**15,
    "ms": 10**12,
    "us": 10**9,
    "ns": 10**6,
    "ps": 10**3,
    "fs": 1,
}


def parse_timescale(text: str) -> int:
    match = re.search(r"\$timescale\s+(\d+)\s*(s|ms|us|ns|ps|fs)\s+\$end", text)
    if not match:
        raise ValueError("VCD has no supported $timescale declaration")
    return int(match.group(1)) * UNIT_FS[match.group(2)]


def parse_vcd(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace")
    scale_fs = parse_timescale(text)
    wanted = {signal.path: signal for signal in SIGNALS}
    code_map: dict[str, list[Signal]] = {}
    scopes: list[str] = []
    lines = iter(text.splitlines())

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("$scope "):
            scopes.append(stripped.split()[2])
        elif stripped.startswith("$upscope"):
            scopes.pop()
        elif stripped.startswith("$var "):
            parts = stripped.split()
            width, code, name = int(parts[2]), parts[3], parts[4]
            full_name = ".".join([*scopes, name])
            if full_name in wanted:
                signal = wanted[full_name]
                signal.width = width
                signal.code = code
                code_map.setdefault(code, []).append(signal)
        elif stripped.startswith("$enddefinitions"):
            break

    missing = [signal.path for signal in SIGNALS if not signal.code]
    if missing:
        raise ValueError("required VCD signals are missing: " + ", ".join(missing))

    current_time = 0
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("$"):
            continue
        if stripped.startswith("#"):
            current_time = int(stripped[1:])
            continue
        if stripped[0] in "01xXzZ":
            value, code = stripped[0].lower(), stripped[1:]
        elif stripped[0] in "bB":
            value, code = stripped[1:].split(maxsplit=1)
            value = value.lower()
        else:
            continue
        for signal in code_map.get(code, []):
            if not signal.changes or signal.changes[-1][1] != value:
                signal.changes.append((current_time, value))

    return scale_fs


def value_at(signal: Signal, time: int) -> str:
    value = "x"
    for change_time, change_value in signal.changes:
        if change_time > time:
            break
        value = change_value
    return value


def clipped_changes(signal: Signal, start: int, end: int) -> list[tuple[int, str]]:
    changes = [(start, value_at(signal, start))]
    changes.extend((time, value) for time, value in signal.changes if start < time <= end)
    return changes


def first_rising_handshake(start: int, end: int, port: str = "m_axi[1]") -> int:
    by_path = {signal.path: signal for signal in SIGNALS}
    clock = by_path["tb_axi_burst.ACLK"]
    valid = by_path[f"tb_axi_burst.{port}.AWVALID"]
    ready = by_path[f"tb_axi_burst.{port}.AWREADY"]
    for time, value in clock.changes:
        if start <= time <= end and value == "1":
            # READY can fall in the same VCD timestamp after the accepting edge,
            # so sample the settled values immediately before the clock event.
            if value_at(valid, time - 1) == "1" and value_at(ready, time - 1) == "1":
                return time
    raise ValueError("no AW handshake found in the selected window")


def bus_label(value: str, width: int) -> str:
    if any(bit not in "01" for bit in value):
        return value.upper()
    digits = max(1, (width + 3) // 4)
    return f"0x{int(value, 2):0{digits}X}"


def render_svg(output: Path, start: int, end: int, scale_fs: int) -> None:
    width = 1200
    left, right = 180, 30
    plot_width = width - left - right
    top, row_height, bottom = 105, 48, 55
    height = top + len(SIGNALS) * row_height + bottom
    start_ns = start * scale_fs / UNIT_FS["ns"]
    end_ns = end * scale_fs / UNIT_FS["ns"]

    def x(time: int) -> float:
        return left + (time - start) * plot_width / (end - start)

    svg: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
        '<title id="title">AXI4 write-address backpressure trace</title>',
        '<desc id="desc">Waveform generated from the passing burst regression. Manager 1 retains the write-address grant while subordinate 0 is stalled and manager 0 begins requesting.</desc>',
        '<rect width="100%" height="100%" fill="#0d1117"/>',
        '<style>text{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}.title{fill:#f0f6fc;font-size:20px;font-weight:700}.sub{fill:#8b949e;font-size:12px}.label{fill:#c9d1d9;font-size:13px}.tick{fill:#8b949e;font-size:11px}.digital{fill:none;stroke:#58a6ff;stroke-width:2}.bus{fill:#238636;fill-opacity:.18;stroke:#3fb950;stroke-width:1.5}.busText{fill:#aff5b4;font-size:11px}.grid{stroke:#30363d;stroke-width:1}.event{stroke:#d29922;stroke-width:1.5;stroke-dasharray:5 4}.eventText{fill:#e3b341;font-size:11px}</style>',
        '<text class="title" x="24" y="30">AW arbitration under subordinate backpressure</text>',
        '<text class="sub" x="24" y="52">Generated from build/tb_axi_burst.vcd by tools/vcd_to_svg.py</text>',
    ]

    for tick_ns in range(int(start_ns // 10 * 10), int(end_ns) + 1, 10):
        if tick_ns < start_ns:
            continue
        tick_time = round(tick_ns * UNIT_FS["ns"] / scale_fs)
        tick_x = x(tick_time)
        svg.append(f'<line class="grid" x1="{tick_x:.2f}" y1="{top - 14}" x2="{tick_x:.2f}" y2="{height - bottom + 4}"/>')
        svg.append(f'<text class="tick" x="{tick_x:.2f}" y="{top - 22}" text-anchor="middle">{tick_ns} ns</text>')

    handshake_time = first_rising_handshake(start, end)
    event_x = x(handshake_time)
    handshake_ns = handshake_time * scale_fs / UNIT_FS["ns"]
    svg.append(f'<line class="event" x1="{event_x:.2f}" y1="{top - 12}" x2="{event_x:.2f}" y2="{height - bottom + 4}"/>')
    svg.append(f'<text class="eventText" x="{event_x - 5:.2f}" y="{top - 40}" text-anchor="end">M1 queued ({handshake_ns:g} ns)</text>')

    target_time = first_rising_handshake(start, end, "s_axi[0]")
    target_x = x(target_time)
    target_ns = target_time * scale_fs / UNIT_FS["ns"]
    svg.append(f'<line class="event" x1="{target_x:.2f}" y1="{top - 12}" x2="{target_x:.2f}" y2="{height - bottom + 4}"/>')
    svg.append(f'<text class="eventText" x="{target_x - 5:.2f}" y="{top - 40}" text-anchor="end">S0 accepts ({target_ns:g} ns)</text>')

    for index, signal in enumerate(SIGNALS):
        row_top = top + index * row_height
        mid = row_top + row_height / 2
        high, low = mid - 10, mid + 10
        svg.append(f'<text class="label" x="{left - 12}" y="{mid + 5:.2f}" text-anchor="end">{html.escape(signal.label)}</text>')
        svg.append(f'<line class="grid" x1="{left}" y1="{row_top + row_height - 2}" x2="{width - right}" y2="{row_top + row_height - 2}"/>')
        changes = clipped_changes(signal, start, end)
        if signal.width == 1:
            points: list[str] = []
            for change_index, (time, value) in enumerate(changes):
                level = high if value == "1" else low if value == "0" else mid
                if change_index:
                    points.append(f"{x(time):.2f},{previous_level:.2f}")
                points.append(f"{x(time):.2f},{level:.2f}")
                previous_level = level
            points.append(f"{x(end):.2f},{previous_level:.2f}")
            svg.append(f'<polyline class="digital" points="{" ".join(points)}"/>')
        else:
            for change_index, (time, value) in enumerate(changes):
                next_time = changes[change_index + 1][0] if change_index + 1 < len(changes) else end
                x1, x2 = x(time), x(next_time)
                if x2 - x1 < 1:
                    continue
                svg.append(f'<rect class="bus" x="{x1:.2f}" y="{mid - 11:.2f}" width="{x2 - x1:.2f}" height="22" rx="3"/>')
                if x2 - x1 > 44:
                    svg.append(f'<text class="busText" x="{(x1 + x2) / 2:.2f}" y="{mid + 4:.2f}" text-anchor="middle">{html.escape(bus_label(value, signal.width))}</text>')

    svg.append(f'<text class="sub" x="{left}" y="{height - 18}">Window: {start_ns:g}–{end_ns:g} ns · source regression: burst regression (see run log for check count)</text>')
    svg.append("</svg>")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(svg) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vcd", nargs="?", type=Path, default=Path("build/tb_axi_burst.vcd"))
    parser.add_argument("output", nargs="?", type=Path, default=Path("docs/images/axi-aw-backpressure.svg"))
    parser.add_argument("--start-ns", type=float, default=55.0)
    parser.add_argument("--end-ns", type=float, default=195.0)
    args = parser.parse_args()
    scale_fs = parse_vcd(args.vcd)
    start = round(args.start_ns * UNIT_FS["ns"] / scale_fs)
    end = round(args.end_ns * UNIT_FS["ns"] / scale_fs)
    if end <= start:
        parser.error("--end-ns must be greater than --start-ns")
    render_svg(args.output, start, end, scale_fs)
    print(f"Wrote {args.output} from {args.vcd} ({args.start_ns:g}–{args.end_ns:g} ns)")


if __name__ == "__main__":
    main()
