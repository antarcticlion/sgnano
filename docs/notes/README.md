# 調査ノートの索引

`notes/` は**分野ごとの追記式の記録**です。現在の状態・決まりごとは [`../DEVELOPMENT.md`](../DEVELOPMENT.md) にあります。
仕様メモ（`SPEC_*.md`）と内部の申し送りは公開しません。

## ノートの一覧

| ノート | 範囲 |
|---|---|
| [`video.md`](video.md) | PSRAM と FB、2 コア描画、フレームの進め方、ローレゾ、オブジェクト、テキスト、VGA タイミング、T3〜T6 |
| [`audio.md`](audio.md) | PT8211 の経緯（形式の取り違え・アナログ段の不良）、映像との同時動作、CD のストリーミング再生、音楽の口（MP3 / OGG / VGM）、`Music.cfg` の SSG・DCSG MIX、VGM プレイヤーの内蔵、96kHz/24bit WAV の書き出し（ALT+F8、経過/合計）・再生、ADC（単発・96kHz ステレオ取り込み、C の A6/A7）、MIDI（DIN / USB ホスト、SMF の MIDI OUT） |
| [`usb.md`](usb.md) | キーボード・マウス・パッド・ハブ、リファレンス機材、TinyUSB の不具合と回避、診断の道具、USB メモリの区画、USB MIDI ホスト（app driver） |
| [`storage.md`](storage.md) | USB メモリ、FAT12/16/32、FDD（UFI/CBI）、光学（ATAPI/BOT）、ISO9660、オーディオ CD、exFAT/NTFS |
| [`devenv.md`](devenv.md) | ビルド・書き込み・診断ビルド、QSPI、core1 が止まる件、T1/T2/T7、静的解析、SRAM |
| [`system.md`](system.md) | 開発段階の旧記述、コンソール、ハードウェア・ピン・クロック、ウォッチドッグ、アプリ層、ログ、用語、直近の作業（GPIO / PIO2 / ABI 5.0 の実機結果を含む） |
| [`doom.md`](doom.md) | Doom の移植（doomgeneric + Freedoom）: 形・メモリ・キー・始め方・実機の速さ |
| [`micropython.md`](micropython.md) | MicroPython の組み込み: 構成・走らせ方・モジュール・SRAM の優先順位・ゲームの移植 |
| [`sram_compaction.md`](sram_compaction.md) | SRAM アリーナのコンパクション（安全点・タスク・PSRAM スタック） |

## 書き足すとき

1. その分野のノートの**末尾**に `## YYYY-MM-DD 見出し` を足す。
2. 次の 4 点を書く（読み手が同じ現象を追えるように）:
   - **現象**: 何が起きたか。ログの行、画面、条件。
   - **調べたこと**: 見た場所、読んだ値、切り分けの結果。
   - **対処**: 変えたもの。変えなかったものと、その理由。
   - **確かめ**: 実機 / ホスト / 何回中何回。残っていること。
3. 古い記述を消さない。訂正は【訂正】、後から分かったことは【追記】を付けて残す。
   （`../DEVELOPMENT.md` 冒頭の決まりと同じ）
4. 日付は実機で見た日。ログの時刻と混同しない。
5. 大きな区切りでは、公開用の文書に要約を書く。内部の申し送りは公開しない。

## 関連する計画

- `PLAN_lowres_2core.md` — ローレゾ 2 コアの計画（実装は済み。その後の変更は `video.md`）
- `PLAN_shell_lang.md` — シェル言語統合の段取り
- `../README.md` — ドキュメント全体の入口とソースの地図

仕様メモ（`SPEC_*.md`）は内部に置いています。実装した内容の文書は、公開のあとに別に用意します。
