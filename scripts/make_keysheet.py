#!/usr/bin/env python3
"""キー操作のチートシート（PDF）を作る。

    python3 scripts/make_keysheet.py [出力先.pdf]     既定は docs/sgnano_keys.pdf

キーの一覧は**ソースから読む**（src/app/keys.c と keys_usb.c の表、lrdemo_key() と audiotest_key() の case）。
説明文だけをこのファイルの DESC に書く。次のときはエラーで止まる:
  - ソースにあるのに説明が無いキー（キーを足したらここにも書く）
  - 説明があるのにソースに無いキー（キーを消したらここからも消す）
キーは「表 -> ローレゾのデモ -> 音源の試験」の順に渡る（app_handle_key()）。先に拾われて**届かない**キーは
自動で見つけて、灰色で注記する。

フォントは make_report.py と同じ Noto（docs/fonts/、scripts/fetch_fonts.sh で取得）。
【注意】Noto Sans Mono に日本語グリフは無いので、等幅（キーの欄）には ASCII だけを渡す。
"""
import os
import re
import sys
import datetime

from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Table, TableStyle,
                                Spacer, KeepTogether)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
FONTDIR = os.path.join(ROOT, 'docs', 'fonts')
pdfmetrics.registerFont(TTFont('JP',  os.path.join(FONTDIR, 'NotoSansJP-Regular.ttf')))
pdfmetrics.registerFont(TTFont('JPB', os.path.join(FONTDIR, 'NotoSansJP-Bold.ttf')))
pdfmetrics.registerFont(TTFont('JPM', os.path.join(FONTDIR, 'NotoSansMono-Regular.ttf')))


# ---- ソースからキーを集める ----
# 修飾キーつき（2026-10-18、ファイラーの一覧）: S_( ) = Shift、C_( ) = Ctrl、A_( ) = Alt。入れ子で組み合わせる（S_(C_(KEY_F(1)))）
KEYTOK = r"((?:[SCA]_\()+(?:'(?:\\.|[^'\\])'|KEY_F\(\d+\)|KEY_[A-Z0-9_]+)\)+|'(?:\\.|[^'\\])'|0x[0-9A-Fa-f]+|KEY_SHIFT_F\(\d+\)|KEY_F\(\d+\)|KEY_[A-Z0-9_]+)"
MODBIT = {'S': 0x100, 'C': 0x200, 'A': 0x400}

def keycodes():
    """src/input/keycode.h の #define KEY_X 値（2026-10-05、ファイラーの特殊キー）"""
    d = {}
    for m in re.finditer(r'#define\s+(KEY_[A-Z0-9_]+)\s+(\S+)', read('src/input/keycode.h')):
        v = m.group(2)
        mf = re.match(r'KEY_F\((\d+)\)', v)
        d[m.group(1)] = 0x80 + int(mf.group(1)) if mf else int(v, 0) if re.match(r'0x|\d', v) else None
    return d

def tok_to_key(t):
    m = re.match(r'(?:[SCA]_\()+', t)
    if m:                                                  # 修飾キーつき: 元のキー | 印（外側のかっこを、付けた数だけ外す）
        pre = re.findall(r'([SCA])_\(', m.group(0))
        return tok_to_key(t[m.end():len(t) - len(pre)]) | sum(MODBIT[c] for c in pre)
    if t.startswith('0x'):
        return int(t, 16)
    if t.startswith('KEY_SHIFT_F('):                       # Shift+F1..F12 = 0xA1..0xAC（2026-10-09）
        return 0xA0 + int(t[12:-1])
    if t.startswith('KEY_F('):
        return 0x80 + int(t[6:-1])
    if t.startswith('KEY_') and t not in keycodes():   # 外側の if の閉じかっこまで拾ったとき
        t = t.rstrip(')')
    if t.startswith('KEY_'):
        return keycodes()[t]
    body = t[1:-1]
    if body.startswith('\\'):
        return {'\\\\': ord('\\'), "\\'": ord("'"), '\\"': ord('"'), '\\n': 10}[body]
    return ord(body)

def read(p):
    return open(os.path.join(ROOT, p), encoding='utf-8').read()

