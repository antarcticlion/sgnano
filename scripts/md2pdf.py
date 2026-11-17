#!/usr/bin/env python3
"""Markdown（このプロジェクトの文書で使う範囲）を A4 縦の PDF にする（2026-10-06、申し送り書のため）。

    python3 scripts/md2pdf.py 入力.md 出力.pdf

扱う書き方: # 表題、## 章、### 節、段落、- 箇条書き（2 字下げで入れ子）、1. 番号つき、| 表 |、``` コード ```、---（区切り）、
**太字**、`コード`。フォントは make_report.py と同じ Noto（docs/fonts/）。
【注意】Noto Sans Mono に日本語の字形は無いので、日本語を含む `コード` は本文の書体で出す。
"""
import os
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Preformatted, Spacer, Table,
                                TableStyle, KeepTogether)

FONTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'fonts')
pdfmetrics.registerFont(TTFont('JP', os.path.join(FONTDIR, 'NotoSansJP-Regular.ttf')))
pdfmetrics.registerFont(TTFont('JPB', os.path.join(FONTDIR, 'NotoSansJP-Bold.ttf')))
pdfmetrics.registerFont(TTFont('JPM', os.path.join(FONTDIR, 'NotoSansMono-Regular.ttf')))
registerFontFamily('JP', normal='JP', bold='JPB', italic='JP', boldItalic='JPB')

ACCENT = colors.HexColor('#1f4e79')
LIGHT = colors.HexColor('#dce6f1')
LIGHT2 = colors.HexColor('#f2f6fb')
GRID = colors.HexColor('#9fb6cd')


def S(name, **kw):
    base = dict(fontName='JP', fontSize=9, leading=13.5, alignment=TA_LEFT, textColor=colors.HexColor('#202020'),
                wordWrap='CJK')                    # 日本語は文字の間で折り返す（既定は空白の位置だけ）
    base.update(kw)
    return ParagraphStyle(name, **base)


st_title = S('t', fontName='JPB', fontSize=19, leading=26, textColor=ACCENT, spaceAfter=6)
st_h1 = S('h1', fontName='JPB', fontSize=13, leading=18, textColor=colors.white, backColor=ACCENT,
          borderPadding=(3, 4, 3, 4), spaceBefore=10, spaceAfter=6)
st_h2 = S('h2', fontName='JPB', fontSize=10.5, leading=15, textColor=ACCENT, spaceBefore=7, spaceAfter=3)
st_p = S('p', spaceAfter=4)
st_li = S('li', spaceAfter=1.5)
st_cell = S('c', fontSize=8, leading=11)
st_cellh = S('ch', fontName='JPB', fontSize=8, leading=11, textColor=ACCENT)
st_code = S('code', wordWrap=None, fontName='JPM', fontSize=7.8, leading=10.5, backColor=LIGHT2, borderPadding=4, spaceAfter=5)


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def inline(t):
    """**太字** と `コード` を reportlab の書き方に（ほかは文字として逃がす）"""
    out, pos = [], 0
    for m in re.finditer(r'`([^`]+)`|\*\*(.+?)\*\*', t):
        out.append(esc(t[pos:m.start()]))
        if m.group(1) is not None:
            c = m.group(1)
            font = 'JPM' if all(ord(ch) < 128 for ch in c) else 'JP'
            out.append('<font name="%s" color="#7a2e0e">%s</font>' % (font, esc(c)))
        else:
            out.append('<b>%s</b>' % inline(m.group(2)))
        pos = m.end()
    out.append(esc(t[pos:]))
    return ''.join(out)


def join(a, b):
    """折り返した行をつなぐ。日本語どうしは空白を入れない（入れると、そこで改行されて行が短く切れる）"""
    if not a:
        return b
    if ord(a[-1]) < 128 and ord(b[0]) < 128:
        return a + ' ' + b
    return a + b


