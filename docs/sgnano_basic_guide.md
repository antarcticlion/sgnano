# sgnano BASIC プログラミング仕様書（SG BASIC R03 環境）

版: 2026-11-17 ／ 対象: sgnano のファームウェア（RP2350B）に組み込んだ SG BASIC **Rev03.001**

この文書は、sgnano で動く BASIC のプログラムを**ほかの人や AI が書く**ための仕様書です。書いてある決まりは**実機とホストで確かめたもの**です。
SG BASIC は Microsoft BASIC（6502 版）を C に移したもので、GW-BASIC に近い文と、VB 風の `Sub` / `Function` / `Type` / `Class` を持ちます。
言語の細かい説明（全部の文・関数・エラー）は `src/basic/docs/LANGUAGE.md` にあります。この文書は sgnano で書くときの要点です。

画面・音・パッドの口（`Machine`・`Sound`）は Ruby・Python と同じ名前・同じ働きにそろえてあります（対応表 `docs/machine_api.md`、
細かい働きは `docs/sgnano_ruby_guide.md` の §7・§9）。

【2026-11-17】**FB・ビットマップ・画像の描画**（線・図形・パス・文字・転送、§5）と**圧縮と書庫**（`Machine.Arc*`、§6）を足した（ABI 5.3・5.12、`SPEC_gfx.md`）。

---

## 1. 環境のあらまし

| 項目 | 内容 |
|---|---|
| 処理系 | SG BASIC Rev03.001。字句は flex、構文は bison。プログラムはその場でバイトコードにコンパイルして走らせる |
| 画面 | Ruby と同じ: テキスト面（80 x 30、上 28 行が端末）・FB（640x480、4 ページ）・ローレゾ面・ビットマップ。`Machine.Mode` / `SCREEN n` の画面モード 0〜7。始めはモード 1 |
| メモリ | ヒープ・スタック（256KB）は PSRAM |
| 数 | **SINGLE**（既定、有効 7 桁）・**DOUBLE**（`#`、有効 16 桁）・**INTEGER**（`%`、**16 ビット: -32768〜32767**）・文字列（`$`、**255 バイトまで**）・Variant |
| 入力 | `INPUT` / `LINE INPUT`（行）、`INKEY$`・`Machine.Key`（1 つずつ。無ければ `""` / -1）、`Machine.KeyDown(k)`。**ESC は実行を止める** |
| 出力 | `PRINT` は画面の端末と、開発用のシリアルの両方へ |
| 真と偽 | 真は -1、偽は 0（`Machine` の真偽を返すメソッドも同じ） |

## 2. プログラムの置き場と実行

- ドライブに拡張子 `.bas`（ソース）で置き、ファイラーで選んで **Enter**。`.sgb`（コンパイル済み）も同じ
- 終わると状態の行に「mandel.bas (SGBASIC)  finished (0)  実行 1.105 秒 -- press any key」のように出て（かっこの中の数は終わりの番号。誤りで止まると 1）、何かキーでファイラーへ戻る（Ruby・Python と同じ）。画面モード・FB の表示とページは実行前に戻る
- **ESC で止める**。誤りで止まると `?SN ERROR IN 120` のように出る（行番号を省いたファイルでは、上から 10・20・30…と数えた番号）
- **行番号は省いてよい**。`GOTO` の行き先には**ラベル**（行の頭に `名前:`）を使う。行番号とラベルは混ぜてよい
- `.sgb` はその版の SG BASIC でしか読めない（R02 で作った `.sgb` は「bytecode revision mismatch」）。`.bas` を置けば足りる
- 見本: `S:/sgbasic`（`mandel.bas` `hat.bas` `m640.bas` `machine.bas` `lowres.bas` `sound.bas` `socket.bas`）、**テスト用アプリの BASIC 版** `S:/sgbasic/testapp/mode0.bas`〜`mode7.bas`

### 2.1 シェルから使う（2026-11-02）

ファイラーで **x** を押すとシェル **sgsh** が開く。SG BASIC のコマンドは mruby・MicroPython に寄せてある。

