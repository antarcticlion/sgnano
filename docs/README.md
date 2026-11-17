# sgnano ドキュメントの入口

このディレクトリは、ファームウェアの**現在の状態**・**仕様**・**調査の記録**を分けて置いています。
「いまどうなっているか」を探すときは [`DEVELOPMENT.md`](DEVELOPMENT.md)、理由や実測値を探すときは `notes/` を読んでください。

## まず読むもの

| 文書 | 中身 | いつ更新するか |
|---|---|---|
| [`notes/`](notes/) | 分野ごとの調査記録（日付つきの追記） | 現象・実測・対処を記録するとき |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | 現在の状態・設計の決まり・用語（公開用） | 開発ガイドを更新したとき |
| [`machine_api.md`](machine_api.md) | mruby / MicroPython / SG BASIC の `Machine` 対応表 | API を足したとき |
| [`sgx_abi.md`](sgx_abi.md) | SGX（外部実行ファイル）の ABI | ABI を変えたとき |
| [`TEST_PLAN_2026-10-31.md`](TEST_PLAN_2026-10-31.md) | 実機試験の計画 | 試験を足したとき |
| `../PLAN_*.md` | lowres 2core・shell 言語統合の段取り | 計画を進めたとき |
| `sgnano_ruby_guide.md` / `sgnano_python_guide.md` / `sgnano_basic_guide.md` | 書く人向けの言語ガイド（PDF あり） | 言語機能を変えたとき |

## ソースの地図

| ディレクトリ | 役割 | 主な入口 |
|---|---|---|
| `src/app/` | 起動バナー・クラッシュ記録・状態表示・キー | `main.c` から |
| `src/video/` | VGA タイミング、2 コア描画、テキスト、ローレゾ、ビットマップ | `video/vga.h`、`video/screen.h` |
| `src/audio/` | PT8211 音源、発音マネージャ、SMF/SGT シーケンサー、ADC | `audio/audio.h`、`audio/sndmgr.h` |
| `src/gpio/` | GPIO（SIO）と PIO2 のユーザー向けの口（SM・命令メモリ・FIFO） | `gpio/userio.h` |
| `src/midi/` | DIN MIDI（UART1）と USB MIDI ホスト | `midi/midi.h`、`midi/midi_usb_host.h` |
| `src/filer/` | ファイラー本体、一覧、ビューア、エディタ、設定、言語、IME、ZMODEM | `filer/filer.h` |
| `src/fs/` | exFAT・NTFS の読み書き（FAT は `input/usbfat.c`） | `fs/fsvol.h` |
| `src/input/` | USB ホスト（HID・MSC・ハブ）、FAT、ISO9660、UART、遠隔コマンド | `input/usbhost.c`、`input/sgremote.h` |
| `src/storage/` | システムドライブ S:（内蔵フラッシュの FAT12） | `storage/sysdisk.h` |
| `src/mem/` | SRAM アリーナ・PSRAM アリーナ・コンパクション | `mem/vmem.h`、`mem/appmem.h` |
| `src/rtos/` | M33BEATOS（core1 の RTOS） | `rtos/m33beatos.h` |
| `src/ruby/` | mruby の組み込み、ファイル API、Machine、端末、時計 | `ruby/rbrun.h` |
| `src/python/` | MicroPython のポート、Machine、socket、FFT | `python/pyrun.h` |
| `src/basic/` | SG BASIC（MIT、上流は `UPSTREAM.md`） | `basic/include/sgbasic/` |
| `src/shell/` | sgsh（csh のサブセット）、端末、言語コマンド | `shell/sh_main.c` |
| `src/sgx/` | SGX（外部実行ファイル）の読み込みと API | `sgx/sgx.h` |
| `src/net/` | lwIP・CDC-ECM・TCP/TLS・NTP | `net/netif.h` |
| `src/image/` | PNG の解読と表示 | `image/png.h` |
| `src/dsp/` | FFT（アセンブラ含む） | `dsp/fft_f32.h` |

## どこを直すか

