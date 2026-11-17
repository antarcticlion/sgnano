# sgnano Python プログラミング仕様書（MicroPython 環境）

版: 2026-11-17 ／ 対象: sgnano のファームウェア（RP2350B、MicroPython v1.29.0）

この文書は、sgnano で動く Python のプログラムを**ほかの人や AI が書く**ための仕様書です。使える書き方・モジュール・メソッドは、
**実機で一つずつ確かめたもの**です（推測ではありません）。ここに無いものは「無い」と考えてください。

同じ機械を Ruby（mruby）と SG BASIC からも使えます。画面・音・パッドの口（`Machine`）は 3 つの言語で同じ名前・同じ働きにそろえてあり、
対応表は `docs/machine_api.md`、それぞれの仕様書は `docs/sgnano_ruby_guide.md`・`docs/sgnano_basic_guide.md` です。
**`Machine` のメソッドの細かい働き（引数の範囲・画面モードの組み合わせ・負荷の目安）は Ruby の仕様書の §7・§9 と同じ**なので、そちらも参照してください。
この文書は Python で違うところを中心に書きます。

【2026-11-17】**FB・ビットマップ・画像の描画**（線・図形・パス・文字・転送、§5）と**圧縮と書庫**（`machine.Archive`、§6）を足した（ABI 5.3・5.12）。

---

## 1. 環境のあらまし

| 項目 | 内容 |
|---|---|
| 処理系 | MicroPython v1.29.0（組み込み向けの Python 3）。ソースは本体の中でコンパイルする |
| 画面 | Ruby と同じ: テキスト面（80 桁 x 30 行。上 28 行が出力の端末、最下行が状態の行）、フレームバッファ（FB、640x480、RGB555・CLUT8・CLUT4、4 ページ）、ローレゾ面（320x240、BG 2 面 + オブジェクト 128 個）、ビットマップ（320x200x8）。`M.mode` の画面モード 0〜7。始めはモード 1 |
| メモリ | ヒープ 512KB（PSRAM）、スタック 64KB |
| 整数 | **大きさの制限なし**（小さな数は 47 ビットのまま、大きな数は自動で多倍長。`2**100` も正しい） |
| 浮動小数 | **倍精度**（CPython と同じ精度。`1/3` は `0.3333333333333333`） |
| 文字列 | UTF-8（`len` は文字数）。**文字列の中の `\u` のエスケープは使えない**（ファイル全体が SyntaxError になる）。日本語はそのまま書く |
| 入力 | `M.key()`（1 つずつ、無ければ None）・`M.wait_key()`・`M.key_down(k)`。**`input()` は無い**。**ESC は実行を止める** |
| 出力 | `print` は画面の端末（上 28 行）と、開発用のシリアルの両方へ |

## 2. プログラムの置き場と実行

- ドライブ（FAT・exFAT・NTFS・S:）に拡張子 `.py` で置き、ファイラーで選んで **Enter**。始めは**画面モード 1**（テキストだけ）
- 実行中は最下行が状態の行（「running (ESC: stop)」）。**ESC** で止める（計算だけのループも止まる。`KeyboardInterrupt` になる）
- 終わると「finished  コンパイル 0.006 秒  実行 0.738 秒 -- press any key」。何かキーでファイラーへ戻る。画面モード・FB の表示とページは実行前に戻る
- ファイラーの **p** で REPL。`>>>` のあとに打って Enter、続きの行は `...`。REPL の入力を待っている間の ESC は REPL を抜ける
- 構文の誤り・捕まえなかった例外は、端末に Traceback が出る
- **`import` はファイルから読まない**（`import mylib` は ImportError）。プログラムは 1 つのファイルに書く。組み込みのモジュールは import できる（§4）
- 始めから使える名前: **`M`**（`Machine()` の 1 つ。`M.mode = 2` のように使う）、`Machine`、`Sound`、`File`（`File.exist(path)`）、`Dir`（`Dir.pwd()`）、`machine`（下回りのモジュール）