```
sgbasic [switches] [programfile] [arguments]
sgbasic -e 'PRINT 1+2'                 # 1 行のプログラム（行番号はいらない。いくつも書ける）
sgbasic -c -e 'PRINT 1'                # 文法だけ（Syntax OK）
sgbasic -i -e 'PRINT 1'                # 走ったあと直接モード（OK のプロンプト）に残る
sgbasic file.bas a b                   # COMMAND$ = "a b"
sgbasic -q file.bas                    # バナーと OK を出さない
sgbasic                                # 直接モード（OK。Ctrl-D で終わり）
sgbc file.bas                          # file.sgb を書き出す（-o out、-c は文法だけ）
sgbasic file.sgb                       # バイトコードを走らせる
```

- 引数は `COMMAND$`（空白でつないだ 1 つの文字列）で読める。`SYSTEM n` で終わりの番号を n にして終わる（`SYSTEM` だけなら 0）
- `basic` は `sgbasic` の別名（`alias` で上書きできる）
- `file.bas` / `file.sgb` のように**拡張子だけで**走らせられる。`run file.bas a b` でも同じ
- パイプ・リダイレクト・stdin がそのまま使える: `printf 'PRINT 42\n' | sgbasic`、`sgbasic file.bas > out.txt`
- 出力はシェルの端末、`?SN ERROR` などは stderr（【訂正 2026-11-06】この記述より前の版では stdout に出ていた。SGX ABI 3.5 の `term_write_err` で直した）。`$status` は正常 0、誤り・Ctrl-C は 1、`SYSTEM n` は n
- 実行中に **Ctrl-C**（または Shift+ESC）で子だけを止めてシェルへ戻る。画面モード 2〜7 を使った子は、終わりにモード 1 へ戻して描き直す

## 3. 書き方の決まり（R03）

### 3.1 予約語は語の単位で

予約語は**語として離れているときだけ**予約語になる。`SCORE`・`TOTAL`・`PRINTX`・`FORMAT` は変数名に使える。その代わり、詰めて書いた
`FORI=1TO10` は通らない（`FOR I = 1 TO 10` と書く）。大文字・小文字は同じ。例外（昔からの決まり）:

- `FN` で始まる語は `FN` と名前に分かれる（`DEF FNSQ(X) = X * X` → `FNSQ(3)`）。`FNAME` のような名前は使えない
- `TAB(`・`SPC(` は `(` が直後にあるときだけ予約語
- `?` は `PRINT`
- `'` から行末まではコメント（`REM` も）

### 3.2 1 行の IF

`IF 条件 THEN 文: 文 ... ELSE 文: 文 ...` は **1 行だけ**（`END IF` のある複数行の IF は無い）。THEN のあとの文は行末（か ELSE）まで続く。
`IF A THEN IF B THEN X ELSE Y ELSE Z` の ELSE は**いちばん近い IF のもの**。長い分かれ道は `SUB` や `GOSUB` に分ける。`IF 条件 THEN 100` / `THEN ラベル` は飛ぶ。

### 3.3 SUB と FUNCTION

```basic
FUNCTION SQUARE(BYVAL V) AS DOUBLE      ' the result: assign to the function's name
    SQUARE = V * V
END FUNCTION
SUB SHOWVAL(BYVAL LABEL$, BYVAL V)
    PRINT LABEL$; V
END SUB
SHOWVAL "4^2 =", SQUARE(4)
CALL SHOWVAL("again", 2)
```

- **SUB / FUNCTION は呼ぶ所より前に書く**。前に無い名前の `F(1)` は配列として読まれる（エラーにならないので気づきにくい）
- 引数は省けば `BYREF`（呼び手の変数が変わる）。値だけ渡すなら `BYVAL` を付ける
- **SUB の中の変数は引数のほかはすべてプログラム全体で共通**（局所の変数は無い）。関数どうしで同じ名前の作業用の変数を使わない
- 途中で抜けるのは `EXIT SUB` / `EXIT FUNCTION`。FUNCTION の値は名前への代入か `RETURN 式`

### 3.4 数の決まり（よく踏むもの）

