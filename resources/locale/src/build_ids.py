#!/usr/bin/env python3
# 番号つきの訳（work/<code>.tsv: "U001<TAB>訳" / "M001<TAB>訳"）から resources/locale/<code>.txt を組み立てる（2026-11-16）。
# 番号は work/strings.tsv（英語）と work/keys.json（日本語の鍵・知らせの英語の並び）に対応する。
#   python3 resources/locale/src/build_ids.py <code> "<言語の名前>"
# 確かめること: % の並びが英語と同じ（違えば使わない）、ファンクションキーのラベル（[F8]）は 8 桁まで、抜けた画面の文は英語で埋める
import json, os, re, sys, unicodedata
HERE = os.path.dirname(os.path.abspath(__file__))
LOC = os.path.dirname(HERE)
def unesc(s): return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
def esc(s): return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n')
def cells(s): return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in s)
PCT = re.compile(r'%[-+ #0]*\d*(?:\.\d+)?(?:l|ll|z)?[diouxXcspfeg%]')
keys = json.load(open(os.path.join(HERE, 'work/keys.json'), encoding='utf-8'))
en_ui, fk, en_msg = {}, set(), {}
for l in open(os.path.join(HERE, 'work/strings.tsv'), encoding='utf-8'):
    p = l.rstrip('\n').split('\t')
    if p[0].startswith('U'):
        t = p[1]
        if t.startswith('[F8] '): fk.add(p[0]); t = t[5:]
        en_ui[p[0]] = unesc(t)
    elif p[0].startswith('M'): en_msg[p[0]] = (p[1], unesc(p[2]))
code, name = sys.argv[1], sys.argv[2]
tr = {}
# 2026-11-16 に足した文（表計算のマクロなど）: work/extra_msg.tsv の "N001<TAB>msg.phrase<TAB>英語"
extra = []
xp = os.path.join(HERE, 'work/extra_msg.tsv')
if os.path.exists(xp):
    for l in open(xp, encoding='utf-8'):
        p = l.rstrip('\n').split('\t')
        if len(p) == 3 and p[0].startswith('N'): extra.append((p[0], p[1], unesc(p[2])))
srcs = [os.path.join(HERE, 'work/%s.tsv' % code), os.path.join(HERE, 'work/%s_msg.tsv' % code)]
for l in (x for f in srcs if os.path.exists(f) for x in open(f, encoding='utf-8')):
    l = l.rstrip('\n')
    if not l or l.startswith('#') or '\t' not in l: continue
    k, v = l.split('\t', 1)
    # テキスト面は結合記号を前の字に重ねない（1 つが 1 桁になる）。NFC で合成済みの字にし、残る記号（ヨルバ語の ọ̀ の声調など）は外す
    v = ''.join(c for c in unicodedata.normalize('NFC', unesc(v)) if not unicodedata.combining(c))
    tr[k.strip()] = v
out = ['# sgnano filer strings: %s (2026-11-17). ui <TAB> Japanese <TAB> translation / msg.* <TAB> English <TAB> translation' % name,
       '# status: unreviewed (machine translation, not checked by a native speaker; 2026-11-17). 未検証: ネイティブの確認をしていない仮の訳',
       '@lang %s' % code, '@name %s' % name]
bad = miss = 0
for i, ja in enumerate(keys['ui']):
    k = 'U%03d' % (i + 1)
    en = en_ui[k]
    t = tr.get(k)
    if t is None: miss += 1; t = en
    if PCT.findall(t) != PCT.findall(en): print('%s %s: %% differs, English used: %r' % (code, k, t)); bad += 1; t = en
    if k in fk and cells(t) > 8: print('%s %s: F-key label over 8 cells, English used: %r' % (code, k, t)); bad += 1; t = en
    out.append('ui\t%s\t%s' % (esc(ja), esc(t)))
seen = set()
for k, kind, en in [('M%03d' % (i + 1), kind, en) for i, (kind, en) in enumerate(keys['msg'])] + extra:
    t = tr.get(k)
    if t is None: miss += 1; continue
    if kind == 'msg.pattern':          # 書き出しの文: 訳は残りを入れる %s を 1 つだけ持つ
        if '%s' not in en:
            # 英語の pattern は「頭」だけ（例 'saved '）。訳には後ろの %s を足す（既存の言語と同じ形）
            if t.replace('%s', '').count('%'): t = en
            if t.count('%s') != 1:
                t = (t.rstrip() + ' %s') if t.strip() else en + '%s'
        elif t.count('%s') != 1 or t.replace('%s', '').count('%'):
            print('%s %s: a pattern needs one %%s, English used' % (code, k)); bad += 1; t = en
    elif kind != 'msg.word' and PCT.findall(t) != PCT.findall(en): print('%s %s: %% differs, English used: %r' % (code, k, t)); bad += 1; t = en
    if (kind, en) in seen: continue    # 同じ英語は先の訳だけ
    seen.add((kind, en))
    out.append('%s\t%s\t%s' % (kind, esc(en), esc(t)))
open(os.path.join(LOC, '%s.txt' % code), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('wrote %s.txt: %d lines, missing %d, fixed %d' % (code, len(out), miss, bad))
