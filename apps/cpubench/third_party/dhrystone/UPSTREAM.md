# Dhrystone 2.1（C 版）

- 作者: Reinhold P. Weicker（1988）。元の Ada 版は Communications of the ACM vol. 27 no. 10（1984）。C への移植は Rick Richardson。
- 出所: netlib の `dhry-c`（シェルの書庫、sha256 `038a7e9169787125c3451a6c941f3aca5db2d2f3863871afcdce154ef17f4e3e`）。
  書庫を `sh` で走らせず、`sed 's/^-//'` と同じ処理で `dhry.h`・`dhry_1.c`・`dhry_2.c`・`README_C`・`RATIONALE` を取り出した（2026-11-20）。
- **手直し: 無し**（元のまま）。組むときに `main` / `scanf` / `printf` / `malloc` / `time` を `../../bench_dhry.c` のつなぎへ名前を替え、
  `-std=gnu89`・`-DTIME` で組む（`../../CMakeLists.txt`）。
- **配布の条件**: 元のソースには、著作権・使用許諾の文がありません。ベンチマークとして 1980 年代から自由に配られてきたもので、
  sgnano は **パブリックドメインとして扱います**（OpenEmbedded の `dhrystone_2.1.bb` も `PD`）。ほかのプロジェクトは同梱する側の
  ライセンスを付けていることがあります（U-Boot は GPL-2.0+、LLVM の試験は LLVM のライセンス、UnixBench は GPL-2.0）が、
  ここに置いたのは netlib の元の版で、それらの条件はかかりません。