### 2.1 シェルから使う（2026-11-02）

ファイラーで **x** を押すとシェル **sgsh** が開く。MicroPython のコマンドは UNIX 版に寄せてある。

```
micropython [opts] [-c command | file] [args...]
micropython -c 'print(1+2)'          # 1 行のプログラム
micropython -c 'import sys; print(sys.argv)' x y   # ['-c', 'x', 'y']
micropython file.py a b              # sys.argv = [file.py, 'a', 'b']
micropython                          # REPL（>>>。Ctrl-D で終わり）
micropython -i file.py               # 走ったあと REPL に残る
micropython -X compile-only file.py  # 文法だけ（何も走らせない）
```

- `python` / `python3` は `micropython` の別名（`alias` で上書きできる）
- `file.py` のように**拡張子だけで**走らせられる。`run file.py a b` でも同じ
- パイプ・リダイレクト・stdin がそのまま使える: `echo 'print(42)' | micropython`、`micropython file.py > out.txt`
- 出力はシェルの端末、Traceback は stderr。`$status` は正常 0、例外・誤り・Ctrl-C は 1
- 実行中に **Ctrl-C**（または Shift+ESC）で子だけを止めてシェルへ戻る。画面モード 2〜7 を使った子は、終わりにモード 1 へ戻して描き直す
- `mpy-cross` はこのファームではビルドしていない（`.mpy` は使えない。`mpy-cross` はその旨を出して終わる）

## 3. 言語として使える書き方

確かめて**使える**もの: `class`（継承・`super()`・`__init__`・特殊メソッド）、関数（既定の引数・キーワード引数・`*args`・`**kw`）、`lambda`、
ジェネレータ（`yield`）、内包表記（リスト・辞書・集合）、`try` / `except ... as e` / `finally`、`with`（自分の `__enter__` / `__exit__`）、
`:=`、`async def`、多重代入、スライス、`%` 書式（`'%05.2f' % x`）、`str.format`（`'{:>5}'.format(s)`）、bytes / bytearray、大きな整数。

**無い**もの（代わりの書き方）:

| 書き方 | 代わりに |
|---|---|
| f 文字列（`f"{x}"`） | `"{}".format(x)` か `"%d" % x` |
| `input()` | `M.key()` / `M.wait_key()` で 1 つずつ読む |
| `import` で自分のファイル | 1 つのファイルに書く |
| 文字列の `\uXXXX` | 字をそのまま書く |

## 4. モジュール

実機で import して確かめた。

| ある | 中身 |
|---|---|
| `math` | `sqrt` `sin` `cos` `tan` `atan2` `exp` `log` `pi` `e` など（倍精度） |
| `time` | `sleep` `sleep_ms` `ticks_ms` `ticks_diff` など |
| `random` | `random` `randint` `randrange` `choice` `seed` |
| `array` `struct` `collections` | `array('f', ...)`・`struct.pack` / `unpack`・`namedtuple` / `OrderedDict` / `deque` |
| `framebuf` | MicroPython の標準（自分の bytearray に描く。画面の FB とは別） |
| `gc` `sys` | `gc.collect()` `gc.mem_free()`、`sys.exit()` |
| `os` | ファイル（§6） |
| `fft` | `fft.fft(re, im, inverse=False)`: `array('f')` の実部・虚部をその場で変換（2〜4096 点、2 のべき乗。アセンブラで 4096 点 15ms 前後） |
| `socket` | TCP と TLS 1.2 のクライアント（§9） |
| `machine` | 下回り（ふだんは `M` を使う） |

