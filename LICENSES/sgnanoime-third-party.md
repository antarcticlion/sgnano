# 第三者のソフトウェア・辞書

`sgnanoime` は次の第三者のデータを使う（または使う予定）。配布物には、
それぞれのライセンス全文と著作権表示を含める。

## いま含まれているもの

### UniDic（現代書き言葉 / 話し言葉 UniDic CWJ / CSJ 2025.12）

- 著作権: 国立国語研究所（NINJAL） / UniDic Consortium
- ライセンス: GPL v2 / LGPL v2.1 / 修正 BSD の三重。本プロジェクトは
  修正 BSD を選ぶ。
- 全文: `license/UniDic-BSD.txt`, `license/UniDic-COPYING.txt`
- 生成物: `data/sgnanoime.dic`（R01.001 以降）
- 改変: `tools/build_dict.py` による語彙の選択、読みの正規化、コストの
  調整、連接行列のクラス集約。詳細は `docs/dictionary.md` と
  `docs/modification_log.md`。

### NAIST-jdic（辞書 R01.004 から、R01.005 でも使用）

- ライセンス: BSD 3-clause
- 著作権: 奈良先端科学技術大学院大学（NAIST）ほか
- 版: 0.6.3b-20111013
- 使い方: 名詞の補完（全名詞）
- 全文: `data/thirdparty/naist-jdic/COPYING`
- 記録: `data/thirdparty/manifests/naist-jdic-0.6.3b-20111013-all-nouns.json`
- 詳細: `docs/dictionaries/naist_jdic.md`

IPADIC は ICOT 条項があり、Debian でも non-free 扱いのため採用しない。
検討記録は `docs/dictionaries/ipa.md` に残す。

### Unicode Unihan（倉頡の文字表）

- データ: Unicode Unihan `kCangjie`（2026-07-31、Unicode 18.0.0）
- ライセンス: Unicode License V3
- 全文: `license/UNICODE-LICENSE.txt`
- 記録: `data/thirdparty/manifests/unihan-18.0.0-cangjie.json`
- 生成物: `src/cangjie.inc`（`tools/gen_cangjie.py`）

### 英語スターター単語リスト

- `data/en_common_words.txt` は本プロジェクト用に作成した独自の
  スターターリスト（約 680 語）。第三者のコーパスは使っていない。
- 生成物: `src/en_words.inc`（`tools/gen_en_words.py`）

### 韓国語スターター単語リスト

- `data/ko_common_words.txt` は本プロジェクト用に作成した独自の
  スターターリスト（約 500 語）。第三者のコーパスは使っていない。
- 生成物: `src/ko_words.inc`（`tools/gen_ko_words.py`）

### 台湾中国語スターター単語リスト

- `data/zh_tw_words.tsv` は本プロジェクト用に作成した独自の
  スターターリスト（1,000 語）。第三者の辞書・コーパスは使っていない。
- 注音読みはスターター用に作成し、台湾の慣用（軽声など）に合わせて
  確認した。Unicode / Unihan のデータはまだ取り込んでいない。
- 共起表 `data/zh_tw_bigrams.tsv`（286 組）も本プロジェクト用に作成した。
- 生成物: `src/zh_tw_words.inc`（`tools/gen_zh_tw_words.py`）、
  `src/zh_tw_bigrams.inc`（`tools/gen_zh_tw_bigrams.py`）

### 中国大陸（簡体字）スターター単語リスト

- `data/zh_cn_words.tsv` は本プロジェクト用に作成した独自の
  スターターリスト（1,048 語、簡体字、声調パターンと n/l/r 用 soft 付き拼音）。
  第三者の辞書・コーパスは使っていない。
- 共起表 `data/zh_cn_bigrams.tsv`（306 組）も本プロジェクト用に作成した。
- 生成物: `src/zh_cn_words.inc`（`tools/gen_zh_cn_words.py`）、
  `src/zh_cn_bigrams.inc`（`tools/gen_zh_cn_bigrams.py`）

## これから入れる予定（まだ配布物には含めない）

### MeCab 系辞書

- 辞書ごとにライセンスが違う（NAIST-jdic / JUMANdic / UniDic は BSD、
  NEologd は Apache-2.0）。
- どの辞書を入れたかを `THIRD_PARTY_NOTICES.md` に追記する。
- 詳細: `docs/dictionaries/mecab.md`

### SudachiDict

- ライセンス: Apache License 2.0
- 著作権: Copyright (c) 2017-2023 Works Applications Co., Ltd.
- SudachiDict は UniDic と NEologd の一部を含む。`LICENSE-2.0.txt` と
  `LEGAL` を両方配布物に含める。
- 詳細: `docs/dictionaries/sudachi.md`

## 配布前チェック

- [ ] 使った辞書の `LICENSE` / `COPYING` / `LEGAL` 全文がある
- [ ] 各辞書の著作権表示とライセンス名がある
- [ ] 改変記録（`data/thirdparty/manifests/*.json`）がある
- [ ] 生成物の SHA-256 とリビジョンがある
- [ ] ユーザー辞書・学習ファイルを配布物に含めていない