1. **`\`（整数の割り算）・`MOD`・`AND`・`OR`・`XOR`・`NOT` は 16 ビットの整数で計算する**。どちらかが -32768〜32767 の外だと
   `?FC ERROR`（ミリ秒・フレーム数・ボタンのビットなどで起きる）。大きな数は `INT(A / B)`、`A - INT(A / B) * B` で
2. 何も付けない変数は SINGLE（有効 7 桁）。ミリ秒を引き算するなど桁の要る計算は、先頭に **`DEFDBL A-Z`**（全部を DOUBLE に）を置くとよい
3. 数の定数は、書いた形のまま SINGLE（`123456789012` は `1.234568E+11`）。DOUBLE の定数は `#` を付ける
4. 文字列は 255 バイトまで（長いと `?LS ERROR`）

### 3.5 Machine のメソッドの引数の頭の `(`

`Machine.FillRect (I * 7) MOD 576, Y, 64, 48, C` のように、**メソッド名のすぐあとが `(` で始まると、それはメソッドの引数のかっこ**と読まれ、
後ろの `MOD 576, ...` で構文の誤りになる。先に変数へ入れる（`X = (I * 7) MOD 576: Machine.FillRect X, Y, 64, 48, C`）。

## 4. よく使う文と関数

| 種類 | もの |
|---|---|
| 制御 | `FOR ... TO ... STEP` / `NEXT`、`WHILE` / `WEND`、`GOTO`、`GOSUB` / `RETURN`、`ON n GOTO / GOSUB`、`END` |
| 入出力 | `PRINT`（`;` で続ける・`,` で次の欄・`TAB(n)`・`PRINT USING`）、`INPUT "問い"; A, B$`、`LINE INPUT A$`、`INKEY$` |
| 配列 | `DIM A(100)`・`DIM B(10, 10)`・`REDIM`・`OPTION BASE`・`LBOUND` / `UBOUND`・`ERASE` |
| データ | `DATA` / `READ` / `RESTORE`（`DATA` の値は上から順に読まれる） |
| 文字列 | `LEFT$` `RIGHT$` `MID$` `LEN` `INSTR` `STR$` `VAL` `CHR$` `ASC` `HEX$` `OCT$` `SPACE$` `STRING$` |
| 数 | `INT` `FIX` `ABS` `SGN` `SQR` `SIN` `COS` `TAN` `ATN` `LOG` `EXP` `RND` `CINT` `CDBL` |
| 誤り | `ON ERROR GOTO 行`・`RESUME` / `RESUME NEXT`・`ERR` / `ERL`・`ERROR n` |
| 時間 | `TIMER`（秒）・`DATE$` / `TIME$`（本体の時計。NTP で合わせていなければ仮の時刻）・`Machine.Ms`（起動からのミリ秒） |
| 型・クラス | `TYPE ... END TYPE`、`CLASS ... END CLASS`（メソッドとフィールド、`Class_Initialize`）、`DIM P AS Point`、`SET C = NEW Counter` |

`STR$(5)` は `" 5"`（正の数は頭に空白）。頭の空白を取るなら `MID$(STR$(V), 2)`。

## 5. 画面: Machine

**名前は Ruby の `Machine` から `_` と `?` を取ったもの**（大文字・小文字は同じ。`pad_pressed?` → `PadPressed`）。
FB の描画は `Machine` に直に（`Machine.PSet`）、ローレゾは頭に `Lr`（`Machine.LrObj`）、ビットマップは `Bm`（`Machine.BmPSet`）。
Ruby の書き込み（`x=`）は代入（`Machine.Mode = 3`）。Ruby の Hash を返すものは鍵を渡して 1 つずつ（`Machine.VideoInfo("frames")`）。
値を返すメソッドはかっこを付ける（`X = Machine.PGet(10, 20)`）、返さないものは文として並べる（`Machine.PSet 10, 20, C`）。