| `json` | `dumps` / `loads`、ファイルへは `json.dump(obj, f)` / `json.load(f)`（2026-11-01） |
| `io` | `StringIO` / `BytesIO`（2026-11-01） |
| `errno` | `errno.ENOENT` など。`open` の失敗は `e.errno` で比べられる（2026-11-01） |
| `binascii` | `hexlify` / `unhexlify` / `b2a_base64` / `a2b_base64`（`crc32` は無い）。`bytes.hex()` / `bytes.fromhex()` も（2026-11-01） |
| `hashlib` | `sha256` / `sha1`（`.digest()`。中身はファームの mbedTLS。`md5` は無い。2026-11-01） |
| `heapq` | `heappush` / `heappop` / `heapify`（2026-11-01） |
| `cmath` | 複素数（`1j`・`abs(3+4j)`・`cmath.sqrt` `exp` `phase` など。2026-11-01） |

**無い**: `re` `select` `asyncio`。

### ヒープ（2026-11-03）
MicroPython のヒープは 64KB の面から始まり、VM の分岐で空きを数えて、空きが 32KB を切ると
PSRAM に 64KB の面を足す。空きが 128KB 以上になると GC が空いた面を返す。
大きな配列を先に確保したいときは、スクリプトの始めで最小値を上げる。

```python
import machine
machine.heap_reserve(512 * 1024)   # 512KB を必ず確保する
print(machine.heap_info())         # {'min': ..., 'total': ..., 'used': ..., 'free': ...}
```

`heap_reserve(n)` は 64KB〜4MB。戻り値は、いま確保してある合計（バイト）。
`total` は PSRAM で予約した合計、`free` は GC が使える空き。

## 5. 画面: Machine（`M`）

**名前は Ruby の `Machine` から `?` を取ったもの**（`key_down?` -> `key_down`、`pad_pressed?` -> `pad_pressed`）。Ruby で `x=` の書き込みは、
Python では属性への代入（`M.mode = 3`、`M.write_page = 1`）。Ruby の `nil` は `None`、`true` / `false` は `True` / `False`。
Ruby の Hash を返すもの（`video_info` など）は dict（鍵は文字列: `v["frames"]`）。

| 書き方 | 意味 |
|---|---|
| `M.mode = n` / `M.mode` | 画面モード 0〜7（0 なし・1 テキスト・2 + RGB555・3 + ローレゾ + CLUT8・4 + ローレゾ + CLUT4・5 テキスト + ローレゾ・6 ローレゾだけ・7 テキスト 25 行 + 320x200x8） |
| `M.fb_visible = b` / `M.text_visible = b` | FB・テキスト面を見せる / 隠す |
| `M.vsync(n=1)` | n フレーム待つ（パッドの状態もここで写す） |
| `M.rgb(r, g, b)` | 0..255 から画素の値 |
| `M.ms()` | 起動からのミリ秒 |
| `M.key()` / `M.wait_key()` / `M.clear_keys()` | 次のキー（無ければ None）/ 待って返す / 捨てる |
| `M.key_down(k)` / `M.keyboard()` / `M.key_name(k)` | 押しているか（USB キーボードだけ）/ つながっているか / 表示用の名前 |
| `M.pages()` / `M.display_page` / `M.write_page` | FB のページ数（4）/ 表示するページ / 描くページ（代入で切り替え） |
| `M.fb_palette(i[, r, g, b])` | CLUT8・CLUT4 の色（読むと `[r, g, b]`） |
| `M.clock_set()` | 時計を NTP で合わせたか |
| `M.video_info()` `M.sys_info()` `M.mouse()` `M.tablet()` `M.pad(i)` `M.storage(i)` | 機械の状態（dict。つながっていない `pad` / `storage` は None） |

**FrameBuffer**（`fb = M.fb`）: `fb.width` `fb.height` `fb.bits_per_pixel` `fb.bytes_per_pixel`（属性）、`fb.clear(c=0)` `fb.pset(x, y, c)`
`fb.pget(x, y)`（外は None）`fb.line` `fb.rect` `fb.fill_rect` `fb.triangle` `fb.fill_triangle` `fb.blit(sx, sy, w, h, dx, dy[, page[, key]])`
（`page` を None にすれば描くページ）、`fb.get_block(x, y, w, h)` -> bytes、`fb.put_block(x, y, w, h, data[, key])`。

