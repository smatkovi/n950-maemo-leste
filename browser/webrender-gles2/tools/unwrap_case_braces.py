#!/usr/bin/env python3
"""After switch2if.py: an if branch whose whole body is one braced case
block ("if (c) { {" ... "}" then the branch's own "}") loses the inner
braces, and the block's lines move to the branch's indentation."""
import re, sys

def match_brace(s, i):
    depth = 0
    while i < len(s):
        if s.startswith('//', i):
            i = s.find('\n', i)
            if i < 0:
                break
            continue
        if s[i] == '{':
            depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError('unbalanced')

def unwrap(s):
    pat = re.compile(r'(\n([ \t]*)(?:\} else(?: if \([^\n]*\))?|if \([^\n]*\))) \{ \{')
    pos = 0
    while True:
        m = pat.search(s, pos)
        if not m:
            return s
        indent = m.group(2)
        inner = m.end() - 1
        close = match_brace(s, inner)
        after = s[close + 1:]
        if not re.match(r'\s*\n[ \t]*\}', after):
            pos = m.end()
            continue
        body = s[inner + 1:close]
        lines = body.split('\n')
        content = [l for l in lines[1:] if l.strip()]
        cur = min((len(l) - len(l.lstrip()) for l in content), default=0)
        want = len(indent) + 4
        new_lines = []
        for l in lines[1:]:
            if l.strip():
                new_lines.append(' ' * want + l[cur:] if len(l) - len(l.lstrip()) >= cur else l)
            else:
                new_lines.append('')
        new_body = '\n'.join(new_lines).rstrip()
        rest = after.lstrip(' \t')
        if rest.startswith('\n'):
            rest = rest[1:]
        s = s[:m.end() - 2] + '\n' + new_body + '\n' + rest
        pos = m.start() + 1

for path in sys.argv[1:]:
    src = open(path).read()
    new = unwrap(src)
    if new != src:
        open(path, 'w').write(new)
        print(path)