def table_keys(path, table):
    """static const app_key_t <table>[] = { { key, arg, fn }, ... }; のキーを順に返す"""
    s = read(path)
    m = re.search(r'static const app_key_t\s+%s\[\]\s*=\s*\{(.*?)\n\};' % table, s, re.S)
    if not m:
        sys.exit('table %s not found in %s' % (table, path))
    return [tok_to_key(k) for k in re.findall(r'\{\s*' + KEYTOK + r'\s*,\s*\d+\s*,\s*k_\w+\s*\}', m.group(1))]

def func_cases(path, signature):
    """関数の本体（次のトップレベルの関数まで）にある case のキーを返す"""
    s = read(path)
    i = s.find(signature)
    if i < 0:
        sys.exit('%s not found in %s' % (signature, path))
    j = s.find('\n}', i)
    body = s[i:j]
    toks = re.findall(r'(?:case\s+|key\s*==\s*|rich\s*==\s*)' + KEYTOK, body)   # case X: と key / rich == X
    return list(dict.fromkeys(tok_to_key(k) for k in toks))

def range_cases(path, start, end):
    """start の行から end の行までにある case のキーを返す（いくつかの関数に分けたキーの受け口。2026-10-17 のファイラー）"""
    s = read(path)
    i = s.find(start)
    j = s.find(end, i)
    if i < 0 or j < 0:
        sys.exit('%s .. %s not found in %s' % (start, end, path))
    toks = re.findall(r'(?:case\s+|key\s*==\s*|rich\s*==\s*)' + KEYTOK, s[i:j])
    return list(dict.fromkeys(tok_to_key(k) for k in toks))

GROUPS = [   # (見出し, キーの出どころ)。テスト用アプリ（映像・ローレゾ・音源・診断の表）は 2026-10-17 にビルドから外したので載せない
    ('ファイラー（起動直後）', lambda: range_cases('src/filer/filer.c', '// ---- キー（2026-10-17', '// ---- キーここまで')),
    ('ビュアー（テキスト・ダンプ）', lambda: func_cases('src/filer/ftext.c', 'bool ftext_key(')),
]
DISPATCH = []