**テキスト**: `M.tattr(fg, bg=0, flags=0)`、`M.text_attr()` / `M.set_text_attr(a)`、`M.text_color(fg, bg=None)`、`M.locate(x, y)`、`M.cursor()`、
`M.text_put(x, y, s[, attr])`、`M.text_attr_at(x, y, attr)`、`M.text_get(x, y)`（`(字, 属性)`）、`M.text_clear([attr])`、`M.text_cols()` / `M.text_rows()`。
定数 `M.TEXT_*`（色 0〜15 と印。`TEXT_BOLD` `TEXT_UNDERLINE` `TEXT_REVERSE` `TEXT_BLINK` `TEXT_DOUBLE_WIDTH` `TEXT_DOUBLE_HEIGHT` `TEXT_BG_TRANSPARENT` `TEXT_CLEAR` `TEXT_DEFAULT` など）と `M.KEY_*`（`KEY_UP` `KEY_F1` など）は Ruby と同じ値。
端末への `print` も Ruby と同じく ANSI のエスケープ列（`"\x1b[1;31m"`）を扱う。

**ローレゾ**（`lr = M.lowres`、モード 3〜6）: `lr.palette(pal, color, r, g, b)`、`lr.pattern(tile, data)`（bytes / bytearray）、
`lr.map(plane, tx, ty, tile, pal=0, hflip=False, vflip=False)`（**タイル 0〜1023、パレット 0〜15**）、`lr.map_get(plane, tx, ty)` -> `(tile, pal, hflip, vflip)`、
`lr.fill_map` `lr.scroll` `lr.bg_visible`、`lr.obj_visible = b`、`lr.obj(i, x, y, tile, w, h, pal=0, pri=0, hflip=False, vflip=False)` `lr.obj_move` `lr.obj_hide` `lr.obj_get`、
`lr.clear` `lr.backdrop` `lr.raster` `lr.raster_wave(plane, table, phase)` `lr.raster_clear`、`lr.width` `lr.height` `lr.tiles` `lr.palettes` `lr.ready`。
**Python ではローレゾ面を 32KB のパターン（512 タイル）・パレット 16 本で開く**（SRAM の都合）。

**ビットマップ**（`bm = M.bitmap`、モード 7）: `bm.clear` `bm.pset` `bm.pget` `bm.line` `bm.rect` `bm.fill_rect` `bm.palette(i[, r, g, b])` `bm.write(off, data)` `bm.read(off, n)`、`bm.width` `bm.height` `bm.ready`。

**パッド**: `M.vsync()` のたびに写す（使わないなら `M.pad_update()`）。`M.pad_button(i, n)` `M.pad_pressed(i, n)` `M.pad_released(i, n)`、`M.pad_dir(i)` -> `(dx, dy)`、
`M.pad_stick(i, "left"/"right", dead=0.15)` -> `(x, y)`（-1.0〜1.0）、`M.pad_axis(i, a, dead=0.15)`、定数 `M.PAD_A` など（F310 の D モードの並び）。

### GPIO / PIO2 / MIDI / 音楽（2026-11-11）

`machine.GPIO` / `machine.PIO2` / `machine.MIDI` / `machine.Music` は**名前空間のインスタンス**。
prelude では `M.GPIO` / `M.PIO2` / `M.MIDI` / `M.Music` でも使える（型ではないので
`machine.PIO2.sm_claim(0)` のように引数付きで呼べる）。

- `machine.GPIO.init(pin)` / `set_dir(pin, out)` / `set_pull(pin, pull)` /
  `set_function(pin, func)` / `put(pin, v)` / `get(pin)`。ピンは 0〜47。
  C ボードで空いているのは GP34〜41（GP44/45 はコンソール、42/43 は MIDI、46/47 は ADC）。
