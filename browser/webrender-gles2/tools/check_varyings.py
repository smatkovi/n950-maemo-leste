#!/usr/bin/env python3
"""Varyings of each ES 2.0 shader variant against what the PowerVR SGX530
accepts, from the vertex shaders `wrench compile_shaders` dumps
(WRENCH_SHADER_DUMP=DIR).

Measured on the SGX530 (DDK 1.17): it fails with "Failed to allocate
varyings" past 8 vectors, and packs less tightly than GLSL ES 1.00's
rules: everything up to 7 rows by those rules compiled, 8 rows only when
all varyings were vec4 (8 x vec4 compiles, 11 mixed varyings of 32
components do not).

Usage: check_varyings.py DUMPDIR   (exit status 1 when a variant fails)
"""
import os
import re
import subprocess
import sys

SIZE = {'float': (1, 1), 'vec2': (1, 2), 'vec3': (1, 3), 'vec4': (1, 4),
        'mat2': (2, 2), 'mat3': (3, 3), 'mat4': (4, 4)}


def preprocess(path):
    src = ''.join(l for l in open(path) if not l.startswith(('#version', '#extension')))
    return subprocess.run(['cpp', '-P', '-U__VERSION__', '-D__VERSION__=100', '-DGL_ES=1'],
                          input=src, capture_output=True, text=True).stdout


def rows(columns):
    grid = []
    for c in sorted(columns, reverse=True):
        for i, used in enumerate(grid):
            if used + c <= 4:
                grid[i] += c
                break
        else:
            grid.append(c)
    return len(grid)


def main():
    d = sys.argv[1]
    bad = 0
    for f in sorted(os.listdir(d)):
        if not f.endswith('.vert'):
            continue
        text = preprocess(os.path.join(d, f))
        decls = re.findall(r'^\s*varying\s+(?:(?:highp|mediump|lowp)\s+)?(\w+)\s+(\w+)(?:\[(\d+)\])?\s*;',
                           text, re.M)
        columns = []
        for t, _, n in decls:
            r, c = SIZE[t]
            columns += [c] * (r * int(n or 1))
        n_rows = rows(columns)
        ok = n_rows <= 7 or (n_rows == 8 and all(c == 4 for c in columns))
        if not ok:
            bad += 1
        print('%-4s %-58s varyings %2d rows %2d components %2d'
              % ('ok' if ok else 'FAIL', f[:-5], len(decls), n_rows, sum(columns)))
    print('%d variants over the SGX530 varying limit' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
