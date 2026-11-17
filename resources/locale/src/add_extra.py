#!/usr/bin/env python3
# work/extra_msg.tsv の文（2026-11-16 の SGCALC のマクロなど）を、既存の言語ファイルの末尾へ msg.phrase で足す。
# 訳は work/extra_existing.py。すでにある英語は足さない（何度走らせてもよい）。% の並びが違う訳は捨てる。
import os, re, sys, unicodedata
HERE = os.path.dirname(os.path.abspath(__file__)); LOC = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, 'work'))
from extra_existing import T
PCT = re.compile(r'%[-+ #0]*\d*(?:\.\d+)?(?:l|ll|z)?[diouxXcspfeg%]')
def esc(s): return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n')
en = [l.rstrip('\n').split('\t')[2] for l in open(os.path.join(HERE, 'work/extra_msg.tsv'), encoding='utf-8') if l.startswith('N')]
for code, tr in T.items():
    assert len(tr) == len(en), (code, len(tr))
    p = os.path.join(LOC, '%s.txt' % code)
    have = set(l.split('\t')[1] for l in open(p, encoding='utf-8') if l.startswith('msg.'))
    add = []
    for e, t in zip(en, tr):
        t = ''.join(c for c in unicodedata.normalize('NFC', t) if not unicodedata.combining(c))
        if e in have: continue
        if PCT.findall(t) != PCT.findall(e): print(code, 'dropped (% differs):', t); continue
        add.append('msg.phrase\t%s\t%s' % (esc(e), esc(t)))
    if add:
        s = open(p, encoding='utf-8').read()
        open(p, 'w', encoding='utf-8').write(s.rstrip('\n') + '\n' + '\n'.join(add) + '\n')
    print(code, 'added', len(add))