- `machine.PIO2.available()`、`load([語, ...])`（pioasm の 16 ビット語。置いた位置を返す）、
  `sm_claim(sm)` / `sm_unclaim(sm)`、`sm_config(sm, off[, div, frac, top, bottom, join])`、
  `sm_pins(...)`、`sm_shift(...)`、`sm_enable(sm, on)`、`sm_put(sm, v)` / `sm_get(sm)`
  （待たない。空なら `None`）、`sm_set_pins(...)` / `sm_set_pindirs(...)`。
  PIO2 は 1 プログラムが占有し、終わると SM・命令・FIFO をファームが片づける。使えるピンは 16〜47。
- `machine.MIDI.available()`（DIN）/ `usb()`（USB MIDI ホスト）/ `read([max])` /
  `write(bytes)` / `set_route(in, out)`（bit0 = DIN、bit1 = USB）。
- `machine.Music.play(path[, loop])` / `stop()` / `pause(on)` / `playing()` /
  `position()` / `length()`（VGM/VGZ・MP3/OGG/WAV）。
- `machine.ADC.pins()`（C は `[40,41,46,47]`、P は `[40,41]`）、`can_read(pin)`、`read(pin)`（0〜4095）、
  `start(l=0, r=0)`（96kHz の連続取り込み。C の A6/A7 は `start(40, 41)`）、`stop()`、`active()`、
  `stats()`（dict: `frames` `dropped` `underruns` `fifo_over` `peak0` `peak1` `dc0` `dc1`）。
  `temperature()` は RP2350 内蔵温度センサ（℃、float）。ADC 使用中は None。
  ADC は 1 つなので、`start` の間の `read` はエラー（`-16` = EBUSY）。

```python
pio = M.PIO2
pio.sm_claim(0)
off = pio.load([0x80A0, 0xA0C7, 0x8020])   # pull block / mov isr, osr / push block
pio.sm_config(0, off, 1, 0, off + 2, off, 0)
pio.sm_enable(0, True)
pio.sm_put(0, 0x12345678)
v = None
for _ in range(1000):
    v = pio.sm_get(0)
    if v is not None:
        break
pio.sm_enable(0, False)
pio.sm_unclaim(0)
```

### FB・ビットマップ・画像の描画（2026-11-13）

`M.fb`（FrameBuffer）、`M.bitmap`（モード 7）、`M.Image` は**同じ描画のメソッド**を持つ（Ruby と同じ名前）。
状態と描画のメソッドは自分を返すので続けて書ける（`M.fb.pen(c).brush(c2).ellipse(0, 0, 639, 479)`）。

- 状態: `reset_drawing` `rgb(r, g, b)` `pen(c[, w, style])` `pen_ext(cap, join)` `brush(c[, style])` `bk(mode[, c])`
  `rop2(r)` `fill_rule(r)` `aa(on)` `clip([l, t, r, b])` `matrix(a, b, c, d, e, f)` `concat(...)` `reset_matrix` `get_matrix`
- 線と図形: `move_to` `line_to` `polyline(pts)` `polyline_to` `poly_bezier` `poly_bezier_to` `arc` `arc_to` `pie` `chord(...)`
  `angle_arc(x, y, r, start, sweep)` `rectangle` `ellipse(l, t, r, b)` `round_rect(l, t, r, b, ew, eh)` `polygon(pts)` `poly_polygon([pts, ...])`。
  点は `[x0, y0, x1, y1, ...]` か `[[x0, y0], ...]`。右と下の端は含まない
- パス: `begin_path` `end_path` `close_path` `path_move_to` `path_line_to` `path_quad_to` `path_cubic_to` `path_arc(cx, cy, r, a0, a1)`
  `fill_path` `stroke_path` `fill_stroke_path`