| 変えたいもの | まず見る場所 | 記録するノート |
|---|---|---|
| USB の列挙・HID・ハブ・MSC | `src/input/usb*.c`、`src/input/usbhost_internal.h` | `notes/usb.md` |
| USB メモリ・FDD・光学・CD | `src/input/usbfat.c`、`usbufi.c`、`usbmsc.c`、`usbata.c`、`isofs.c` | `notes/storage.md` |
| exFAT・NTFS | `src/fs/` | `notes/storage.md` |
| 画面モード・タイミング・描画 | `src/video/` | `notes/video.md` |
| テキスト・属性・IME | `src/video/text.c`、`src/filer/ime.c`、`fstr.c` | `notes/video.md`、`notes/system.md` |
| 音源・シーケンサー | `src/audio/` | `notes/audio.md` |
| ADC（単発・96kHz 取り込み） | `src/audio/adcin.c` | `notes/audio.md`、`machine_api.md`、`sgx_abi.md` §5.27 |
| ファイラーのキー・一覧・コピー | `src/filer/filer.c`、`fio.c`、`fcopy.c`、`ftree.c` | `notes/system.md` |
| 言語（Ruby/Python/BASIC） | `src/ruby/`、`src/python/`、`src/basic/` | `notes/system.md`、`notes/micropython.md` |
| シェル | `src/shell/` | `notes/system.md` |
| SGX | `src/sgx/`、`sdk/sgx/`、`apps/` | `sgx_abi.md`、`notes/system.md` |
| GPIO / PIO2 / MIDI | `src/gpio/`、`src/midi/`、`src/tusb_config.h` | `machine_api.md`、`sgx_abi.md` §5.25〜5.26、`notes/audio.md`、`notes/usb.md` |
| RTOS・タスク | `src/rtos/` | `notes/system.md` |
| メモリ（SRAM/PSRAM） | `src/mem/`、`src/psram/` | `notes/devenv.md` |
| ネットワーク | `src/net/` | `notes/system.md` |
| ビルド・書き込み・試験 | `scripts/`、`CMakeLists.txt` | `notes/devenv.md` |

## 書き方の決まり

1. **現在の状態は `DEVELOPMENT.md` に書く。** 調査の経緯・実測値・失敗した案は `notes/` に書く。
2. **ノートは追記式。** 分野ごとのファイルの末尾に `## YYYY-MM-DD 見出し` を足す。古い記述を消さず、
   訂正するときは【訂正】、【追記】を付ける（`DEVELOPMENT.md` の冒頭にも同じ決まりがある）。
3. **仕様メモ（`SPEC_*.md`）は内部に置く。** 実装の意図と API の約束を書き、日付つきの経緯はノートへ。
4. **PDF は Markdown から作る。** `python3 scripts/md2pdf.py <md> <pdf>`。手で PDF を編集しない。
5. **試験を伴う変更は、変更した分野のノートに「どう確かめたか」を残す。**
   ホストは `scripts/test_all.sh`、HDD 接続の起動は `scripts/test_launch.py`。
6. **コメントは「なぜ・なぜそうしないか・どの前提か」を書く。** コードを読めば分かる「何をしているか」は
   短くてよいが、タイミング・SRAM/PSRAM の制約・USB の回避策・過去に踏んだ不具合は必ず残す。

## よく使う手順

```sh
scripts/build.sh                 # build/sgnano.elf
scripts/flash_swd.sh             # SWD で書き込み（--reset / --rescue / --attach）
scripts/flash_chunks.sh          # 一括消去が止まるときの 128KB ずつ書き込み
scripts/console.sh               # UART のログとキー入力
scripts/test_all.sh              # ホスト試験
python3 scripts/test_launch.py   # HDD 接続で S:/testapp のテストを起動
python3 scripts/md2pdf.py docs/sgnano_ruby_guide.md docs/sgnano_ruby_guide.pdf
```

ビルド構成・書き込みの作法・ウォッチドッグ・QSPI の復旧などは `notes/devenv.md` を参照。