def table(rows, width):
    head, body = rows[0], rows[1:]
    n = len(head)
    data = [[Paragraph(inline(c), st_cellh) for c in head]]
    for r in body:
        r = (r + [''] * n)[:n]
        data.append([Paragraph(inline(c), st_cell) for c in r])
    # 列の幅: 中身の長さに比例（短い列が潰れないよう下限を付ける）
    lens = [max(len(re.sub(r'[`*]', '', r[i])) if i < len(r) else 0 for r in [head] + body) for i in range(n)]
    lens = [max(6, min(l, 60)) for l in lens]
    tot = sum(lens)
    cw = [width * l / tot for l in lens]
    t = Table(data, colWidths=cw, repeatRows=1)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), LIGHT),
        ('GRID', (0, 0), (-1, -1), 0.4, GRID),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 3), ('RIGHTPADDING', (0, 0), (-1, -1), 3),
        ('TOPPADDING', (0, 0), (-1, -1), 2), ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
    ]))
    return t


def convert(src, out):
    lines = open(src, encoding='utf-8').read().splitlines()
    page = A4
    margin = 16 * mm
    width = page[0] - 2 * margin
    flow, title = [], ''
    i = 0
    para = []

    def flush_para():
        if para:
            text = ''
            for ln in para:
                text = join(text, ln)
            flow.append(Paragraph(inline(text), st_p))
            para.clear()

    while i < len(lines):
        ln = lines[i]
        if ln.startswith('```'):                            # コード
            flush_para()
            j = i + 1
            code = []
            while j < len(lines) and not lines[j].startswith('```'):
                code.append(lines[j]); j += 1
            flow.append(Preformatted('\n'.join(code), st_code))
            i = j + 1
            continue
        if ln.startswith('|'):                              # 表
            flush_para()
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-{2,}:?', c) for c in cells):
                    rows.append(cells)
                i += 1
            flow.append(table(rows, width))
            flow.append(Spacer(1, 4))
            continue
        m = re.match(r'^(#{1,3}) (.*)', ln)
        if m:
            flush_para()
            lvl, text = len(m.group(1)), m.group(2)
            if lvl == 1:
                title = text
                flow.append(Paragraph(inline(text), st_title))
            elif lvl == 2:
                flow.append(Paragraph(inline(text), st_h1))
            else:
                flow.append(KeepTogether([Paragraph(inline(text), st_h2)]))
            i += 1
            continue
        m = re.match(r'^( *)(- |\d+\. )(.*)', ln)
        if m:                                               # 箇条書き（続きの行は字下げで続く）
            flush_para()
            indent = len(m.group(1)) // 2
            text = m.group(3)
            j = i + 1
            while j < len(lines) and lines[j].startswith(' ' * (len(m.group(1)) + 2)) and not re.match(r'^ *(- |\d+\. )', lines[j]):
                text = join(text, lines[j].strip()); j += 1
            bullet = '•' if m.group(2) == '- ' else m.group(2).strip()
            st = ParagraphStyle('li%d' % indent, parent=st_li, leftIndent=10 + indent * 12, bulletIndent=indent * 12)
            flow.append(Paragraph(inline(text), st, bulletText=bullet))
            i = j
            continue
        if ln.strip() == '---':
            flush_para()
            flow.append(Spacer(1, 3))
            i += 1
            continue
        if not ln.strip():
            flush_para()
            i += 1
            continue
        para.append(ln.strip())
        i += 1
    flush_para()

    def on_page(c, doc):
        c.setFont('JP', 7.5)
        c.setFillColor(colors.HexColor('#777777'))
        c.drawString(margin, 9 * mm, title)
        c.drawRightString(page[0] - margin, 9 * mm, '%d' % doc.page)

    doc = BaseDocTemplate(out, pagesize=page, leftMargin=margin, rightMargin=margin, topMargin=14 * mm,
                          bottomMargin=16 * mm, title=title, author='sgnano')
    frame = Frame(margin, 16 * mm, width, page[1] - 30 * mm, id='f', leftPadding=0, rightPadding=0, topPadding=0,
                  bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id='p', frames=[frame], onPage=on_page)])
    doc.build(flow)
    print('wrote %s (%d pages)' % (out, doc.page))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: md2pdf.py input.md output.pdf')
    convert(sys.argv[1], sys.argv[2])
