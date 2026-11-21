# Linpack ベンチマーク（C 版）

- 作者: Bonnie Toy の C への移植（1988）、Will Menninger の手直し（1993）、Jack Dongarra の daxpy の直し（1994）。元は Jack Dongarra・Cleve Moler らの LINPACK。
- 出所: netlib の `benchmark/linpackc.new`（https://netlib.org/benchmark/linpackc.new、2026-11-20 に取得）を `linpack.c` として置いた。
- **手直し（1 つ）**: 30 行目の `#define DP` を `#ifndef SP` で囲んだ（単精度の殻 `../../lp_sp.c` が `SP` を定義すると、元は `DP` も立って
  `REAL` の型がぶつかった。元の版は単精度にするときこの行を書き換える前提）。
- 使い方: `../../lp_body.inc` が同じ翻訳単位に読み込み、static な `matgen`・`dgefa`・`dgesl` を直接呼ぶ。元の `main` は名前を替えて使わない。
- **配布の条件**: 元のソースには、著作権・使用許諾の文がありません。netlib で自由に配られているもので、sgnano は **パブリックドメインとして扱います**。
  よく使われる John Burkardt の C 版（LGPL）とは別のもので、ここに置いたのは netlib の元の版です。
