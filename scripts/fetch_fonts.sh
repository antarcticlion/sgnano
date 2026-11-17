#!/usr/bin/env bash
# レポート用の Noto フォント（SIL OFL 1.1）を取得し、静的インスタンスへ変換して docs/fonts/ に置く。
# reportlab は CFF アウトライン（Noto Sans CJK の .ttc）を読めないので、
# Google Fonts の可変 TrueType から wght を固定したものを作る。
set -eu
cd "$(dirname "$0")/.."
mkdir -p docs/fonts
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
base=https://github.com/google/fonts/raw/main/ofl
curl -sL -o "$tmp/jp.ttf"   "$base/notosansjp/NotoSansJP%5Bwght%5D.ttf"
curl -sL -o "$tmp/mono.ttf" "$base/notosansmono/NotoSansMono%5Bwdth,wght%5D.ttf"
curl -sL -o docs/fonts/OFL.txt "$base/notosansjp/OFL.txt"
python3 - "$tmp" <<'PY'
import sys, os
from fontTools import ttLib
from fontTools.varLib import instancer
tmp = sys.argv[1]
for src, axes, dst in [('jp.ttf',   {'wght': 400},             'NotoSansJP-Regular.ttf'),
                       ('jp.ttf',   {'wght': 700},             'NotoSansJP-Bold.ttf'),
                       ('mono.ttf', {'wght': 400, 'wdth': 100},'NotoSansMono-Regular.ttf')]:
    f = ttLib.TTFont(os.path.join(tmp, src))
    instancer.instantiateVariableFont(f, axes, inplace=True, updateFontNames=True)
    f.save(os.path.join('docs/fonts', dst))
    print(dst)
PY