- 転送: `bitblt(dx, dy, w, h, src[, sx, sy, rop, key])` `stretch_blt(...)` `draw_dib(..., bits, ...)`（bits は bytes）
- 文字: `font([face, height, weight, flags, escapement])` `text_color(c[, align, extra])` `text_out(x, y, s)` `ext_text_out(...)`
  `draw_text(...)`（`DT_CALCRECT` で `(l, t, r, b)`）`text_extent(s)`（tuple）
- `M.Image(w, h[, fmt])` / `M.Image.load(path[, fmt])`、`width` `height` `format` `pset` `pget` `clear([c])` `free`。
  PNG・JPEG・GIF（1 枚目）・TIFF、`FMT_RGB555` / `FMT_CLUT8`
- 見本: `samples/python/gfx.py`、デモ `samples/python/gfxdemo.py`。
  **α1 の実機では、この 2 つは構文の誤り（`syntax error, unexpected ':'`）で止まる（既知の不具合）**。
  口（`M.fb` などのメソッド）はファームに入っている。

## 6. ファイル（os）

| 書き方 | 中身 |
|---|---|
| `open(path, mode="r")` | ふつうの Python の形（`with open(p) as f:`・`for line in f`・`read` `readline` `readlines` `write` `seek` `tell`、モードは `r` `w` `a` `x` と `b`・`+`）。中身は丸ごとメモリに持ち、閉じるとき（`with` を抜けるとき）に書き戻す。無いファイルは `OSError`（`errno.ENOENT`） |
| `os.read_file(path)` -> bytes | 丸ごと読む |
| `os.write_file(path, data)` | 丸ごと書く（str か bytes） |
| `os.listdir([path])` / `os.stat(path)` / `os.getcwd()` | 一覧 / 大きさなど / いまのフォルダ |
| `os.remove` `os.rename` `os.mkdir` | 消す・名前を変える・フォルダを作る |
| `File.exist(path)` / `Dir.pwd()` | ある？ / いまのフォルダ（Ruby に合わせた名前） |

- パスは**いまのフォルダからの相対**（始めはファイラーで開いていたフォルダ）か **`S:/...`** のような絶対パス
- 失敗は `OSError`
- `open` で書いたものは**閉じるまでドライブに書かれない**（`close()` を忘れない。`with` を使う）

### 圧縮と書庫（machine.Archive、2026-11-17、ABI 5.12）

- 方式（`fmt`）: `STORE` `DEFLATE` `ZLIB` `GZIP`（既定）`BZIP2` `LZMA` `XZ`。
- `machine.Archive.compress(b[, fmt[, level]])` -> bytes。level は 0〜9（既定 6）。
- `machine.Archive.decompress(b[, fmt])` -> bytes。fmt を省くと先頭のバイトから見分ける。**4MB まで**。
- `machine.Archive.compress_file(in, out[, fmt[, level]])` / `.decompress_file(in, out)`。
- `machine.Archive.list(path)` -> dict の list（`name` `size` `csize` `mtime` `crc` `dir`）。
- `machine.Archive.extract(path[, dest[, only]])` -> 書いたファイル数（フォルダは作り、同じ名前は置き換える）。
- `machine.Archive.create(path, paths[, method[, level]])` -> 入れた数。`method` は ZIP のときだけ。
- 作業場は PSRAM（ファームが取る）。足りなければ段を下げ、FB を出していないときは FB の 4 ページを借りて、返すときに 0 で消す。
- 長い呼び出しは **ESC で止められる**。誤りは `OSError`（理由は英語）。

## 7. 時間と乱数

`M.ms()`（経過ミリ秒）、`time.ticks_ms()`、`time.sleep_ms(n)`、`random.randint(a, b)`・`random.random()`・`random.seed(n)`。
`M.vsync()` でフレームに合わせて待つ。

## 8. 音: Sound

Ruby の `Sound` と同じ（`docs/sgnano_ruby_guide.md` §9）。Python では**メソッドとして呼ぶ**（`Sound.playing()`・`Sound.paused()`。`Sound.channels` だけは属性）。

