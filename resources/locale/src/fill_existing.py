#!/usr/bin/env python3
# 既存の言語ファイル（2026-11-04 までに作ったもの）を今のソースの文にそろえる（2026-11-16）。
#   python3 resources/locale/src/fill_existing.py <code>...
# - 画面の文（ui）は今の鍵の順に並べ直す。すでにある訳はそのまま、無いものは work/<code>_fill.tsv の "U001<TAB>訳" で補う。
#   日本語（ja）は鍵そのもの。補いも無ければ英語（en.txt の訳）で埋めて知らせる（日本語が混ざらないように）。
# - ソースから消えた古い鍵は落とす。知らせ（msg.*）はそのまま残し、補いの "M001<TAB>訳" で足りないものを足す。
# - 確かめること（build_ids.py と同じ）: % の並び、ファンクションキーのラベルの幅、結合記号を外す。
import json, os, re, sys, unicodedata
HERE = os.path.dirname(os.path.abspath(__file__)); LOC = os.path.dirname(HERE)
PCT = re.compile(r'%[-+ #0]*\d*(?:\.\d+)?(?:l|ll|z)?[diouxXcspfeg%]')
def unesc(s): return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
def esc(s): return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n')
def cells(s): return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in s)
def clean(s): return ''.join(c for c in unicodedata.normalize('NFC', s) if not unicodedata.combining(c))
keys = json.load(open(os.path.join(HERE, 'work/keys.json'), encoding='utf-8'))
en_ui, fk = {}, set()
for l in open(os.path.join(HERE, 'work/strings.tsv'), encoding='utf-8'):
    p = l.rstrip('\n').split('\t')
    if p[0].startswith('U'):
        t = p[1]
        if t.startswith('[F8] '): fk.add(p[0]); t = t[5:]
        en_ui[p[0]] = unesc(t)
for code in sys.argv[1:]:
    path = os.path.join(LOC, '%s.txt' % code)
    head, ui, msgs = [], {}, []
    for l in open(path, encoding='utf-8'):
        l = l.rstrip('\n')
        if not l: continue
        if l.startswith('#') or l.startswith('@'): head.append(l); continue
        f = l.split('\t')
        if f[0] == 'ui' and len(f) == 3: ui[unesc(f[1])] = unesc(f[2])
        elif f[0].startswith('msg.') and len(f) == 3: msgs.append((f[0], unesc(f[1]), unesc(f[2])))
    fill = {}
    fp = os.path.join(HERE, 'work/%s_fill.tsv' % code)
    if os.path.exists(fp):
        for l in open(fp, encoding='utf-8'):
            l = l.rstrip('\n')
            if not l or l.startswith('#') or '\t' not in l: continue
            k, v = l.split('\t', 1)
            fill[k.strip()] = clean(unesc(v))
    out, filled, eng, bad = list(head), 0, 0, 0
    for i, ja in enumerate(keys['ui']):
        k = 'U%03d' % (i + 1)
        en = en_ui[k]
        t = ja if code == 'ja' else ui.get(ja)          # 日本語はファームの文そのもの
        if t is None:
            t = ja if code == 'ja' else fill.get(k)
            if t is None: t = en; eng += 1
            else: filled += 1
            if PCT.findall(t) != PCT.findall(en): print('%s %s: %% differs, English used: %r' % (code, k, t)); bad += 1; t = en
            if k in fk and cells(t) > 8: print('%s %s: F-key label too wide, English used: %r' % (code, k, t)); bad += 1; t = en
        out.append('ui\t%s\t%s' % (esc(ja), esc(t)))
    have = set((kind, e) for kind, e, _ in msgs)
    for kind, e, t in msgs: out.append('%s\t%s\t%s' % (kind, esc(e), esc(t)))
    added = 0
    for i, (kind, e) in enumerate(keys['msg']):
        k = 'M%03d' % (i + 1)
        if (kind, e) in have or k not in fill: continue
        t = fill[k]
        if kind == 'msg.pattern':
            if t.count('%s') != 1 or t.replace('%s', '').count('%'): print('%s %s: a pattern needs one %%s, dropped' % (code, k)); continue
        elif kind != 'msg.word' and PCT.findall(t) != PCT.findall(e): print('%s %s: %% differs, dropped: %r' % (code, k, t)); continue
        out.append('%s\t%s\t%s' % (kind, esc(e), esc(t))); added += 1
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('%s: ui filled %d, English fallback %d, fixed %d, messages added %d, stale ui dropped %d' % (
        code, filled, eng, bad, added, len([j for j in ui if j not in set(keys['ui'])])))
