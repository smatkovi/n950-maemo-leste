#!/usr/bin/env python3
"""Rewrites GLSL switch statements as if/else chains (GLSL ES 1.00 has no
switch). Usage: switch2if.py FILE...; a switch it cannot convert safely
(fallthrough, a break inside a case block) is left alone and reported."""
import re, sys

counter = [0]

def skip_comment(s, i):
    if s.startswith('//', i):
        j = s.find('\n', i)
        return len(s) if j < 0 else j
    if s.startswith('/*', i):
        j = s.find('*/', i + 2)
        return len(s) if j < 0 else j + 2
    return i

def match_brace(s, i):
    """s[i] == '{'; index of the matching '}'."""
    depth = 0
    while i < len(s):
        j = skip_comment(s, i)
        if j != i:
            i = j
            continue
        c = s[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError('unbalanced braces')

def match_paren(s, i):
    depth = 0
    while i < len(s):
        if s[i] == '(':
            depth += 1
        elif s[i] == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError('unbalanced parens')

LABEL = re.compile(r'\b(case\s+([^:]+?)|default)\s*:')

def top_level_labels(body):
    """Positions of case/default labels at nesting depth 0 of the body."""
    out = []
    depth = 0
    i = 0
    while i < len(body):
        j = skip_comment(body, i)
        if j != i:
            i = j
            continue
        c = body[i]
        if c in '({':
            depth += 1
        elif c in ')}':
            depth -= 1
        elif depth == 0:
            m = LABEL.match(body, i)
            if m and (i == 0 or not (body[i - 1].isalnum() or body[i - 1] == '_')):
                out.append(m)
                i = m.end()
                continue
        i += 1
    return out

def strip_trailing(stmts):
    t = stmts.rstrip()
    if t.endswith('break;'):
        return t[:-len('break;')].rstrip(), True
    if t.endswith('}'):
        # a braced case block: look at its last statement
        depth = 0
        for i in range(len(t) - 1, -1, -1):
            if t[i] == '}':
                depth += 1
            elif t[i] == '{':
                depth -= 1
                if depth == 0:
                    break
        if t[:i].strip() == '':
            inner, terminated = strip_trailing(t[i + 1:-1])
            if terminated:
                return t[:i] + '{' + inner + '\n' + ' ' * 0 + '}', True
    ends_return = re.search(r'\breturn\b[^;]*;\s*$', t) is not None or re.search(r'\bdiscard\s*;\s*$', t) is not None
    return t, ends_return

def convert_one(s, start):
    m = re.compile(r'\bswitch\s*\(').match(s, start)
    p_open = s.index('(', start)
    p_close = match_paren(s, p_open)
    expr = s[p_open + 1:p_close].strip()
    b_open = s.index('{', p_close)
    b_close = match_brace(s, b_open)
    body = s[b_open + 1:b_close]
    labels = top_level_labels(body)
    if not labels:
        raise ValueError('no labels')
    groups = []  # (conds, is_default, stmts)
    k = 0
    while k < len(labels):
        conds, is_default = [], False
        while True:
            lm = labels[k]
            if lm.group(1) == 'default':
                is_default = True
            else:
                conds.append(lm.group(2).strip())
            nxt = labels[k + 1].start() if k + 1 < len(labels) else len(body)
            between = body[lm.end():nxt]
            if between.strip() == '' and k + 1 < len(labels):
                k += 1
                continue
            break
        stmts = between
        k += 1
        groups.append((conds, is_default, stmts))
    var = 'wr_switch_%d' % counter[0]
    counter[0] += 1
    pieces = []
    default_stmts = None
    for idx, (conds, is_default, stmts) in enumerate(groups):
        body_stmts, terminated = strip_trailing(stmts)
        if not terminated and idx != len(groups) - 1:
            raise ValueError('fallthrough after case %s' % conds)
        if re.search(r'\bbreak\s*;', body_stmts) and not re.search(r'\b(for|while)\s*\(', body_stmts):
            raise ValueError('break inside case %s' % conds)
        if is_default:
            default_stmts = body_stmts
            continue
        cond = ' || '.join('%s == (%s)' % (var, c) for c in conds)
        pieces.append((cond, body_stmts))
    ind = s[s.rfind('\n', 0, start) + 1:start]
    out = '{\n%s    int %s = int(%s);\n' % (ind, var, expr)
    first = True
    for cond, body_stmts in pieces:
        out += '%s    %sif (%s) {%s\n%s    }' % (ind, '' if first else '} else '.replace('} ', ''), cond, body_stmts, ind)
        out += '\n' if False else ''
        first = False
        out = out.rstrip('}').rstrip() + '\n%s    }' % ind if False else out
    # rebuild cleanly
    out = '{\n%s    int %s = int(%s);\n' % (ind, var, expr)
    for i, (cond, body_stmts) in enumerate(pieces):
        kw = 'if' if i == 0 else '} else if'
        out += '%s    %s (%s) {%s\n' % (ind, kw, cond, body_stmts)
    if default_stmts is not None:
        if pieces:
            out += '%s    } else {%s\n' % (ind, default_stmts)
        else:
            out += '%s    {%s\n' % (ind, default_stmts)
    out += '%s    }\n%s}' % (ind, ind)
    return s[:start] + out + s[b_close + 1:]

def convert(s, name):
    pos = 0
    while True:
        m = re.compile(r'\bswitch\s*\(').search(s, pos)
        if not m:
            return s
        try:
            s = convert_one(s, m.start())
        except ValueError as e:
            print('%s: left alone (%s) at: %s' % (name, e, s[m.start():m.start() + 60].replace('\n', ' ')))
            pos = m.end()
            continue
        pos = m.start() + 1

for path in sys.argv[1:]:
    src = open(path).read()
    new = convert(src, path)
    if new != src:
        open(path, 'w').write(new)
        print('%s: %d switch' % (path, src.count('switch') - new.count('switch')))
