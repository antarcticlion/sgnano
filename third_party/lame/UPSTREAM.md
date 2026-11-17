# LAME 3.100（エンコーダの部分だけ）

- 出所: Debian の `lame_3.100.orig.tar.gz`（https://deb.debian.org/debian/pool/main/l/lame/）、
  sha256 `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`（LAME の公式の 3.100 と同じ）。2026-11-14。
- ライセンス: **LGPL**（`COPYING`・`LICENSE`）。**ファームには入れない。** 外部実行ファイル `wav2mp3.sgx`（`apps/wav2mp3/`）だけが静的にリンクする。
  LGPL の条件（使う人がライブラリを差し替えて組み直せること）は、`apps/wav2mp3/` のソースと SDK（`sdk/sgx/`）をこのリポジトリで公開して満たす。
- 入れたもの: `libmp3lame/` の `.c` / `.h`（`mpglib_interface.c`・`i386/` と `vector/` の SSE の中身は除く。`vector/lame_intrin.h` は宣言だけなので入れた。`fft.c`・`quantize.c` が取り込む）、`include/lame.h`、`COPYING`・`LICENSE`・`README`。
- `config.h` は sgnano が書いたもの（configure は走らせない）。
- 手直し: 無し（下に足したら書く）。
