# cpubench（CPU の計測）

sgnano の画面モード 0〜7 と音楽（無し / MP3 / VGM の YM2151 + C352）の負荷の下で、Dhrystone 2.1（DMIPS = VAX MIPS）と
Linpack（n = 100）の単精度・倍精度の MFLOPS を測る外部実行ファイル（SGX）です。SGX ABI 5.20 が要ります（sgnano alpha2-2026.11.2 から）。

- 計る間は何も動かさず、計算はメインより 1 段低い優先度のタスクで回します。データとスタックを SRAM に置いた形（S）と PSRAM に置いた形（P）を両方測ります。
- **1 コア（Core 1）と 2 コア（Core 1 + Core 0 のサブタスク）を続けて測ります**（2026-11-24、ABI 5.19）。2 コアは Core 0 の側に Dhrystone の
  2 本目（`dhry0_*.c`、元の版を別の名前で取り込む）を走らせます。
- ローレゾ面を開くモード（3〜6）では、ローレゾ面を **BG 1 面・パターン 16KB・パレット 8 本の決まった大きさ**で開きます
  （`SGX_MODE_LR_ONE_BG` と `SGX_MODE_LR_FIXED`、2026-11-28）。SRAM の空き具合でローレゾ面の大きさが変わり、計算に使える SRAM が変わって
  測り比べがそろわなくなるのを防ぐためです。
- SRAM に必要な連続した空きが無い組み合わせは n/a になります（例: 2 コアの倍精度は 163KB 要る）。
- メニューの「全部」で 8 モード x 3 音 x 1 コア / 2 コアを一通り測ります。`-run 画面モード,音,秒` の引数で 1 つだけ測って終わることもできます。
- 結果は画面（倍角の文字）と `S:/SystemLogs/cpubench.csv`・報告のファイル `S:/SystemLogs/cpubench_<日時>.txt`、UART の `CPUBENCH` の行に出ます。
- 音楽の負荷の曲は、`cpubench.sgx` と同じフォルダの `skyward_pulse.vgz` / `skyward_pulse.mp3`（このリポジトリの `resources/bench/`）。
- 組み方は `CMakeLists.txt` の頭。

## ライセンス

- `cpubench.c`・`bench_dhry.c`・`dhry0_*.c`・`lp_*.c`・`lp_body.inc`・`*.h`: MIT（`LICENSE`）。
- `third_party/dhrystone/`・`third_party/linpack/`: 元のソースに使用許諾の文が無く、パブリックドメインとして扱う（各 `UPSTREAM.md`）。
- 曲 `resources/bench/skyward_pulse.*`: CC BY-SA 4.0（`resources/bench/LICENSE.md`）。