| 書き方 | 意味 |
|---|---|
| `Machine.Mode = n` / `SCREEN n` | 画面モード 0〜7（Ruby と同じ組み合わせ） |
| `Machine.FbVisible = b` / `Machine.TextVisible = b` | FB・テキスト面を見せる / 隠す（`-1` / `0`） |
| `Machine.VSync [n]` | n フレーム待つ（パッドの写しもここで） |
| `Machine.RGB(r, g, b)` | 0..255 から画素の値（RGB555）。CLUT8・CLUT4 では色の番号を直に |
| `Machine.Ms` | 起動からのミリ秒 |
| `Machine.Key` / `Machine.WaitKey` / `Machine.ClearKeys` | 次のキー（無ければ -1）/ 待つ / 捨てる |
| `Machine.KeyDown(k)` / `Machine.Keyboard` / `Machine.KeyName(k)` | 押しているか（USB キーボードだけ）/ つながっているか / 表示用の名前 |
| `Machine.Pages` / `Machine.DispPage` / `Machine.WritePage` | FB のページ数 / 表示するページ / 描くページ（代入で切り替え） |
| `Machine.FbPalette i, r, g, b` / `Machine.FbPalette(i)` | CLUT8・CLUT4 の色 |
| `Machine.Cls [c]` / `Machine.FbClear [c]` | FB を塗る |
| `Machine.PSet x, y, c` / `Machine.PGet(x, y)` | 点 |
| `Machine.Line` `Machine.Rect` `Machine.FillRect` `Machine.Triangle` `Machine.FillTriangle` | 線・枠・塗り・三角形（引数は Ruby と同じ） |
| `Machine.Blit sx, sy, w, h, dx, dy [, page [, key]]` | 矩形の転送（`page` を -1 にすれば描くページ） |
| `B = Machine.GetBlock(x, y, w, h)` / `Machine.PutBlock x, y, w, h, B [, key]` / `Machine.FreeBlock B` | 矩形を取り出して番号で持つ（16 個まで。使い終わったら `FreeBlock`） |
| `Machine.TAttr(fg [, bg [, flags]])` / `Machine.TextAttr = a` / `Machine.TextColor fg [, bg]` | 文字の属性 |
| `Machine.Locate x, y` / `Machine.TextPut x, y, s$ [, attr]` / `Machine.TextAttrAt x, y, attr` / `Machine.TextGet(x, y)` / `Machine.TextClear [attr]` | 文字の位置・置き方 |
| `Machine.VideoInfo(鍵)` `Machine.SysInfo(鍵)` `Machine.Mouse(鍵)` `Machine.Tablet(鍵)` `Machine.Pad(i, 鍵)` `Machine.Storage(i, 鍵)` | 機械の状態を 1 つずつ（鍵は Ruby の Hash と同じ名前の文字列。`Pad(i, "connected")`・軸は `"axis0"`〜`"axis5"`） |
| `Machine.HeapReserve n` / `Machine.HeapInfo(鍵)` | ヒープの最小値を n バイトに（64KB〜4MB）。鍵は `"min"` `"total"` `"free"` `"peak"` |
| `Machine.PadButton(i, n)` `Machine.PadPressed(i, n)` `Machine.PadReleased(i, n)` | パッドのボタン（`Machine.PAD_A` など） |
| `Machine.PadDirX(i)` / `PadDirY(i)` / `PadStickX(i, "left")` / `PadStickY(i, "left")` / `PadAxis(i, a)` | 向き（-1/0/1）・スティック（-1.0〜1.0） |
| 定数 `Machine.TEXT_*` `Machine.KEY_*` `Machine.PAD_*` | Ruby と同じ値（`Machine.TEXT_BG_TRANSPARENT`・`Machine.KEY_F12` など） |

**ローレゾ**（モード 3〜6）: `Machine.LrPalette pal, i, r, g, b`、`Machine.LrPattern tile, data$`（1 バイト 1 画素の文字列。**255 バイトまでなので、
大きな絵は 128 バイト = 2 タイルずつ** `tile`・`tile + 2`…に分けて書く）、`Machine.LrMap pl, tx, ty, tile [, pal [, hflip [, vflip]]]`（**タイル 0〜1023、パレット 0〜15**）、
`Machine.LrMapGet(pl, tx, ty, "tile")`、`Machine.LrFillMap` `Machine.LrScroll` `Machine.LrBgVisible`、`Machine.LrObj i, x, y, tile, w, h [, pal, pri]`
`Machine.LrObjMove` `Machine.LrObjHide` `Machine.LrObjVisible b`、`Machine.LrClear` `Machine.LrBackdrop` `Machine.LrRaster` `Machine.LrRasterWave pl, table$, phase`
（表は 255 段まで）`Machine.LrRasterClear`、`Machine.LrTiles` `Machine.LrPalettes`。ファイラーから走らせると 32KB のパターン（512 タイル）・パレット 32 本で開く。

