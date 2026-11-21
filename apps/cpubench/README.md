# cpubench（CPU の計測）

sgnano の画面モード 0〜7 と音楽（無し / MP3 / VGM の YM2151 + C352）の負荷の下で、Dhrystone 2.1（DMIPS = VAX MIPS）と
Linpack（n = 100）の単精度・倍精度の MFLOPS を測る外部実行ファイル（SGX）です。SGX ABI 5.15 が要ります（sgnano α2 から）。

- 計る間は何も動かさず、計算はメインより 1 段低い優先度のタスクで回します。データとスタックを SRAM に置いた形（S）と PSRAM に置いた形（P）を両方測ります。
- 結果は画面（倍角の文字）と `S:/SystemLogs/cpubench.csv`・報告のファイル `S:/SystemLogs/cpubench_<日時>.txt`、UART の `CPUBENCH` の行に出ます。
- 音楽の負荷の曲は、`cpubench.sgx` と同じフォルダの `skyward_pulse.vgz` / `skyward_pulse.mp3`（このリポジトリの `resources/bench/`）。
- 組み方は `CMakeLists.txt` の頭。

## ライセンス

- `cpubench.c`・`bench_dhry.c`・`lp_*.c`・`lp_body.inc`・`*.h`: MIT（`LICENSE`）。
- `third_party/dhrystone/`・`third_party/linpack/`: 元のソースに使用許諾の文が無く、パブリックドメインとして扱う（各 `UPSTREAM.md`）。
- 曲 `resources/bench/skyward_pulse.*`: CC BY-SA 4.0（`resources/bench/LICENSE.md`）。