```python
Sound.wave(0, Sound.SQUARE)
Sound.adsr(0, 0, 40, 90, 50)
Sound.note_on(0, 69, 110)      # A4
M.vsync(30)
Sound.note_off(0)

Sound.play("WTF4CH.mid", True)  # the BGM, repeated (a path or the bytes of the file)
while Sound.playing():
    if M.key() == ord("q"):
        break
    M.vsync()
Sound.stop()
```

## 9. ネットワーク（socket）

`s = socket.tcp(host, port, timeout=5000)` / `s = socket.tls(host, port, verify=False, ca=None, timeout=10000)`（TLS 1.2。`ca` に PEM を渡せば証明書を確かめる）。
返る口: `s.send(data)` `s.recv(n)` `s.available()` `s.peer()` `s.closed()` `s.close()`。LAN アダプタがつながっていて DHCP が済んでいること。
実機で `example.com:80` と `www.debian.org:443` が `HTTP/1.1 200 OK` を返した。

## 10. 速さの目安（実機で測った値、2026-11-01）

`samples/python/bench.py`（`samples/ruby/bench.rb` と同じ項目）。3 つの言語の比べは表の右。

| 内容 | モード 1 | モード 2（RGB555 表示） | モード 4（CLUT4 表示） | （参考）Ruby / BASIC のモード 2 |
|---|---|---|---|---|
| 空の `while`（`i += 1`）10 万回 | 0.15 秒 | 0.51 秒 | 0.19 秒 | 0.36 / 1.63 秒 |
| `fb.pset` 1 万回 | - | 0.33 秒 | 0.13 秒 | 0.87 / 1.31 秒 |
| `fb.fill_rect(x, y, 64, 48, c)` 1000 回 | - | 0.53 秒 | 0.10 秒 | 0.51 / 0.60 秒 |
| `fb.line`（端から端）1000 回 | - | 0.31 秒 | 0.38 秒 | 0.37 / 0.39 秒 |
| `fb.fill_triangle`（64x48）1000 回 | - | 0.56 秒 | 0.22 秒 | 0.73 / 0.80 秒 |
| `fb.fill_triangle`（画面の半分）100 回 | - | 2.5 秒 | 0.34 秒 | 2.2 / 2.1 秒 |
| `fb.triangle`（大きな外枠）1000 回 | - | 0.92 秒 | 0.98 秒 | 1.0 / 1.0 秒 |
| `fb.blit` 64x48 1000 回（透明色なし / あり） | - | 3.7 / 3.3 秒 | 1.6 / 2.6 秒 | 3.9 / 4.2 秒（なし） |
| `fb.get_block` / `put_block` 64x48 1000 回 | - | 4.2 / 1.1 秒 | 1.6 / 1.8 秒 | 3.6 / 3.0 秒（get） |
| `fb.clear` 100 回 | - | 3.7 秒 | 0.37 秒 | 3.3 / 3.7 秒 |

| プログラム | Python | Ruby | BASIC |
|---|---|---|---|
| マンデルブロ（80x24 の文字、`mandel.py`） | 0.74 秒 | 0.43 秒 | 1.11 秒 |
| hat（`math.sqrt`・`cos` で点を約 1 万、`hat.py`） | 12.0〜15.1 秒 | 10.5 秒 | 15.1 秒 |
| 640x480 のマンデルブロ（`m640.py`） | 94.0 秒 | 50.6 秒 | 69.3 秒 |

- FB を表示している間は遅い（表示が FB を読む間、プログラムを待たせるため。モード 2 は FB なしの約 3.5 倍）。計算の多い絵はモード 4〜6 で
- 1 点ずつの `pset` より `fill_rect`・`line` でまとめて描く。`blit` は元を PSRAM から読むので塗りより遅い
- 640x480 の全面を 1 点ずつ計算するような絵は、数十秒〜数分かかる

## 11. 制限のまとめ