**ビットマップ**（モード 7）: `Machine.BmClear` `Machine.BmPSet` `Machine.BmPGet`（外は -1）`Machine.BmLine` `Machine.BmRect` `Machine.BmFillRect`
`Machine.BmPalette i, r, g, b` `Machine.BmWrite(off, s$)`（書いた数。末尾をはみ出した分は切る）`Machine.BmRead(off, n)`。

### GPIO / PIO2 / MIDI（2026-11-11）

- `Machine.GpioInit pin`、`Machine.GpioSetDir pin, out`、`Machine.GpioSetPull pin, pull`、
  `Machine.GpioSetFunction pin, func`、`Machine.GpioPut pin, v`、`Machine.GpioGet(pin)`。
  ピンは 0〜47。C ボードで空いているのは GP34〜41（GP44/45 はコンソール、42/43 は MIDI、46/47 は ADC）。
- `Machine.Pio2Available`、`Machine.Pio2SmClaim sm`、`Machine.Pio2Insn i, w`、
  `Machine.Pio2Load(n)`、`Machine.Pio2SmConfig sm, off [, div, frac, top, bottom, join]`、
  `Machine.Pio2SmPins ...`、`Machine.Pio2SmShift ...`、`Machine.Pio2SmEnable sm, on`、
  `Machine.Pio2SmPut sm, v`、`Machine.Pio2SmGet(sm)`（空なら -1）、`Machine.Pio2SmUnclaim sm`。
  PIO2 は 1 プログラムが占有し、終わると SM・命令・FIFO をファームが片づける。使えるピンは 16〜47。
- `Machine.MidiAvailable` / `MidiUSB` / `MidiRead([n])` / `MidiWrite s$` /
  `MidiSetRoute in, out`（bit0 = DIN、bit1 = USB）。
- `Machine.MusicPlay "file"[, loop]` / `MusicStop` / `MusicPause` / `MusicVolume` /
  `MusicPosition` / `MusicLength`（VGM/VGZ・MP3/OGG/WAV）。
- `Machine.AdcPins`（使えるピンの数）/ `Machine.AdcPin(i)`（ピン番号）、`Machine.AdcCanRead(pin)`、
  `Machine.AdcRead(pin)`（0〜4095）、`Machine.AdcStart [l, r]`（96kHz の連続取り込み。C の A6/A7 は
  `Machine.AdcStart 40, 41`）、`Machine.AdcStop`、`Machine.AdcActive`、
  `Machine.AdcStats("peak0")`（鍵: frames dropped underruns fifo_over peak0 peak1 dc0 dc1）。
  `Machine.AdcTemperature` は RP2350 内蔵温度センサ（℃）。ADC 使用中は -999。
  ADC は 1 つなので、`AdcStart` の間の `AdcRead` は -16（EBUSY）。

ピンを使わない PIO2 の自己テスト:

```basic
R = Machine.Pio2SmClaim(0)
R = Machine.Pio2Insn(0, 32928)
R = Machine.Pio2Insn(1, 41159)
R = Machine.Pio2Insn(2, 32800)
OFF = Machine.Pio2Load(3)
R = Machine.Pio2SmConfig(0, OFF, 1, 0, OFF + 2, OFF, 0)
R = Machine.Pio2SmEnable(0, 1)
R = Machine.Pio2SmPut(0, 305419896)
FOR I = 1 TO 1000
  G = Machine.Pio2SmGet(0)
  IF G >= 0 THEN GOT = G
NEXT I
R = Machine.Pio2SmEnable(0, 0)
R = Machine.Pio2SmUnclaim(0)
```

### FB・ビットマップ・画像の描画（2026-11-13、`SPEC_gfx.md`）

