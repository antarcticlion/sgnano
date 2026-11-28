# sgnano UART 遠隔コマンド リファレンス

この文書は、PC やほかのプログラム（人・AI エージェント・試験の道具）が、sgnano の実機を **UART の遠隔コマンド** で
操作するための参照です。ファームウェアの `src/input/sgremote.c`（受け取り）と `src/filer/sgremote_work.c`（実行）が元です。

- 対象: α2（`alpha2-2026.11` 以降。いまの版は `alpha2-2026.11.2`、ABI 5.20）のファームウェア
- 更新日: 2026-11-28（初版 2026-11-21）
- 道具の見本: `scripts/zm.py`（ZMODEM の転送）、`scripts/console.sh`（ログとキー）

---

## 1. つなぎ方

| 項目 | 値 |
|---|---|
| ポート | sgnano の UART0（GP44 = TX、GP45 = RX）。デバッグプローブの UART ブリッジなら PC では `/dev/ttyACM0` など |
| 速さ | **921600 baud**、8N1、フロー制御なし |
| 文字コード | UTF-8 |
| 同じ線に流れるもの | ファームウェアのログ（`[usb] ...` など）、キー入力、ZMODEM の転送 |

同じ UART が **ログ・キー入力・遠隔コマンド** を兼ねます。PC が送った普通の文字は **キー入力** としてファイラーやプログラムに届き、
`0x1E` で始まる行だけが遠隔コマンドになります。

## 2. 送り方と返事

### 2.1 送る形

```
0x1E <COMMAND> [ARGS] 0x0A
```

- 頭に **`0x1E`**（RS）を 1 バイト付け、終わりは **改行（`0x0A`）**。
- コマンドの名前は大文字・小文字を区別しません（`list` = `LIST`）。前の空白は読み飛ばします。
- 引数は **空白 1 つ** のあと。2 つ以上の引数を取るものは **タブ（`0x09`）** で区切ります（`REN`・`COPY`・`RBRUN`・`SPLIT`）。
  この文書では、タブを **`<TAB>`** と書きます。
- 1 行は **320 バイトまで**（`0x1E` と改行を除く）。超えると `@SG\tERR\t3\tcommand too long`。
- **1 つ送ったら、その返事が来るまで次を送らない** でください。受け取りの待ち行列は 4 行ですが、処理は 1 つずつです。

### 2.2 返事の形

返事は **`@SG` で始まる行** です（区切りはタブ、終わりは `\r\n`）。同じ線にログの行も流れるので、`@SG` で始まらない行は読み飛ばしてください。

| 形 | 意味 |
|---|---|
| `@SG\tOK\t<コマンド>[\t<中身>]` | 成功 |
| `@SG\tERR\t<番号>\t<理由>` | 失敗（番号は 2.3） |
| `@SG\t<種類>\t...` | 中身を返すコマンド（`LIST`・`STAT`・`DRV`・`RSTAT`・`PONG` など。各コマンドの節） |

