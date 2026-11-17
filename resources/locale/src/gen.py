import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from ui_tr import UI
import msg_ko
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
def esc(s): return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n')
keys = [l.split('\t')[1] for l in open(ROOT + '/resources/locale/template.txt', encoding='utf-8') if l.startswith('ui\t')]
def unesc(s): return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
keys = [unesc(k) for k in keys]
for code, name, idx in (('en', 'English', 0), ('ko', '한국어', 1)):
    out = ['# sgnano filer strings: %s (2026-10-25). ui <TAB> Japanese <TAB> translation / msg.* <TAB> English <TAB> translation' % name,
           '@lang %s' % code, '@name %s' % name]
    for k in keys:
        if k not in UI: print(code, 'MISSING', repr(k)); continue
        out.append('ui\t%s\t%s' % (esc(k), esc(UI[k][idx])))
    if code == 'ko':
        for kind, d in (('phrase', msg_ko.PHRASE), ('prefix', msg_ko.PREFIX), ('pattern', msg_ko.PATTERN), ('word', msg_ko.WORD)):
            for a, b in d.items(): out.append('msg.%s\t%s\t%s' % (kind, esc(a), esc(b)))
    open(ROOT + '/resources/locale/%s.txt' % code, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('wrote', code, len(out))
