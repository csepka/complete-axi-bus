#!/usr/bin/env python3
"""Preserve Boolean functionality while avoiding MUX reconvergence X pessimism.

An unknown select represents both binary choices. If both data values are known
and equal, the output is that value. Input Z is treated as an unknown logic value.
This is a zero-delay functional abstraction, not a transistor or timing model.
"""
import re

def refine(source):
    expected = ['assign _1_ = S & B;', 'assign _2_ = A & _0_;',
                'assign _3_ = _1_ | _2_;', 'assign _0_ = ~S;', 'assign Z = _3_;']
    for name in ['MUX2_X1', 'MUX2_X2']:
        pattern = rf'module {name}\(A, B, S, Z\);.*?endmodule'
        matches = list(re.finditer(pattern, source, re.S))
        assert len(matches) == 1, f'Review library model: {name}'
        original = matches[0].group()
        assignments = [line.strip() for line in original.splitlines() if line.strip().startswith('assign ')]
        assert assignments == expected, f'Review changed Liberty function: {name}'
        replacement = f'''// Consensus-preserving four-state functional MUX; binary function unchanged.
module {name}(input A, B, S, output Z);
  assign Z = S ? (B & 1'b1) : (A & 1'b1);
endmodule'''
        source = source[:matches[0].start()] + replacement + source[matches[0].end():]
    return source

if __name__ == '__main__':
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    folder = root/'build/physical'
    (folder/'nangate45_models.v').write_text(refine((folder/'nangate45_models_raw.v').read_text()))
