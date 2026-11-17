# 言語ごとの訳（lang_<code>.py: UI = {英語: 訳}、PHRASE / PREFIX / PATTERN / WORD = {英語: 訳}）から resources/locale/<code>.txt を作る
import sys, os, importlib, unicodedata
sys.path.insert(0, os.path.dirname(__file__))
from ui_tr import UI as JA_UI
import msg_ko
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
def esc(s): return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n')
def unesc(s): return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
keys = [unesc(l.split('\t')[1]) for l in open(ROOT + '/resources/locale/template.txt', encoding='utf-8') if l.startswith('ui\t')]
def cells(s): return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in s)
FKEYS = [k for k in keys if JA_UI.get(k, ('',))[0][:2].strip().isdigit() and len(JA_UI[k][0]) <= 8 and ' ' not in JA_UI[k][0][3:] and k not in ('日',)]
for code in sys.argv[1:]:
    m = importlib.import_module('lang_' + code)
    out = ['# sgnano filer strings: %s (2026-10-25). ui <TAB> Japanese <TAB> translation / msg.* <TAB> English <TAB> translation' % m.NAME,
           '# status: unreviewed (machine translation, not checked by a native speaker; 2026-10-25). 未検証: ネイティブの確認をしていない仮の訳',
           '@lang %s' % code, '@name %s' % m.NAME]
    miss = 0
    for k in keys:
        en = JA_UI[k][0]
        if en not in m.UI: print(code, 'missing ui', repr(en)); miss += 1; continue
        t = m.UI[en]
        if k in FKEYS and cells(t) > 8: print(code, 'fkey too wide', repr(t))
        out.append('ui\t%s\t%s' % (esc(k), esc(t)))
    for kind, src in (('phrase', msg_ko.PHRASE), ('prefix', msg_ko.PREFIX), ('pattern', msg_ko.PATTERN), ('word', msg_ko.WORD)):
        d = getattr(m, kind.upper())
        for a in src:
            if a not in d: print(code, 'missing msg.%s' % kind, repr(a)); miss += 1; continue
            out.append('msg.%s\t%s\t%s' % (kind, esc(a), esc(d[a])))
    for en in m.UI:
        if en not in [JA_UI[k][0] for k in keys]: print(code, 'unknown ui', repr(en))
    open(ROOT + '/resources/locale/%s.txt' % code, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('wrote', code, len(out), 'missing', miss)