1. `import` は組み込みのモジュールだけ（自分のファイルは読まない）。f 文字列・`input`・`\u` のエスケープ・`re` は無い
2. ヒープは 512KB。640x480 の画素を list に持つと足りない（bytearray で必要な分だけ）
3. 入力は `M.key()` / `M.wait_key()` / `M.key_down()`。ESC は実行を止める
4. 画面モードは 0〜7。ローレゾ面は 512 タイル・16 パレットで開く
5. 音はポート 4 つ（Ruby と同じ）

## 12. ひな形

```python
# Title: what this program does
M.mode = 2
M.text_visible = False
fb = M.fb
fb.clear()
t0 = M.ms()
fb.fill_rect(100, 100, 200, 100, M.rgb(255, 128, 0))
fb.line(0, 0, 639, 479, M.rgb(255, 255, 255))
M.text_visible = True
print("done in %.2f s" % ((M.ms() - t0) / 1000))
```

```python
# animation: 10 seconds
M.mode = 2
fb = M.fb
fb.clear()
x = 0
c = M.rgb(0, 255, 255)
t0 = M.ms()
while M.ms() - t0 < 10000:
    fb.fill_rect(x, 200, 40, 40, 0)     # erase the old one
    x = (x + 4) % 600
    fb.fill_rect(x, 200, 40, 40, c)     # draw the new one
    M.vsync()
```

## 13. AI に書かせるときの指示（そのまま渡せる要約）

- 処理系は MicroPython 1.29（Python 3 の書き方）。整数は大きさの制限なし、浮動小数は倍精度。**f 文字列・`input`・自分のファイルの `import`・文字列の `\u`・`re` は無い**
- 画面は始めから使える `M`（`M.mode = 2` にしてから `fb = M.fb` に描く。色は `M.rgb(r, g, b)`。640x480。ページ 4 枚: `M.write_page = 1` に描いて `M.display_page = 1` で見せる）
- メソッドの名前は Ruby の `Machine` から `?` を取ったもの（`M.key_down(k)`・`M.pad_pressed(0, M.PAD_A)`）。状態は dict（`M.video_info()["frames"]`）
- ローレゾ: `M.mode = 3`〜`6`、`lr = M.lowres`（`lr.pattern` `lr.map`（タイル 0〜1023・パレット 0〜15）`lr.obj` `lr.obj_move` `lr.scroll`）。512 タイル・16 パレット
- ビットマップ: `M.mode = 7`、`bm = M.bitmap`（320x200、`bm.write(y * 320 + x, data)` でまとめて）
- キー: `M.key()`（無ければ None）・`M.wait_key()`。ESC は使えない（実行を止める）
- ファイル: `with open(p, "w") as f: f.write(s)`・`json.dump(obj, f)`（閉じるとき書かれる）、`os.listdir()`、`File.exist(p)`。パスは相対か `S:/...`。`json` `hashlib`（sha256）`binascii` `heapq` `cmath` `errno` `io` がある
- 音: `Sound.note_on(ch, note, vel)`・`Sound.play("x.mid", True)`・`Sound.playing()`（メソッド）・`Sound.stop()`
- 経過時間は `M.ms()`、待ちは `M.vsync()`、乱数は `random`
- FB 表示中は遅い（空ループ 10 万回 0.5 秒、`pset` 1 回約 33µs、全面の `clear` 37ms）

## 付録: 確かめに使ったもの

- 実機の `samples/python/bench.py`（速さ）、モジュールと書き方の確かめ（2026-11-01、import と `exec` を 1 つずつ）
- `samples/machine_api/api.py`（`api.rb`・`api.bas` と同じ出力を出す。Machine の口の突き合わせ）
- 見本: `samples/python/testapp/`（mode0〜7・`jumps.py`・`shogi.py`・`pad.py`・`raster.py`・`sound.py`・`tablet.py`・`hat.py`・`mandel.py`・`m640.py`）
- 組み込みの仕組みは `docs/notes/micropython.md`