Ruby・Python と同じ描画のメソッドを、BASIC の名前にしてある。**FrameBuffer のものは `Machine` に直接**、
**ビットマップは `Bm`**、**画像は `Img`（先頭に取っ手）**が付く。

- FrameBuffer（モード 2〜6）: `Machine.ResetDrawing` `Machine.FbRgb(r, g, b)` `Machine.Pen c[, w, style]` `Machine.PenExt cap, join`
  `Machine.Brush c[, style]` `Machine.Bk mode[, c]` `Machine.Rop2 r` `Machine.FillRule r` `Machine.Aa on` `Machine.Clip [l, t, r, b]`
  `Machine.Matrix a, b, c, d, e, f` `Machine.Concat ...` `Machine.ResetMatrix` `Machine.GetMatrix(i)`
- 線と図形: `Machine.MoveTo` `LineTo` `Polyline` `PolylineTo` `PolyBezier` `PolyBezierTo` `Arc` `ArcTo` `Pie` `Chord`
  `AngleArc` `Rectangle` `Ellipse` `RoundRect` `Polygon` `PolyPolygon`
  （点は引数で最大 8 組。引数なしなら点のバッファ `Machine.PtClear` / `Machine.PtAdd x, y, ...` / `Machine.PtBreak`。
  `PolyPolygon` は `PtBreak` で輪を区切る）
- パス: `Machine.BeginPath` `EndPath` `ClosePath` `PathMoveTo` `PathLineTo` `PathQuadTo` `PathCubicTo` `PathArc`
  `Machine.FillPath` `StrokePath` `FillStrokePath`
- 転送: `Machine.Bitblt`（元は 0 = FB、1 = ビットマップ、または画像の取っ手）`Machine.StretchBlt` `Machine.DrawDib`
- 文字: `Machine.Font` `Machine.FbTextColor` `Machine.TextOut` `Machine.ExtTextOut` `Machine.DrawText`（`Machine.TextExtentW` / `TextExtentH`）
- ビットマップ（モード 7）: 同じ名前に `Bm` を付ける（`Machine.BmPen` `Machine.BmRectangle` `Machine.BmTextOut` …）。
  色は `Machine.BmRgb`、文字の色は `Machine.BmTextColor`
- 画像: `ImgNew(w, h[, fmt])` / `ImgLoad(path$[, fmt])`（取っ手。負なら失敗）、`ImgWidth(h)` `ImgHeight(h)` `ImgFormat(h)`
  `ImgPSet h, x, y, c` `ImgPGet(h, x, y)` `ImgClear h[, c]` `ImgFree h`、描画は `Machine.ImgEllipse h, ...` のように取っ手を先頭に
- 見本: `samples/basic/gfx.bas`、デモ `samples/basic/gfxdemo.bas`

## 6. ファイル

GW-BASIC の形: `OPEN "名前" FOR INPUT / OUTPUT / APPEND AS #1`、`PRINT #1, ...`、`INPUT #1, A$`、`LINE INPUT #1, A$`、`EOF(1)`、`CLOSE #1`、
ランダムファイル（`OPEN ... AS #1 LEN = 64`・`FIELD`・`GET` / `PUT`）。`KILL`（消す）・`NAME 古い AS 新しい`・`MKDIR` `RMDIR` `CHDIR`・`FILES`。
パスは**プログラムのフォルダからの相対**か `S:/...` のような絶対パス。開いたファイルは中身をメモリに持ち、`CLOSE` で書き戻す。

### 圧縮と書庫（Machine.Arc*、2026-11-17、ABI 5.12）

BASIC の文字列はバイト列をそのまま持てないので、**メモリどうしの圧縮・展開は無い**。ファイルと書庫だけ。

- `Machine.ArcCompressFile in$, out$[, fmt[, level]]` / `Machine.ArcDecompressFile in$, out$`（.gz / .bz2 / .xz / .lzma）。
- `n = Machine.ArcList(path$)` -> 項目の数。`Machine.ArcName(i)` `ArcSize(i)` `ArcCsize(i)` `ArcMtime(i)` `ArcCrc(i)` `ArcDir(i)`
  （0 始まり）。書庫は名前で見分ける（.zip / .7z / .tar / .tar.gz / .tar.bz2 / .tar.xz / .tar.lzma）。