# ---- 説明（ここだけ手で書く）。★ はよく使うキー ----
DESC = {
    'ファイラー（起動直後）': {
        0x90: '★ カーソルを上へ', 0x91: '★ カーソルを下へ', 0x92: '左の列へ（26 項目戻る。ヘルプ・属性の見本では前のページ、削除の確かめでは「はい」）', 0x93: '右の列へ（26 項目進む。ヘルプ・属性の見本では次のページ、削除の確かめでは「いいえ」）',
        0x94: '前のページ', 0x95: '次のページ', 0x96: '★ 全部に印（FD の Home。1 つでも外れていれば全部に、全部付いていれば外す）', 0x97: '末尾へ',
        0x296: '先頭へ（Ctrl+Home）', 0x297: '末尾へ（Ctrl+End）',
        0x0D: '★ 開く（フォルダに入る / .png 画像 / .txt テキスト / .rb .mrb は Ruby で実行（ESC で止める） / ほかはバイナリダンプ / CD のトラックはモード 7 のスペクトログラムで再生。再生中は止める。削除の確かめでは「はい」）',
        0x09: '★ 印（*）を付ける・外す（カーソルは動かさない。FD の Tab）。削除の確かめでは「はい / いいえ」を切り替える',
        0x4E: '削除の確かめ: 消さない（n と同じ）',
        ' ': '★ 印（赤い *）を付ける・外して次の項目へ。Shift で範囲を選んでいれば、その範囲に印を付ける。CD の再生中は止める',
        'q': 'CD の再生を止める', 'Q': 'CD の再生を止める',
        0x08: '★ 上のフォルダへ',
        'l': '★ ドライブを選ぶ（USB メモリ・フロッピー・CD・S: 内蔵）', 0x89: 'L と同じ（ドライブを選ぶ）',
        0x85: '★ 名前を変える（F5）',
        'c': '★ コピー（F3）: 印（Space）の付いたもの。無ければ範囲（Shift+矢印）、それも無ければカーソルの項目（フォルダは中身ごと）。行き先はドライブとフォルダの木から（←→ ドライブ、↑↓ フォルダ、Enter 決める）。ESC で止める',
        'm': '★ 移動（Shift+F3）: コピーと同じ選び方。写せたものから元を消す',
        'd': '★ 削除（F4）: y で確かめる。印・範囲をまとめて。フォルダは中身ごと（FAT・exFAT・NTFS）',
        'r': '★ 名前を変える（F5）: 今の名前を直して Enter。同じフォルダの中だけ、同じ名前があれば断る',
        'a': '★ 属性を変える（Shift+F1）: 窓で 読み出し専用・隠し・システム・アーカイブ を R / H / S / A か Space で切り替え、Enter で書く',
        'e': '★ テキストエディタで開く（Shift+F8。MIFES 風。Ctrl-Space / F12 で IME、F2 保存、F10 / ESC 閉じる）',
        'v': '★ テキストで表示（Shift+F9）。Shift+V は 16 進',
        'i': 'ドライブの情報（Shift+F2。USB の文字列・INQUIRY・VPD・4K セクタか。HDD は ATA の IDENTIFY）',
        'k': '★ フォルダを作る（Shift+F5）。名前を打って Enter',
        'n': '★ 新しいファイル（0 バイト）を作る（Ctrl+F1）。名前を打って Enter。削除の確かめでは「消さない」',
        'h': '★ シェル sgsh（Shift+F6。csh のサブセット。exit / Ctrl-D で戻る、help でコマンド）',
        'j': 'FDD・LS-120・CD の媒体を取り出す（CD の再生中は止めてから）',
        'x': '★ 実行（F2）: カーソルのファイルを開く・実行する（Enter と同じ）',
        0x7F: '★ カーソルのファイルを消す（y で確かめる。フォルダは中身ごと。FAT・exFAT・NTFS）', 'y': '削除の確かめ: 消す', 'Y': '削除の確かめ: 消す',
        0x272: '★ 読み直す（Ctrl+R。CD は媒体を入れ替えたときのために TOC から読み直す）',
        0x176: '16 進のビュアーで開く（Shift+V。拡張子によらない）',
        0x281: '新しいファイル（N と同じ）', 0x282: '新しいフォルダ（K と同じ）', 0x283: '名前を変える（R と同じ）', 0x284: '属性を変える（A と同じ）',
        0x285: 'Ruby の REPL（Alt+I と同じ）', 0x286: 'コピー（C と同じ）', 0x287: '移動（M と同じ）', 0x288: '消す（D と同じ）', 0x289: 'エディタで開く（E と同じ）', 0x28A: '.rb をコンパイル（Alt+M と同じ）', 0x28B: '分割（4MB ずつ）', 0x28C: '結合（.001 から）',
        0x481: 'テキストの属性の見本（Alt+F1）', 0x482: '★ FB（画像）の表示 オン / オフ（Alt+F2）', 0x483: '★ テキスト面の表示 オン / オフ（Alt+F3）',
        0x484: 'モニタの EDID（Alt+F4）', 0x485: '★ 画面の写し（Alt+F5。PNG をいまのフォルダへ）', 0x486: 'FB の表示ページを回す（Alt+F6）',
        0x489: 'ZMODEM で PC から受け取る（Alt+F9 / Alt+R）', 0x48A: 'ZMODEM で PC へ送る（Alt+F10 / Alt+S）', 0x48B: '分割（Alt+F11）', 0x48C: '結合（Alt+F12）',
        0x682: 'FB の表示ページを 0 で消す（Ctrl+Alt+F2）', 0x683: 'FB の全画素の輝度を 1/2 にする（Ctrl+Alt+F3）', 0x685: '読み直す（Ctrl+Alt+F5）', 0x686: 'MicroPython の REPL（Ctrl+Alt+F6）', 0x687: '16 進のビュアー（Ctrl+Alt+F7）', 0x688: 'VGM/VGZ を 96kHz/24bit WAV に書き出す（Ctrl+Alt+F8）', 0x689: 'フォント ROM のライセンス（Ctrl+Alt+F9）', 0x68A: 'ADC のステレオ入力（GP40/41）を鳴らす（Ctrl+Alt+F10）', 0x488: '設定（表示の言語・IME・キーボード。Alt+F8）',
        0x67F: '再起動（Ctrl+Alt+Del / Shift+F12）',
        0x469: 'Ruby の REPL（Alt+I / Ctrl+F5）', 0x46D: '.rb をコンパイルして .mrb を書き出す（Alt+M / Ctrl+F10）', 0x470: 'MicroPython の REPL（Alt+P / Ctrl+Alt+F6）', 0x472: 'ZMODEM で PC から受け取る（Alt+R / Alt+F9）', 0x473: 'ZMODEM で PC へ送る（Alt+S / Alt+F10）',
        0x49A: '画面の写し（Alt+PrintScreen / Alt+F5。PNG をいまのフォルダへ）',
        0x81: '★ ヘルプ（F1）', 0x82: '★ 実行（F2。画像の表示中は FB の表示 オン/オフ）', 0x83: '★ コピー（F3。画像の表示中はテキスト面の表示 オン/オフ）',
        0x84: '★ 削除（F4）', 0x85: '★ 名前を変える（F5）', 0x86: 'FB の表示ページを回す（画像の表示中。一覧では未割り当て）', 0x87: 'FB を 0 で消す', 0x88: 'FB の明るさを 1/2 にする（RGB555）', 0x8A: 'USB のエンドポイントと LAN の状態（F10）',
        0x8B: '時計（F11。NTP で合わせた日本時間。s ですぐ合わせる）', 0x8C: '表計算 SGCALC（F12）',
        0xA1: '属性を変える（Shift+F1。画像の表示中は属性の見本）', 0xA2: 'ドライブの情報（Shift+F2。画像の表示中は FB を消す）', 0xA3: '移動（Shift+F3。画像の表示中は FB を 1/2 の明るさに）', 0xA4: 'フォルダを削除（Shift+F4。画像の表示中は EDID）',
        0x9B: '★ コンテキストメニュー（カーソルの項目にできる操作を小さな窓に。上下で選ぶ・Enter で決定・ESC でやめる。中身は S:/SystemSettings/ContextMenu.cfg）', 0x20D: 'コンテキストメニュー（メニューキーと同じ）',
        0xAA: 'S: ドライブのエラー検査（Shift+F10）',
        0xA5: 'フォルダを作る（Shift+F5）', 0xA6: 'シェル sgsh（Shift+F6）', 0xA7: 'フォント ROM のライセンス（画像の表示中。一覧では未割り当て）', 0xA8: 'エディタで開く（Shift+F8）', 0xA9: 'テキストで表示（Shift+F9）', 0xAB: 'トラッカー（Shift+F11）', 0xAC: '再起動（Shift+F12）',
        0x190: '範囲を選ぶ（Shift+上）', 0x191: '範囲を選ぶ（Shift+下）', 0x192: '範囲を選ぶ（Shift+左）', 0x193: '範囲を選ぶ（Shift+右）', 0x194: '範囲を選ぶ（Shift+PgUp）', 0x195: '範囲を選ぶ（Shift+PgDn）', 0x196: '★ 印を反転（Shift+Home。FD と同じ）', 0x197: '範囲を選ぶ（Shift+End: 末尾まで）',
        0x1B: '★ 窓を閉じる・選択を解く・FB とテキスト面の表示を元に戻す（サブフォルダでは上位へ）',
    },
    'ビュアー（テキスト・ダンプ）': {
        'q': '★ ファイラーに戻る', 'Q': 'ファイラーに戻る', 0x1B: 'ファイラーに戻る', 0x81: 'ビュアーのヘルプ', 0x99: '検索の欄で IME のオン・オフ（Ctrl+Space）', 0x8C: '検索の欄で IME のオン・オフ', 0xA9: '16 進の表示へ（いま見ている所のまま）', 0x85: '色分けの言語を替える（C/C++ -> mruby -> MicroPython -> SG BASIC -> なし）', 0x89: 'テキストの表示へ（いま見ている所のまま）',
        'j': '★ 1行下へ', 'e': '1行下へ', 0x91: '1行下へ', 0x0D: '1行下へ', 0x0E: '1行下へ', 0x05: '1行下へ',
        'k': '★ 1行上へ', 'y': '1行上へ', 0x90: '1行上へ', 0x10: '1行上へ', 0x19: '1行上へ',
        ' ': '★ 1画面下へ', 'f': '1画面下へ', 'z': '1画面下へ', 0x95: '1画面下へ', 0x06: '1画面下へ', 0x16: '1画面下へ',
        'b': '★ 1画面上へ', 'w': '1画面上へ', 0x94: '1画面上へ', 0x02: '1画面上へ',
        'd': '半画面下へ', 0x04: '半画面下へ', 'u': '半画面上へ', 0x15: '半画面上へ',
        'g': '★ 先頭へ', '<': '先頭へ', 0x96: '先頭へ', 'G': '★ 末尾へ', '>': '末尾へ', 0x97: '末尾へ',
        '/': '★ 前へ検索（パターンを打って Enter。英字の大文字小文字は区別しない）', '?': '後ろへ検索',
        'n': '★ 次を検索', 'N': '逆向きに次を検索', 0x08: '検索のパターンを1文字消す（打っている間。Enter で探す、ESC でやめる）',
    },
    '映像': {
        'v': '★ 画面モードを巡回（0 表示なし / 1 テキスト / 2 +RGB555 / 3 +ローレゾ+CLUT8 / 4 +CLUT4 / 5 +ローレゾ / 6 ローレゾのみ）',
        'D': '★ 表示タイミングを巡回（31 / 24 / 15kHz の12通り）',
        'B': '背景色を巡回',
        't': 'テキスト面の表示 / 非表示（閉じていれば開いてデモを出す）',
        'T': 'テキスト面を全面敷き詰める（合成の最悪条件）',
        'c': 'ローレゾの実機自己検証（SIMD 版と素朴版を全画素比べる）',
        's': '詳細ログの常時表示 オン / オフ',
        'V': '表示経路を作り直す（画面が乱れたときの復帰）',
        0x04: '複合同期（CSYNC）の切り替え（15kHz）',
        0x14: 'テキスト面を開く / 閉じる（閉じると約50KB 空く）',
    },
    'ローレゾ面のデモ': {
        'l': '★ ローレゾ面の表示 / 非表示（閉じていれば開いて中身を入れ直す）',
        'b': 'BG の表示を巡回（BG1 -> BG0 -> 両方 -> なし）',
        'f': 'フォントを巡回',
        'F': 'フォント一覧（16x16）/ スクロールするデモ の切り替え',
        'o': 'オブジェクトのデモ（押すたび個数が増え、最後は消える）',
        'O': 'オブジェクトの負荷試験（64x64 を128個重ねる）',
        'S': 'スクロールを止める / 動かす',
        0x0C: 'ローレゾ面を開く / 閉じる（閉じると約182KB 空く）',
        0x0B: 'ローレゾ面を小さい設定で開き直す（32KB・BG 1面・パレット5本）',
    },
    '音源': {
        '0': '★ 自動メロディ（全ボイス、ボイスごとに違う波形）',
        '7': '★ 1ボイスだけ鳴らす（押すたび v0 -> v5 -> v0。チップごとの確認）',
        '8': 'ボイス1だけ鳴らす',
        '9': '自動メロディ（全ボイス同じ音程・波形）',
        '1': '手動再生: サイン（ボイス1だけ）',
        '2': '手動再生: 三角',
        '3': '手動再生: のこぎり',
        '4': '手動再生: 矩形',
        '5': '手動再生: パルス 25%',
        '6': '手動再生: オルガン',
        0x15: '手動再生の音量を上げる',
        0x19: '手動再生の音量を下げる',
        '-': '手動再生の音量を下げる',
        0x10: '手動再生を半音上げる',
        0x0F: '手動再生を半音下げる',
        '[': '手動再生を半音下げる',
        'k': 'データの MSB を反転',
        'n': 'データの符号を反転',
        'i': 'データ形式 I2S / LSJ の切り替え（正しいのは LSJ）',
        'm': '全ボイスをミュート（ピンを Low に固定。配線の切り分け）',
        'M': 'ミュート解除',
        'A': '固定サンプルレートの試験音（48kHz / 1kHz）',
        'y': '試験音をやめて通常の再生に戻す',
        'C': '出力ピンの自己診断（キャプチャして波形表と照合）',
        'd': '減衰の試験（全ボイス）',
        0x05: '減衰の試験（ボイス1）',
        'q': 'ノートごとのログ オン / オフ',
        'h': '音源のキーの一覧をログに出す',
    },
    'USB 入力（診断）': {
        'U': '★ USB の状態・全機器・エンドポイントを表示',
        'R': '★ USB ホストを作り直す（全機器を列挙し直す）',
        'K': 'キー配列 US / JIS の切り替え',
        'E': 'キーボードの LED を巡回',
        'N': 'マウスの累計移動量を0に戻す',
        'u': 'TinyUSB の RAM ログを出す',
        '&': '引き受け手のいない機器の素性を表示（押すたび次の機器）',
        'Q': '全機器に制御転送を投げて生存を確かめる',
        'G': 'GET_REPORT で状態を1回読む（パッド、無ければマウス）',
        'Z': '割り込み EP の自動の張り直し オン / オフ（止まる機器専用）',
        'z': '割り込み EP を1回張り直す',
        'P': 'NAK 再試行の設定を巡回',
        'x': 'エンドポイントのエラー記録をクリア',
        'H': 'パッドをレポートプロトコルにする',
        ';': 'パッドの出力の経路（割り込み OUT / 制御転送）を切り替え',
        'J': 'DualShock 3 の有効化をやり直す（振動も止める）',
        '/': 'DualShock 3 の LED を巡回',
        ',': 'DualShock 3 の振動を巡回',
        '.': 'DualShock 3 の振動の掃引（デモ）',
        'w': 'パッドの EP のポーリング間隔を巡回',
        'a': 'パッドの EP を入れ直す',
        'Y': 'パッドの IN EP を止める',
        'I': 'パッドに SET_IDLE（128ms）',
        'j': 'パッドに SET_CONFIGURATION',
        'r': 'パッドの EP0 を開き直す',
        'e': 'パッドに制御転送の IN を投げる',
        'g': 'epx でパッドに IN を連続で投げる（終わったら R）',
        'X': 'いちばん静かなパッド以外の割り込み IN を止める（戻すには R）',
    },
    'ストレージ': {
        '%': '★ USB メモリの FAT を一覧（押すたび次のドライブ）',
        '#': 'USB メモリのセクタ0を読む',
        '$': 'USB メモリの状態',
        "'": '★ オーディオ CD を先頭から最後まで再生（10秒分を貯めてから鳴らす。epx がオフなら30秒だけ）',
        '`': 'CD の再生を止める',
        '\\': '★ CD の TOC（トラック一覧）',
        ']': '★ CD の ISO9660 を一覧（音楽 CD では断る）',
        ':': 'CD の LBA 16 を読む（ISO9660 の入口）',
        '!': 'CD の音声セクタを読む（押すたび1秒進む。データ CD では断る）',
        '"': '★ FDD の FAT を一覧',
        '(': 'FDD / 光学ドライブの状態（2台とも）',
        ')': 'FDD / 光学ドライブのセクタ0を読む',
        '=': 'FDD / 光学ドライブを問い合わせ直す',
        0x02: 'CD と USB メモリのデータ段を epx で読む オン（既定）/ オフ。速さの記録も出す',
        0x07: 'USB メモリの読み出しの速さを測る（1MB を 16KB ずつ）',
        0x06: 'USB メモリのルートでいちばん大きいファイルを読む（先頭 4MB、速さと CRC32）',
        0x16: 'USB メモリの PNG を 640x480 に収めてモード2 で表示（押すたびに次の PNG）',
        0x0E: '画面を黒にし、FB を黒で消して次の PNG を読み込み、モード2 で表示',
        0x18: 'USB メモリにフォルダ「sgnano files」を作り、長い名前（日本語を含む）のファイル（約 200KB）を書いて読み返す',
        0x03: 'FDD・光学ドライブを全部いっせいに読み直す（受け場の取り合いの試験）',
        0x0A: 'FDD（LS-120 など）の媒体を取り出す（START STOP UNIT の LoEj）',
        0x1A: 'フロッピーで同じこと（約 20KB、FAT12）',
        0x12: 'Ctrl-X で書いたファイルを長い名前に変えて読み、消し、フォルダも消す（USB メモリ）',
        0x11: 'フロッピーで同じこと（Ctrl-Z のあとに）',
        '~': 'FDD の形状を問い合わせる（MODE SENSE）',
        '|': 'FDD の書式を指定（1.44MB -> 1.2MB -> ... と巡回）',
        '<': 'FDD: ヘッドを0トラックへ戻す',
        '>': 'FDD: セクタ0へシーク',
        '?': 'FDD: セクタ0を読めるか確かめる（VERIFY）',
        '@': 'FDD: 判定を無視してセクタ0を読む',
        '+': 'FDD: モーターを回す',
        '_': 'FDD: モーターを止める',
        '^': 'FDD: READ を連打（モーター音の確認）',
        '*': 'FDD: 畳みかけて読む（モーターが止まる前に）',
        '{': 'FDD: メディアをロックして読む',
        '}': 'FDD: ロックを解除',
    },
    '試験・診断': {
        0x01: '表示用メモリ（アリーナ）の一覧と見張りの確認',
        0x17: 'アプリの作業領域（app_alloc）の試験',
        0x13: 'モニタの EDID を DDC（PIO2 の I2C）で読み直してログに出す',
        'W': 'わざと止める（ウォッチドッグで再起動する）',
        'p': 'アプリ時間の PSRAM 書き込み試験の量を巡回',
        'L': 'フレームの開始をわざと遅らせる量を巡回',
    },
}