- 複数の行を返すコマンド（`LIST`・`DRIVES`）は、**終わりの行**（`LIST\tEND`・`DRIVES\tEND`）まで読んでください。
- 返事の中の名前（ファイル名など）は **逃がして** あります: `\\` = `\`、`\t` = タブ、`\n`・`\r` = 改行、`\xHH` = そのほかの制御文字。
- 知らないコマンドには `@SG\tERR\t1\tunknown command`。

### 2.3 誤りの番号

ファイルの操作の誤りは、ファームのファイルの層（`rbfs`）の番号です。

| 番号 | 意味 |
|---|---|
| 1 | 無い（`ENOENT`）。知らないコマンドもこの番号 |
| 2 | もうある（`EEXIST`）。引数の誤り（`invalid path`・`usage:`）もこの番号 |
| 3 | 書けない・読み出し専用（`EACCES`）。始められない（`could not start`・`no memory` など）もこの番号 |
| 4 | フォルダが空でない（`ENOTEMPTY`） |
| 5 | フォルダでない（`ENOTDIR`）。読み書きの失敗のまとめ（`COPY` の `read error` など）もこの番号 |
| 6 | フォルダだ（`EISDIR`） |
| 7 | 読み出し専用のドライブ（`EROFS`） |
| 8 | 空きが無い（`ENOSPC`） |
| 9 | 読み書きの失敗（`EIO`） |
| 10 | 下回りに無い操作（`ENOTSUP`）。`Ruby support is disabled` もこの番号 |
| 11 | パスがおかしい（`EINVAL`） |
| 12 | PSRAM が足りない（`ENOMEM`） |
| 13 | ドライブが無い・媒体が無い（`ENODEV`、`no such drive`） |

**理由の文（4 つ目の欄）を正として読んでください。** 番号はいくつかの場面で使い回しています（上の表の「もこの番号」）。

### 2.4 いつ処理されるか（大事）

- 遠隔コマンドは **ファイラーの裏の仕事の輪**（`src/filer/fio.c`）で、ファイラーのアプリ時間に 1 つずつ処理されます。
- **ファイラーの一覧が出ているとき** に送るのが確実です。
- **プログラムを走らせている間**（SGCALC・トラッカー・Ruby・SGX など）は、返事が来ない・断られることがあります。
  - 2026-11-21: SGCALC を開いている間は `DRIVES` に返事が無く、`RSTOP` でも SGCALC は止まりませんでした。
  - SGCALC はメニューの「ファイル → 終了」で閉じてください。
- 返事が来ないときは、まず **`PING`** で、ファイラーが受け付けられる状態かを確かめてください。
- `LIST`・`STAT`・`DEL`・`REN`・`MKDIR` の間は、ファームが **FB（画面）を一時的に隠します**（USB の処理の都合）。
- ZMODEM（`ZPUT`・`ZGET`）の間は UART が転送の線になり、ログとキーは止まります。**ZMODEM を終えた直後の約 0.4 秒** に送ったコマンドは落ちることがあるので、
  終わったら `PING` に答えるまで待ってください（`scripts/zm.py` の作り）。

### 2.5 パスの書き方

- `A:/dir/name` の形（区切りは `/`）。ドライブ文字は `A`〜`T`、内蔵のシステムドライブは **`S:`**。
- ドライブ文字のない相対のパスは、**ファイラーのいまのフォルダ**（`CWD` で分かる）から。
- 名前は長い名前（UTF-8、日本語も可）。大文字・小文字は区別しません（FAT・exFAT）。
- **ドライブ文字は、つなぐ順や起動ごとに変わります。** 書き込む前に `DRIVES` と `LIST` で、ねらいのドライブかを確かめてください。

---

## 3. コマンド

「区分」: **基本** = ふつうに使う / **試し** = 試験・自動操作のための口 / **診断** = 切り分け用（開発者向け） /
**危険** = わざと壊す・止めるもの（ふだんは使わない）。

### 3.1 状態

| コマンド | 区分 | 返事 | 説明 |
|---|---|---|---|
| `PING` | 基本 | `@SG\tPONG\tSGNANO` | 受け付けられるかの確かめ |
| `BOARD` | 基本 | `@SG\tBOARD\t<名前>` | 基板の種類（P / C） |
| `CWD` | 基本 | `@SG\tCWD\t<パス>` | ファイラーのいまのフォルダ |
| `DRIVES` | 基本 | 下を参照 | ドライブの一覧 |
| `FSTATE` | 試し | `@SG\tFSTATE\t<状態>` | ファイラーの画面の状態（試し用の要約） |
| `RSTAT` | 基本 | `@SG\tRSTAT\t<走っている 0/1>\t<時間>` | 言語のプログラムが走っているか・最後の実行の時間 |
| `CORESTAT` | 診断 | 下を参照 | Core 0 の余裕度・描画稼働率・サブタスク稼働率・ペア時間・画面モード（2026-11-24） |
| `COUNTS` | 診断 | 下を参照 | 表示経路のカウンタ（`underrun`・`fifo_stall`・`recover`・`late_lines`・`min_ready`、2026-11-24） |
| `MEM` | 診断 | `@SG\tOK\tMEM` | SRAM・PSRAM のアリーナの一覧を **ログ** へ |
| `MUSICINFO` | 診断 | `@SG\tOK\tMUSICINFO` | 音楽の様子をログへ |
| `DYN` | 診断 | `@SG\tDYN\t...` の後に `@SG\tOK\tDYN\t<件数>` | 常駐コードの動的ロードの区画（2026-11-28）: 名前・`sram`/`flash`・SRAM の番地・コードの大きさ・区画の中を指す番地の置き場の数・跳び台の数・載せた / 下ろした / SRAM が足りず載せなかった回数。`DYN HOLD` で全部下ろして載せない（フラッシュのままの道の試し）、`DYN FREE` で戻す |
| `MODS` | 診断 | `@SG\tMOD\t...` の後に `@SG\tOK\tMODS\t<件数>` | 音のドライバーの動的モジュールの目録（名前・種別・状態 `idle`/`sram`/`flash`・参照数・SRAM 番地・イメージ長・BSS 長、2026-11-27） |
| `USBINFO` | 診断 | `@SG\tOK\tUSBINFO` | USB の状態と数をログへ（`U` キー相当） |
| `MSCINFO` | 診断 | `@SG\tOK\tMSCINFO` | USB ストレージの台と番地をログへ（同じ機器の別の区画かの見分け） |
| `USBDEV` | 診断 | `@SG\tOK\tUSBDEV` | 引き受け手のいない機器の構成をログへ |
| `USBHW` | 診断 | `@SG\tOK\tUSBHW` | 割り込みエンドポイントのハードの状態をログへ |
| `MIDISTAT` | 診断 | `@SG\tOK\tMIDISTAT\t<数>` | USB MIDI の受け口の数 |
| `PADSTAT [i]` | 診断 | `@SG\tOK\tPADSTAT ...` | パッドの親ハブのポートの状態 |
| `MOUSEDUMP` | 診断 | `@SG\tOK\tMOUSEDUMP` | マウスの生のレポートをログへ |
| `KBDTRACE` | 診断 | `@SG\tOK\tKBDTRACE` | キーボードのレポートの記録をログへ |

**`DRIVES` の返事**（ドライブ 1 つにつき 1 行、終わりに 1 行）:

```
@SG	DRV	<letter>	<type>	<ready>	<device>	<partition-start-LBA>
@SG	DRIVES	END	<count>
```

- 種類: `1` = FAT（USB）、`2` = フロッピー、`3` = exFAT、`4` = NTFS、`5` = CD（ISO9660）、`6` = そのほか（扱えない区画）
- 準備: `1` = 使える、`0` = まだ・媒体なし
- 同じ「機器の番号」で「区画の頭の LBA」が違うものは、**同じ機器の別の区画** です。

**`RSTAT` の時間** は、日本語の決まった形です（表示の言語によらない）: `コンパイル 0.006 秒  実行 0.482 秒`、`実行 1.571 秒`、`0.001 秒未満` など。
画面の終わりの行は表示の言語で出ますが、`RSTAT` は変わりません。

**`CORESTAT` の返事**（直近 1 秒の Core 0 統計、2026-11-24 追加）:

```
@SG	CORESTAT	idle_pct=88.5	busy_pct=11.3	sub_pct=0.0	idle_us=885000	busy_us=113000	sub_us=0	pair_max=22	pairs0=14400	pairs1=0	min_ready=28	mode=TEXT+FB
```

- `idle_pct` / `busy_pct` / `sub_pct`: Core 0 の WFE 待機・描画処理・Core 0 サブタスク（`c0task`）の稼働割合（%）
- `idle_us` / `busy_us` / `sub_us`: 直近 1 秒の各累積時間（µs）
- `pair_max` / `pairs0` / `pairs1` / `min_ready` / `mode`: Core 0 最長ペア描画時間（µs）、Core 0・Core 1 の描画ペア数、最小先読みライン余裕度、画面モード名

**`COUNTS` の返事**（表示経路カウンタの累計と最小先読みライン、2026-11-24 追加）:

```
@SG	COUNTS	underrun=0 fifo_stall=0 recover=0 late_lines=0 min_ready=28
```

### 3.2 ファイル

| コマンド | 区分 | 返事 | 説明 |
|---|---|---|---|
| `LIST [パス]` | 基本 | 下を参照 | フォルダの中身 |
| `STAT <パス>` | 基本 | `@SG\tSTAT\t<F/D>\t<大きさ>\t<書いた日時>\t<属性>\t<名前>` | 1 つの項目 |
| `MKDIR <パス>` | 基本 | `@SG\tOK\tMKDIR\t<パス>` | フォルダを作る |
| `DEL <パス>` | 基本 | `@SG\tOK\tDEL\t<パス>` | ファイルか **空の** フォルダを消す |
| `REN <元><TAB><新しい名前>` | 基本 | `@SG\tOK\tREN\t<パス>` | 名前を変える（名前だけなら同じフォルダの中） |
| `COPY <元><TAB><先>` | 基本 | `@SG\tOK\tCOPY\t<先>` | ファイル 1 つを写す（先はファイルのパス）。**終わるまで返事が来ない**（490MB で 40〜60 分） |
| `SPLIT <パス>[<TAB><大きさ>]` | 基本 | `@SG\tOK\t...` | 7-Zip の無圧縮の分割の形（`.001`・`.002` …）に分ける。大きさを省くと 4MB |
| `JOIN <パス>.001` | 基本 | `@SG\tOK\tJOIN\t<パス>\t<部品の数>` | `.001` から順につなぐ（999 個まで）。FAT では写さずにクラスタの鎖をつなぎ、**部品は消える** |
| `ZPUT <フォルダ>` | 基本 | ZMODEM を始める | PC → 実機（下の 3.6） |
| `ZGET <パス>` | 基本 | ZMODEM を始める | 実機 → PC（下の 3.6） |
| `SYSFSCK [REPAIR]` | 基本 | `@SG\tSYSFSCK\t<CHECK/REPAIR>\tfiles=... bad=...` | S: の検査（`REPAIR` で直す） |

**`LIST` の返事**:

```
@SG	LIST	BEGIN	<path>
@SG	LIST	<F|D>	<size>	<mtime>	<attr>	<name>      (one line per entry)
@SG	LIST	END	<count>	<truncated 0|1>
```

- 書いた日時は **UTC の秒**（1970 年から）。属性は FAT の印のビット（`0x01` 読み出し専用・`0x02` 隠し・`0x04` システム・`0x10` フォルダ・`0x20` アーカイブ）。
- `切れた` が `1` なら、一覧が長すぎて途中までです。

**書き込みの注意**

- 読み出し専用のファイル・ドライブ（CD）、S: のシステムのフォルダ（`SystemSettings`・`SystemFiles`・`SystemLogs`）は消せない・名前を変えられません。
- NTFS は、きれいに取り外されていない（unclean）とき書き込みを断ります。
- `COPY` が失敗すると、書きかけの一時ファイル（`~sgXXXXX.tmp`）が先に残ることがあります（返事の理由に名前が出ます）。
- 書き込んだあと、ファイラーは一覧を読み直します。

### 3.3 プログラムを走らせる

| コマンド | 区分 | 返事 | 説明 |
|---|---|---|---|
| `RBRUN <パス>[<TAB>引数…]` | 基本 | `@SG\tOK\tRBRUN` | `.rb`・`.mrb`・`.sgx`・`.bas`・`.sgb` を走らせる。引数は `.sgx` の `argv[1..]` |
| `PYRUN <パス>` | 基本 | `@SG\tOK\tPYRUN` | `.py` を走らせる |
| `PYTHON` | 基本 | `@SG\tOK\tPYTHON` | MicroPython の REPL を開く |
| `PYKEY <10 進>` | 試し | `@SG\tOK\tPYKEY` | Python へキーを 1 つ（`27` = ESC で `KeyboardInterrupt`） |
| `RSTOP` | 基本 | `@SG\tOK\tRSTOP` | 走っている Ruby / SGX へ ESC を送って止める（**止まらないプログラムもある**: SGCALC など） |

- `OK` は **走らせ始めた** という意味です。終わりは `RSTAT` の 1 つ目の欄（`0` = 走っていない）か、画面の終わりの行で見ます。
- 終わると画面の下に `... finished ... -- press any key` が出て、**キーを 1 つ送るまでファイラーに戻りません**（普通の文字を 1 つ送る）。
- 走らせている間は、ほかの遠隔コマンドに返事が来ないことがあります（2.4）。

### 3.4 ファイラーの操作（試し用）

| コマンド | 区分 | 返事 | 説明 |
|---|---|---|---|
| `FCD <フォルダ>` | 試し | `@SG\tOK\tFCD` | ファイラーの一覧をそのフォルダへ |
| `FSEL <パス>` | 試し | `@SG\tOK\tFSEL` | そのフォルダを開き、読み直したあとカーソルを名前に |
| `FKEY <10 進>` | 試し | `@SG\tOK\tFKEY` | ファイラーのキーの道へキーを 1 つ（例: `FKEY 104` = `'h'` でシェル `sgsh` を開く） |
| `SHOT [フォルダ]` | 試し | `@SG\tOK\tSHOT` | 画面を PNG で、フォルダを省けばいまのフォルダへ（書けないフォルダなら `S:/`）。PSRAM に約 614KB の連続した空きが要る。【訂正 2026-11-27】ファイラーのほか、SGX・3 言語・シェルの実行中も撮れる（2026-11-27 から。以前は「プログラムの実行中は断る」と書いていた） |

`FSEL` / `FCD` で位置を決めたら、あとは **普通のキー**（2 の「同じ線」）を送って操作します。キーの送り方は 4 章。

### 3.5 ネットワーク・設定

| コマンド | 区分 | 返事 | 説明 |
|---|---|---|---|
| `NET` | 基本 | `@SG\tNET\t<状態>` | LAN の状態 |
| `NET OFF` / `NET ON` | 基本 | `@SG\tOK\tNET OFF` など | LAN を止める・戻す（試しで SRAM を空けるとき） |
| `REPORT ON` / `REPORT OFF` | 診断 | `@SG\tOK\tREPORT ON` など | 毎秒の詳細の報告をログへ（既定は出さない。出すと画面がときどき乱れる） |

### 3.6 ZMODEM（`ZPUT` / `ZGET`）

- `ZPUT <フォルダ>`: 実機がそのフォルダで ZMODEM の受け取りを始めます（`**\x18B01` = ZRINIT が来る）。PC は `sz` で送ります。同じ名前は置き換えます。
- `ZGET <パス>`: 実機がそのファイルを送り始めます（`**\x18B00` = ZRQINIT が来る）。PC は `rz` で受けます。
- 受け取りは **1 ファイル 4MB まで**。大きいものは PC で分けて送り、`JOIN` でつなぎます。送りは 4MB を超えても分けません。
- 速さは約 70KB/s。終わったら `PING` に答えるまで待ってから次を送ります。
- 手順の実装は `scripts/zm.py`（`scripts/zm.sh put --remote-dir <フォルダ> <ファイル>…` / `get --remote-file <パス> <フォルダ>`）をそのまま使うのが確実です。

### 3.7 USB の切り分け（診断）

ふだんは使いません。USB の不具合を調べるときの口です。

| コマンド | 説明 |
|---|---|
| `USBRESTART` | USB のホストを作り直す（キーボードが戻らないとき）。一度答えなくなった機器は電源を入れ直すまで引き受けない |
| `USBRESET <ドライブ>` / `USBSYNC <ドライブ>` / `USBREAD ...` | USB ストレージの BOT の立て直し・書き込みの確定・セクタの直読み（先頭 16 バイト・CRC32・時間を返す） |
| `USBBG 0\|1` | USB ストレージのデータ段の裏読み（epx）を切り替える |
| `USBKICK` | HID の張り直し（ハブ越しで止まったキーボードの試し） |
| `KBDPOLL ON\|OFF` | ハブ越しのロースピードのキーボードを GET_REPORT で読むか |
| `PADPORT [i]` / `PADIDLE [i] <n>` / `PADPROTO [i]` / `PADREARM [i]` / `PADGET [i]` | パッドの親ハブのポートのリセット・SET_IDLE・SET_PROTOCOL・張り直し・GET_REPORT |
| `PADRUMBLE [i] <弱 0/1> <強 0..255>` | DS3 の振動 |
| `USBHUBREARMTEST` | ハブの見張りの張り直しを試す |
| `COPYGAP <ms>` | 書き込みの確定から次のファイルまでの間（切り分け用） |
| `GPIOTEST <ピン>[ 0\|1]` | 画面をモード 0 にしてピンを SIO で駆動し、パッドの入力と状態を返す（**ファームの使うピンに当てない**） |
| `AUDCAP ...` | 音の出力のピンの取り込み |
| `COMPACT [バイト]` | SRAM のコンパクション |

### 3.8 危険（わざと壊す・止める）

**ふだんは送らないでください。** 試験で道を通すためだけのものです。

| コマンド | 何が起きるか |
|---|---|
| `PANICTEST` | わざと panic する。ウォッチドッグで再起動し、次の起動で止まった記録が出る |
| `SRAMHOG ON [残すバイト]` / `SRAMHOG OFF` | SRAM のアリーナの空きを全部取る / 返す（空きが無いときの試し）。ON の間はほかの機能が動かないことがある |
| `MSCSTUCK ON` / `OFF` | USB ストレージが答えない場面をまねる（時間切れの道の試し） |

---

## 4. キーを送る（コマンドではない普通の入力）

`0x1E` で始まらないバイトは、キー入力としてファイラーや走っているプログラムに届きます。特殊キーは ANSI のエスケープ列です
（`scripts/console.sh` の `{名前}` と同じ）。

| キー | 送るバイト |
|---|---|
| ↑ ↓ → ← | `ESC [ A` / `B` / `C` / `D` |
| Home / End / Ins / Del | `ESC [ H` / `ESC [ F` / `ESC [ 2 ~` / `ESC [ 3 ~` |
| PgUp / PgDn | `ESC [ 5 ~` / `ESC [ 6 ~` |
| メニューキー | `ESC [ 29 ~` |
| F1〜F4 | `ESC O P` / `Q` / `R` / `S` |
| F5〜F12 | `ESC [ 15 ~`・`17`・`18`・`19`・`20`・`21`・`23`・`24 ~` |
| Shift / Alt / Ctrl + F1〜F4 | `ESC [ 1 ; m P`〜`S`（m = 2 Shift・3 Alt・5 Ctrl） |
| Shift / Alt / Ctrl + F5〜F12 | `ESC [ n ; m ~`（n は上の数） |
| Shift + 矢印 | `ESC [ 1 ; 2 A`〜`D` |
| Enter / BS / Tab / ESC | `\r` / `\b` / `\t` / `0x1B` |

**注意**

- **ESC のあと続けて文字を送ると、Alt + 文字** として読まれます。ESC を単独で送るときは、次のキーまで少し（0.3 秒ほど）あけてください。
  このため、UART からは **Alt + 文字・一部のアプリの Alt + F キーが届かない** ことがあります（SGCALC の Alt+F12 は届かない。メニューで閉じる）。
- 1 つ送ったら、画面が変わるのを待ってから次を送ってください。窓が開く前に打った文字は、ファイラーの操作として読まれます。
- 名前の欄では、カーソルは **拡張子の前** に置かれます（名前を変えるとき、拡張子は残る）。
- ファイラーのキーの一覧は `docs/sgnano_keys.pdf`、ファイラーの F1 ヘルプ。

---

## 5. 手順の見本

### 5.1 ファイルを入れて走らせる

```
-> 0x1E PING                       <- @SG PONG SGNANO
-> 0x1E DRIVES                     <- @SG DRV A 3 1 0 63 ... @SG DRIVES END 2
   (PC: scripts/zm.sh put --remote-dir A:/work hello.rb)
-> 0x1E RBRUN A:/work/hello.rb     <- @SG OK RBRUN
-> 0x1E RSTAT                      <- @SG RSTAT 1 <time text in Japanese>
   (when it has finished, send one ordinary character to go back to the filer)
```

返事の区切りは実際はタブです。`RSTAT` の時間は日本語の決まった形（3.1）です。

### 5.2 Python で送る（最小）

```python
import serial, time
ser = serial.Serial('/dev/ttyACM0', 921600, timeout=0.2)

def remote(line, timeout=20, until=('OK', 'ERR')):
    ser.reset_input_buffer()
    ser.write(('\x1e%s\n' % line).encode('utf-8'))
    buf, end = b'', time.time() + timeout
    while time.time() < end:
        buf += ser.read(4096)
        rows = [l.decode('utf-8', 'replace') for l in buf.replace(b'\r', b'').split(b'\n') if l.startswith(b'@SG')]
        if any(len(r.split('\t')) > 1 and r.split('\t')[1] in until for r in rows):
            return rows
    return rows

print(remote('PING', until=('PONG',)))
print(remote('DRIVES', until=('DRIVES',)))
print(remote('LIST S:/', until=('ERR',), timeout=5))   # read LIST until its END line
```

### 5.3 画面を確かめる

遠隔コマンドには画面を読む口がありません。開発の試験の道具は、デバッグプローブの SWD で **テキスト面を止めずに** 読んでいます
（`tm` の指す文字の並び、80 桁 x 30 行）。プローブが無いときは、`SHOT` で画面を PNG にするか、返事とログで確かめてください。

---

## 6. AI エージェント向けの決まり

- **書く前に確かめる**: `DRIVES` と `LIST` で、ねらいのドライブ・フォルダかを確かめてから `MKDIR`・`ZPUT`・`COPY`・`DEL`・`REN` を送る。
  ドライブ文字は入れ替わる（2.5）。人のデータのあるドライブに書かない。
- **1 つずつ**: 返事（`OK` / `ERR` / 中身の終わりの行）を待ってから次を送る。
- **返事が来ないとき**: `PING` で確かめ、プログラムが走っていないかを見る。走っていれば、そのプログラムの閉じ方（メニュー・`q`・ESC）で閉じる。
- **危険・診断のコマンド**（3.7・3.8）は、人に頼まれたときだけ送る。
- **長いもの**（`COPY` の大きいファイル・`JOIN`・ZMODEM）は終わるまで返事が来ない。時間切れは長めに（`COPY` は 1MB あたり 5〜7 秒を目安）。
- キーを送る操作は、**窓が開いたことを確かめてから** 名前を打つ。合わなければ ESC で止める。