- `Machine.ArcExtract path$[, dest$[, only$]]` -> 書いたファイル数。
- `Machine.ArcCreate path$, "a;b;c"[, method[, level]]` -> 入れた数。`method` は ZIP のときだけ（`ARC_STORE` `ARC_DEFLATE` `ARC_BZIP2` `ARC_LZMA`）。
- `Machine.ArcWhy` -> 直前の誤りの理由（英語）。誤りは **負の数**。
- 定数: `ARC_STORE` `ARC_DEFLATE` `ARC_ZLIB` `ARC_GZIP` `ARC_BZIP2` `ARC_LZMA` `ARC_XZ`。
- 作業場は PSRAM（ファームが取る）。足りなければ段を下げ、FB を出していないときは FB の 4 ページを借りて、返すときに 0 で消す。
- 長い呼び出しは **ESC で止められる**。

## 7. 音とネットワーク

- **`Sound`**（Ruby と同じ口）: `Sound.Wave 0, 3`・`Sound.Adsr 0, 0, 40, 100, 40`・`Sound.NoteOn 0, 69, 110`・`Sound.NoteOff 0`、
  曲は `OK = Sound.Play("WTF4CH.mid", -1)`（-1 = くり返し。ファイルが無ければ 0）、`Sound.Playing` `Sound.Paused` `Sound.Pause` `Sound.Resume` `Sound.Stop` `Sound.Length`
- **`Socket`**: `DIM S AS NEW Socket`・`R = S.Connect("example.com", 80)`（TLS は `S.ConnectTls`）・`S.WriteLine "..."`・`S.ReadLine()`・`S.Close`。見本 `S:/sgbasic/socket.bas`

## 8. 速さの目安（実機で測った値、2026-11-01）

`samples/basic/bench.bas`（`samples/ruby/bench.rb` と同じ項目。実機は `S:/testapp`）。

| 内容 | モード 1 | モード 2（RGB555 表示） | モード 4（CLUT4 表示） | （参考）Ruby / Python のモード 2 |
|---|---|---|---|---|
| 空の `WHILE`（`I = I + 1`）10 万回 | 0.48 秒 | 1.63 秒 | 0.60 秒 | 0.36 / 0.51 秒 |
| `Machine.PSet` 1 万回 | - | 1.31 秒 | 0.48 秒 | 0.87 / 0.33 秒 |
| `Machine.FillRect`（64x48）1000 回 | - | 0.60 秒 | 0.14 秒 | 0.51 / 0.53 秒 |
| `Machine.Line`（端から端）1000 回 | - | 0.39 秒 | 0.32 秒 | 0.37 / 0.31 秒 |
| `Machine.FillTriangle`（64x48）1000 回 | - | 0.80 秒 | 0.26 秒 | 0.73 / 0.56 秒 |
| `Machine.FillTriangle`（画面の半分）100 回 | - | 2.1 秒 | 0.30 秒 | 2.2 / 2.5 秒 |
| `Machine.Triangle`（大きな外枠）1000 回 | - | 1.0 秒 | 0.78 秒 | 1.0 / 0.92 秒 |
| `Machine.Blit` 64x48 1000 回（透明色なし / あり） | - | 4.2 / 3.7 秒 | 1.3 / 2.0 秒 | 3.9 / 3.7 秒（なし） |
| `GetBlock` / `PutBlock` 64x48 1000 回 | - | 3.0 / 1.9 秒 | 1.0 / 1.5 秒 | 3.6 / 4.2 秒（get） |
| `Machine.FbClear` 100 回 | - | 3.7 秒 | 0.34 秒 | 3.3 / 3.7 秒 |

| プログラム | BASIC | Ruby | Python |
|---|---|---|---|
| マンデルブロ（80x24 の文字、`mandel.bas`） | 1.11 秒 | 0.43 秒 | 0.74 秒 |
| hat（`SQR`・`COS` で点を約 1 万、`hat.bas`） | 15.1 秒 | 10.5 秒 | 12.0〜15.1 秒 |
| 640x480 のマンデルブロ（`m640.bas`） | 69.3 秒 | 50.6 秒 | 94.0 秒 |