def tstyle(styles, lo, hi):
    """行 lo..hi-1 の表の体裁（styles の行番号はずらして当てる）"""
    base = [
        ('FONT', (0, 0), (0, -1), 'JPM', 8.5),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TOPPADDING', (0, 0), (-1, -1), 0.5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0.5),
        ('LEFTPADDING', (0, 0), (-1, -1), 2),
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#eef2f7')),
        ('LINEBELOW', (0, 0), (-1, -1), 0.25, colors.HexColor('#dddddd')),
    ]
    for cmd, (c0, r0), (c1, r1), v in styles:
        if lo <= r0 < hi:
            base.append((cmd, (c0, r0 - lo), (c1, r1 - lo), v))
    return base


def norm(k):
    return ord(k) if isinstance(k, str) else k

NAMED = {0x0D: 'Enter', 0x08: 'BS', 0x09: 'Tab', 0x1B: 'ESC', 0x7F: 'Del', 0x90: 'Up', 0x91: 'Down', 0x92: 'Left',
         0x93: 'Right', 0x94: 'PgUp', 0x95: 'PgDn', 0x96: 'Home', 0x97: 'End', 0x98: 'Ins', 0x9A: 'PrintScreen', 0x9B: 'Menu'}

def key_label(k):
    if k >= 0x100:                                         # 修飾キーつき（2026-10-18）
        pre = ''.join(n for b, n in ((0x100, 'Shift+'), (0x200, 'Ctrl+'), (0x400, 'Alt+')) if k & b)
        base = k & 0xFF
        return pre + (chr(base).upper() if ord('a') <= base <= ord('z') else key_label(base))
    if k in NAMED:
        return NAMED[k]
    if 0x81 <= k <= 0x8C:
        return 'F%d' % (k - 0x80)
    if 0xA1 <= k <= 0xAC:
        return 'Shift+F%d' % (k - 0xA0)
    if k < 0x20:
        return 'Ctrl-' + chr(k + 0x40)
    return {0x20: 'Space', ord('\\'): '\\'}.get(k, chr(k))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'docs', 'sgnano_keys.pdf')
    src = {name: fn() for name, fn in GROUPS}
    desc = {g: {norm(k): v for k, v in d.items()} for g, d in DESC.items()}

    # 突き合わせ: ソースと説明が食い違えば止める
    errors = []
    for g, keys in src.items():
        for k in keys:
            if k not in desc.get(g, {}):
                errors.append('%s: key %r (0x%02x) has no description' % (g, key_label(k), k))
        for k in desc.get(g, {}):
            if k not in keys:
                errors.append('%s: description for %r but the key is not in the source' % (g, key_label(k)))
    if errors:
        sys.exit('\n'.join(errors))

    # 届かないキー: 振り分けの順で先のグループが同じキーを拾う
    owner = {}
    for g in DISPATCH:
        for k in src[g]:
            owner.setdefault(k, g)
    shadowed = {(g, k): owner[k] for g in DISPATCH for k in src[g] if owner[k] != g}

    # ---- PDF ----
    st_h = ParagraphStyle('h', fontName='JPB', fontSize=9.5, leading=12, textColor=colors.HexColor('#1f3a5f'),
                          spaceBefore=3, spaceAfter=1)
    st_d = ParagraphStyle('d', fontName='JP', fontSize=6.2, leading=7.4)   # 【2026-10-05】7.0 -> 6.2（4段で1枚に）
    st_dx = ParagraphStyle('dx', parent=st_d, textColor=colors.HexColor('#999999'))
    st_note = ParagraphStyle('n', fontName='JP', fontSize=6.6, leading=8.4, textColor=colors.HexColor('#444444'))

    page = landscape(A4)
    margin = 8 * mm
    title_h = 9 * mm
    ncol = 4                    # 【2026-10-05】3 -> 4（ファイラーとビュアーのキーで2ページになった）
    gap = 4 * mm
    colw = (page[0] - 2 * margin - (ncol - 1) * gap) / ncol
    kw = 18 * mm
    cw = [kw, colw - kw]
    flow = []
    total = 0
    st_k = ParagraphStyle('k', fontName='JPM', fontSize=6.6, leading=8.0)
    for g, _ in GROUPS:
        rows, styles = [], []
        # 同じ説明のキーは1行にまとめる（2026-10-05、ビュアーは同じ働きのキーが多い）。★ はまとめたどれかに付いていれば付ける
        merged = {}
        for k in src[g]:
            text = desc[g][k]
            base = text[1:].strip() if text.startswith('★') else text
            if base in merged and (g, k) not in shadowed:
                merged[base][0].append(k); merged[base][1] |= text.startswith('★')
            else:
                merged.setdefault(base if (g, k) not in shadowed else (base, k), [[k], text.startswith('★')])
        for key_text, (ks, star) in merged.items():
            k = ks[0]
            text = key_text if isinstance(key_text, str) else key_text[0]
            if (g, k) in shadowed:
                p = Paragraph('%s <font size="6">（届かない: %s の同じキーが先に拾う）</font>' % (text, shadowed[(g, k)]),
                              st_dx)
                styles.append(('TEXTCOLOR', (0, len(rows)), (0, len(rows)), colors.HexColor('#aaaaaa')))
            else:
                p = Paragraph(('<font name="JPB">%s</font>' % text) if star else text, st_d)
            rows.append([Paragraph(' '.join(key_label(x) for x in ks), st_k), p])
            total += len(ks)
        # 表は段をまたいで分けてよい（分けないと段の下に大きな空きができて2ページになった）。
        # 見出しだけが段の末尾に取り残されないよう、見出しと最初の3行はまとめる
        head, rest = rows[:3], rows[3:]
        t1 = Table(head, colWidths=cw); t1.setStyle(TableStyle(tstyle(styles, 0, len(head))))
        flow.append(KeepTogether([Paragraph(g, st_h), t1]))
        if rest:
            t2 = Table(rest, colWidths=cw, splitByRow=1)
            t2.setStyle(TableStyle(tstyle(styles, len(head), len(rows))))
            flow.append(t2)
        flow.append(Spacer(1, 1.5 * mm))

    today = datetime.date.today().isoformat()
    flow.append(Paragraph(
        '<font name="JPB">使い方</font>: 起動直後はファイラー。<b>F10</b> でテスト用アプリ（「映像」以降のキー。'
        'モード5・デモ・試験のメロディ）と行き来する。'
        'USB キーボードと UART コンソール（scripts/console.sh -k、特殊キーは {UP} {F1} のように書く）のどちらから押しても同じ。'
        '記号は「文字」として届くので、US / JIS どちらの配列でもその文字を打てばよい。Ctrl-X は Ctrl を押しながら X。'
        '<b>太字</b>はよく使うキー。灰色は、振り分けの順（表 -> ローレゾのデモ -> 音源）で先に別の処理が拾うため届かないキー。'
        'このシートはソースから作っている（scripts/make_keysheet.py、%s 時点、%u キー）。' % (today, total), st_note))

    frames = [Frame(margin + i * (colw + gap), margin, colw, page[1] - 2 * margin - title_h,
                    leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0, id='c%d' % i) for i in range(ncol)]

    def on_page(c, doc):
        c.setFont('JPB', 13)
        c.setFillColor(colors.HexColor('#1f3a5f'))
        c.drawString(margin, page[1] - margin - 5 * mm, 'sgnano キー操作 チートシート')
        c.setFont('JP', 7.5)
        c.setFillColor(colors.HexColor('#666666'))
        c.drawRightString(page[0] - margin, page[1] - margin - 5 * mm, '%s 時点' % today)

    doc = BaseDocTemplate(out, pagesize=page, leftMargin=margin, rightMargin=margin, topMargin=margin,
                          bottomMargin=margin, title='sgnano key cheat sheet', author='sgnano')
    doc.addPageTemplates([PageTemplate(id='p', frames=frames, onPage=on_page)])
    doc.build(flow)
    print('wrote %s (%u keys, %u not reachable)' % (out, total, len(shadowed)))
    for (g, k), o in sorted(shadowed.items(), key=lambda x: x[0][0]):
        print('  not reachable: %s %r (taken by %s)' % (g, key_label(k), o))


if __name__ == '__main__':
    main()