- BASIC は式の計算が Ruby・Python より遅い（空ループで約 3〜4 倍）。描く命令の重さは 3 つともほぼ同じ（ファームの同じ処理）
- FB を表示している間は遅い（モード 2 はモード 1 の約 3.4 倍）。計算の多い絵はモード 4〜6 で
- 起動（読み込みとコンパイル）は 500 行・DATA 1,500 項目のプログラムで約 1 秒

## 9. 制限のまとめ

1. `\` `MOD` `AND` `OR` は 16 ビット（§3.4）。大きな数は `INT()` で
2. 文字列は 255 バイトまで（ローレゾのパターン・波の表も 255 バイトずつ）
3. IF は 1 行だけ。SUB / FUNCTION は呼ぶ所より前に。SUB の中の変数は全体で共通
4. メソッド名の直後が `(` の引数に注意（§3.5）
5. 予約語は語の単位（`FORI=1TO10` は通らない）

## 10. ひな形

```basic
' Title: what this program does
DEFDBL A-Z
Machine.Mode = 2
Machine.TextVisible = 0
Machine.FbClear 0
T0 = Machine.Ms
Machine.FillRect 100, 100, 200, 100, Machine.RGB(255, 128, 0)
Machine.Line 0, 0, 639, 479, Machine.RGB(255, 255, 255)
Machine.TextVisible = -1
PRINT "done in"; (Machine.Ms - T0) / 1000; "s"
```

```basic
' animation: 10 seconds
DEFDBL A-Z
Machine.Mode = 2
Machine.FbClear 0
X = 0: C = Machine.RGB(0, 255, 255): T0 = Machine.Ms
WHILE Machine.Ms - T0 < 10000
    Machine.FillRect X, 200, 40, 40, 0      ' erase the old one
    X = X + 4: IF X >= 600 THEN X = 0
    Machine.FillRect X, 200, 40, 40, C      ' draw the new one
    Machine.VSync
WEND
```

## 11. AI に書かせるときの指示（そのまま渡せる要約）

- SG BASIC R03（GW-BASIC に近い BASIC + VB 風の SUB / FUNCTION / CLASS）。行番号は省いてよく、飛び先はラベル（`NAME:`）
- **予約語は空白で区切る**（`FOR I = 1 TO 10`）。IF は 1 行だけ。**SUB / FUNCTION は呼ぶ前に定義**、変数は全体で共通、値渡しは `BYVAL`
- **`\` `MOD` `AND` `OR` は 16 ビット整数**。ミリ秒などの大きな数は `INT(A / B)` で。先頭に `DEFDBL A-Z` を置く。文字列は 255 バイトまで
- 画面は `Machine.Mode = 2` にしてから `Machine.PSet` `Machine.Line` `Machine.FillRect`（色は `Machine.RGB(r, g, b)`、640x480）。名前は Ruby の Machine から `_` と `?` を取る（`Machine.PadPressed(0, Machine.PAD_A)`）。ローレゾは `Machine.Lr…`、ビットマップは `Machine.Bm…`
- 値を返すメソッドはかっこ付き（`K = Machine.Key`、無ければ -1）。メソッド名の直後を `(` で始めない
- 状態は鍵で 1 つずつ（`Machine.VideoInfo("frames")`）
- 音は `Sound.NoteOn ch, note, vel`・`OK = Sound.Play("x.mid", -1)`
- 経過時間は `Machine.Ms`、待ちは `Machine.VSync`、乱数は `RND(1)`

## 付録: 確かめに使ったもの

- ホストの試験 `make -C src/basic test`（R03 の決まりを含む）、R02 と同じ命令が出ることの照合（`src/basic/tests/dumpcode.c`）
- 実機の `samples/basic/bench.bas`（速さ）、`samples/machine_api/api.bas`（Ruby・Python と同じ出力）、テスト用アプリ `samples/basic/testapp/`（`scripts/make_testapp_bas.py`）
- 言語の全部: `src/basic/docs/LANGUAGE.md`
