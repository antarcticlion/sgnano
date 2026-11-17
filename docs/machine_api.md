# Machine API — the three languages side by side (2026-11-01)

mruby, MicroPython and SG BASIC offer the same `Machine` methods. Ruby is the
reference; the others follow these spelling rules:

- **Python**: the Ruby name without `?` (`pad_pressed?` → `pad_pressed`). Ruby
  `x=` setters are properties (`Machine.mode = 3`) or the same name with an argument.
- **BASIC**: the Ruby name without `_` and `?`, case-insensitive
  (`pad_pressed?` → `PadPressed`). FrameBuffer methods sit on `Machine` itself
  (`Machine.PSet`); LowRes methods get the prefix `Lr` (`Machine.LrObj`), Bitmap
  methods `Bm` (`Machine.BmPSet`). Ruby setters are assignments (`Machine.Mode = 3`).
- What Ruby returns as a **Hash** (`video_info`, `sys_info`, `mouse`, `tablet`,
  `pad(i)`, `storage(i)`) BASIC returns one field at a time:
  `Machine.VideoInfo("frames")`, `Machine.Pad(0, "hat")`, `Machine.Storage(0, "mb")`
  (the same key names). Pairs (`pad_dir`, `pad_stick`, `cursor`) are split:
  `PadDirX(i)` / `PadDirY(i)`, `PadStickX(i[,side[,dead]])` / `PadStickY(...)`,
  `CursorX` / `CursorY`.
- Constants: Ruby `Machine::TEXT_BOLD`, Python `Machine.TEXT_BOLD`, BASIC
  `Machine.TEXT_BOLD` (all three spellings of each are listed once below).
- Booleans: Ruby / Python `true` / `false`; BASIC `-1` / `0`.

Status column: ✓ = present. Anything missing is a bug — add it.

## Machine

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `mode` / `mode=` | `mode` (property), `set_mode` | `Mode` (`=`), `Screen` | 0..7 |
| `fb_visible?` / `fb_visible=` | `fb_visible` (property) | `FbVisible` (`=`) | |
| `text_visible?` / `text_visible=` | `text_visible` (property) | `TextVisible` (`=`) | |
| `lowres_small?` / `lowres_small=` | `lowres_small` (property) | `LowresSmall` (`1` / `0`、引数なしで読む) | 2026-11-13: 次の画面モードの切り替えで、ローレゾ面はパターン 16KB でよい。立てないと借りずに開く形は 32KB・16 本以上で、テキスト面のあるモード 3〜6 では VGM の合成の区画を借り、VGM を鳴らせない。VGM を同時に鳴らすプログラム（jumps_vgm）は立てる。SGX は `SGX_MODE_LR_SMALL` |
| `vsync([n])` | `vsync([n])` | `VSync [n]` | also updates the pad snapshot |
| `rgb(r,g,b)` | `rgb(r,g,b)` | `RGB(r,g,b)` | 0..255 each → pixel value |
| `fb` | `fb` | (methods on `Machine`) | FrameBuffer |
| `bitmap` | `bitmap` | (`Bm*`) | Bitmap (mode 7) |
| `lowres` | `lowres` | (`Lr*`) | LowRes (modes 3..6) |
| `ms` | `ms` | `Ms` | ms since boot |
| `clock_set?` | `clock_set` | `ClockSet` | NTP has set the clock |
| `key` | `key` | `Key` | nil / None / -1 when none |
| `wait_key` | `wait_key` | `WaitKey` | |
| `clear_keys` | `clear_keys` | `ClearKeys` | |
| `keyboard?` | `keyboard` | `Keyboard` | |
| `key_down?(k)` | `key_down(k)` | `KeyDown(k)` | |
| `key_name(k)` | `key_name(k)` | `KeyName(k)` | |
| `video_info` | `video_info` | `VideoInfo(key)` | keys: timing mode_name fb line_hz frame_hz frames underrun fifo_stall recover late_start late_render pair_max (BASIC: pair_max0 / pair_max1) |
| `sys_info` | `sys_info` | `SysInfo(key)` | keys: uptime mem_free mem_largest usb_devices hubs pads usb_reinit usb_wedged keyboard kbd_vid kbd_pid kbd_leds mouse |
| `heap_reserve(n)` | `heap_reserve(n)` | `HeapReserve n` / `Machine.HeapReserve(n)` | raise the minimum heap (64KB default, 4MB max); returns the reserved total |
| `heap_info` | `heap_info()` | `HeapInfo("key")` | keys: min total used free (BASIC: min total free peak) |
| `heap_total` / `heap_free` / `heap_min` | — | — | Ruby only (Python: `heap_info()`) |
| `mouse` | `mouse` | `Mouse(key)` | keys: connected buttons x y wheel |
| `tablet` | `tablet` | `Tablet(key)` | keys: connected ready name proximity tool x y pressure x_max y_max pressure_max tip button1 button2 pad wheel |
| `pad(i)` | `pad(i)` | `Pad(i, key)` | nil when not connected (BASIC: `Pad(i,"connected")`); keys: vid pid hat buttons buttons_n axes (BASIC: axis0..axis5) |
| `storage(i)` | `storage(i)` | `Storage(i, key)` | keys: vendor product mb (BASIC: "connected" too) |
| `pad_update` | `pad_update` | `PadUpdate` | |
| `pad_button?(i,n)` | `pad_button(i,n)` | `PadButton(i,n)` | n = `PAD_*` |
| `pad_pressed?(i,n)` | `pad_pressed(i,n)` | `PadPressed(i,n)` | |
| `pad_released?(i,n)` | `pad_released(i,n)` | `PadReleased(i,n)` | |
| `pad_dir(i)` | `pad_dir(i)` | `PadDirX(i)` / `PadDirY(i)` | -1 / 0 / 1 |
| `pad_axis(i,a[,dead])` | `pad_axis(i,a[,dead])` | `PadAxis(i,a[,dead])` | -1.0..1.0 with dead zone |
| `pad_stick(i,side[,dead])` | `pad_stick(i,side[,dead])` | `PadStickX` / `PadStickY` | side "left" / "right" |
| `text_attr` / `text_attr=` | `text_attr()` / `set_text_attr` | `TextAttr` (`=`) | |
| `tattr(fg[,bg[,flags]])` | `tattr(...)` | `TAttr(...)` | |
| `text_color(fg[,bg])` | `text_color(...)` | `TextColor fg[,bg]` | |
| `locate(x,y)` | `locate(x,y)` | `Locate x,y` | |
| `cursor` | `cursor` | `CursorX` / `CursorY` | |
| `text_clear([attr])` | `text_clear([attr])` | `TextClear [attr]` | |
| `text_put(x,y,s[,attr])` | `text_put(...)` | `TextPut x,y,s[,attr]` | |
| `text_attr_at(x,y,attr)` | `text_attr_at(...)` | `TextAttrAt x,y,attr` | |
| `text_get(x,y)` | `text_get(x,y)` | `TextGet(x,y)` | Ruby / Python: [char, attr]; BASIC: the character (`TextAttrAt(x,y)` reads the attribute) |
| `text_cols` / `text_rows` | `text_cols` / `text_rows` | `TextCols` / `TextRows` | |
| `pages` | `pages` | `Pages` | |
| `display_page` / `=` | `display_page` (property) | `DispPage` (`=`) | |
| `write_page` / `=` | `write_page` (property) | `WritePage` (`=`) | |
| `fb_palette(i[,r,g,b])` | `fb_palette(...)` | `FbPalette(i[,r,g,b])` | get: [r,g,b] (BASIC: RGB555 value) |
| `Machine::GPIO` | `machine.GPIO` | (`Machine.Gpio*`) | GPIO (SIO) — see below |
| `Machine::PIO2` | `machine.PIO2` | (`Machine.Pio2*`) | PIO2 — see below |
| `Machine::ADC` | `machine.ADC` | (`Machine.Adc*`) | ADC — see below |
| `Machine::Music` | `machine.Music` | (`Machine.Music*`) | music player — see below |
| `Machine::MIDI` | `machine.MIDI` | (`Machine.Midi*`) | MIDI — see below |

Python: `machine.Music` / `machine.MIDI` / `machine.GPIO` / `machine.PIO2` are **namespace
instances**, not types (MicroPython's type objects apply a self-type check to built-in
functions with arguments). The prelude also exposes them as `M.Music` / `M.MIDI` /
`M.GPIO` / `M.PIO2`.

## Music (`Machine::Music` / `machine.Music` / `Machine.Music*`)

The firmware music port (ABI 4.4): VGM/VGZ, MP3, OGG and WAV are played by the
background task. It is separate from `Sound` (the SMF/SGT sequencer); the
music stream uses port 0, so the game sound effects should use another port.

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `Machine::Music.play(path[,loop])` | `machine.Music.play(path[,loop])` | `Machine.MusicPlay path[,loop]` | 0 = started, negative = error; loop is a boolean |
| `Machine::Music.stop` | `machine.Music.stop()` | `Machine.MusicStop` | |
| `Machine::Music.pause(on)` | `machine.Music.pause(on)` | `Machine.MusicPause on` | |
| `Machine::Music.playing?` | `machine.Music.playing()` | `Machine.MusicPlaying` | |
| `Machine::Music.paused?` | `machine.Music.paused()` | `Machine.MusicPaused` | |
| `Machine::Music.volume(v)` | `machine.Music.volume(v)` | `Machine.MusicVolume v` | 0..127 |
| `Machine::Music.seek(ms)` | `machine.Music.seek(ms)` | `Machine.MusicSeek ms` | VGM cannot seek |
| `Machine::Music.position` / `length` | `...position()` / `length()` | `Machine.MusicPosition` / `MusicLength` | ms |
| `Machine::Music.format` | `...format()` | `Machine.MusicFormat` | `MUSIC_MP3` / OGG / WAV / VGM |
| `Machine::Music.title` | `...title()` | `Machine.MusicTitle` | VGM GD3 title, or the file name |
| `Machine::Music.underruns` / `load` | `...underruns()` / `load()` | `Machine.MusicUnderruns` / `MusicLoad` | VGM only |

Constants: Ruby `Machine::Music::LOOP` / `MP3` / `OGG` / `WAV` / `VGM`,
Python `machine.Music.LOOP` etc., BASIC `Machine.MUSIC_LOOP` etc.

## MIDI (`Machine::MIDI` / `machine.MIDI` / `Machine.Midi*`)

C ボードの DIN MIDI（UART1 GP42/43、31250 8N1）と USB MIDI ホスト。
経路のビットは DIN = 1、USB = 2。

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `Machine::MIDI.available?` | `machine.MIDI.available()` | `Machine.MidiAvailable` | C のみ true |
| `Machine::MIDI.usb?` | `machine.MIDI.usb()` | `Machine.MidiUSB` | USB MIDI ホストが接続中 |
| `Machine::MIDI.bytes` | `machine.MIDI.bytes()` | `Machine.MidiBytes` | 読めるバイト数 |
| `Machine::MIDI.read([max])` | `machine.MIDI.read([max])` | `Machine.MidiRead [n]` | バイト列（BASIC は文字列） |
| `Machine::MIDI.write(s)` | `machine.MIDI.write(s)` | `Machine.MidiWrite s$` | 書けたバイト数 |
| `Machine::MIDI.input_route` / `output_route` | `...input_route()` / `output_route()` | `Machine.MidiInputRoute` / `MidiOutputRoute` | bit0 DIN, bit1 USB |
| `Machine::MIDI.set_route(in,out)` | `machine.MIDI.set_route(in,out)` | `Machine.MidiSetRoute in,out` | |

Constants: `Machine::MIDI::DIN` / `USB`, `machine.MIDI.DIN` / `USB`,
BASIC `Machine.MIDI_DIN` / `MIDI_USB`.

## GPIO (`Machine::GPIO` / `machine.GPIO` / `Machine.Gpio*`)

SIO の入出力。ピンは 0〜47。空きピンは基板で違う（C ボードは GP34〜41、P ボードは GP42/43・GP46/47。
GP44/45 はコンソール、C の 42/43 は MIDI、46/47 は ADC）。PSRAM・VGA・音源・基板判別に使っているピンは触らないこと。

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `Machine::GPIO.init(pin)` | `machine.GPIO.init(pin)` | `Machine.GpioInit pin` | 入力、プル無し |
| `Machine::GPIO.set_dir(pin, out)` | `machine.GPIO.set_dir(pin, out)` | `Machine.GpioSetDir pin,out` | true = 出力 |
| `Machine::GPIO.set_pull(pin, pull)` | `machine.GPIO.set_pull(pin, pull)` | `Machine.GpioSetPull pin,pull` | `PULL_NONE` / `PULL_UP` / `PULL_DOWN` |
| `Machine::GPIO.set_function(pin, func)` | `machine.GPIO.set_function(pin, func)` | `Machine.GpioSetFunction pin,func` | `FUNC_SIO` = 5、`FUNC_PIO2` = 8、`FUNC_NULL` = 0x1F |
| `Machine::GPIO.put(pin, v)` | `machine.GPIO.put(pin, v)` | `Machine.GpioPut pin,v` | |
| `Machine::GPIO.get(pin)` | `machine.GPIO.get(pin)` | `Machine.GpioGet(pin)` | パッドのレベル |

Constants: Ruby `Machine::GPIO::IN` / `OUT` / `PULL_*` / `FUNC_*`、Python `machine.GPIO.*`、BASIC `Machine.GPIO_*`。

## PIO2 (`Machine::PIO2` / `machine.PIO2` / `Machine.Pio2*`)

PIO2 をユーザーに開放したもの。PIO0 は映像、PIO1 は音源 0〜3 が使う。PIO2 は 1 つのプログラムが占有し、
終わるとファームが SM・命令メモリ・FIFO を片づける。GPIOBASE は 16 なので使えるピンは 16〜47。
命令は pioasm（RP2350、絶対ピン番号）の 16 ビット語をそのまま渡す。

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `available?` | `available()` | `Machine.Pio2Available` | このプログラムが使えるか |
| `load([words])` | `load([words])` | `Machine.Pio2Insn i,w` → `Machine.Pio2Load(n)` | 載せた位置（0〜31）を返す |
| `insn(i, w)` / `load_staged(n)` | 同左 | 同上 | 配列を渡せない言語用 |
| `gpio_init(pin)` | `gpio_init(pin)` | `Machine.Pio2GpioInit pin` | ピンを PIO2 の入力に（16〜47） |
| `sm_claim(sm)` / `sm_unclaim(sm)` | 同左 | `Machine.Pio2SmClaim` / `Pio2SmUnclaim` | SM 0〜3 |
| `sm_config(sm, off[, div_int, div_frac8, wrap_top, wrap_bottom, fifo_join])` | 同左 | `Machine.Pio2SmConfig sm,off[,div,frac,top,bottom,join]` | 初期設定 |
| `sm_pins(sm[, out_base, out_count, set_base, set_count, in_base, sideset_base, sideset_count, sideset_opt, sideset_pindirs, jmp_pin])` | 同左 | `Machine.Pio2SmPins ...` | ピンの割り当て |
| `sm_shift(sm[, out_dir, out_auto, out_thresh, in_dir, in_auto, in_thresh])` | 同左 | `Machine.Pio2SmShift ...` | シフト |
| `sm_clkdiv(sm, div[, frac8])` | 同左 | `Machine.Pio2SmClkdiv ...` | 分周を後から変える |
| `sm_enable(sm, on)` | 同左 | `Machine.Pio2SmEnable sm,on` | |
| `sm_restart` / `sm_clear_fifos` / `sm_drain_tx` | 同左 | `Machine.Pio2SmRestart` / `SmClearFifos` / `SmDrain` | |
| `sm_exec(sm, insn)` | 同左 | `Machine.Pio2SmExec sm,insn` | 命令を 1 つ実行 |
| `sm_put(sm, v)` / `sm_get(sm)` | 同左 | `Machine.Pio2SmPut` / `Pio2SmGet` | 待たない。Ruby/Python の get は空なら nil / None |
| `sm_tx_level` / `sm_rx_level` / `sm_tx_full?` / `sm_rx_empty?` | 同左 | `Pio2SmTxLevel` / `Pio2SmRxLevel` / `Pio2SmTxFull` / `Pio2SmRxEmpty` | FIFO の状態 |
| `sm_set_pins(sm, base, values, count)` | 同左 | `Machine.Pio2SmSetPins ...` | bit0 = base |
| `sm_set_pindirs(sm, base, dirs, count)` | 同左 | `Machine.Pio2SmSetPindirs ...` | 1 = 出力 |
| `irq_flags` / `irq_clear(mask)` | 同左 | `Machine.Pio2IrqFlags` / `Pio2IrqClear` | PIO2 の IRQ（下位 8 ビット） |

Constants: `SM_MAX` = 4、`PIN_MIN` = 16、`PIN_MAX` = 47、`FIFO_JOIN_NONE` / `FIFO_JOIN_TX` / `FIFO_JOIN_RX`、
`SHIFT_RIGHT` / `SHIFT_LEFT`。

ピンを使わない自己テスト（`pull block` / `mov isr, osr` / `push block`）:

```ruby
pio = Machine::PIO2
pio.sm_claim(0)
off = pio.load([0x80A0, 0xA0C7, 0x8020])
pio.sm_config(0, off, 1, 0, off + 2, off, 0)
pio.sm_enable(0, true)
pio.sm_put(0, 0x12345678)
v = nil
1000.times { v = pio.sm_get(0); break if v }
pio.sm_enable(0, false)
pio.sm_unclaim(0)
```

## ADC (`Machine::ADC` / `machine.ADC` / `Machine.Adc*`)

P ボードは GP40/41（ADC0/1、L/R）。C ボードは GP46/47（ADC6/7、専用 L/R）と GP40/41（A6/A7、ADC0/1）を選べる。
単発の読み取りと、96kHz のステレオ入力をボイス 0 で鳴らす連続取り込みがある。ADC は 1 つなので、
連続取り込みの間は `read` が `-EBUSY` になる。

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `Machine::ADC.pins` | `machine.ADC.pins()` | `Machine.AdcPins` / `AdcPin(i)` | 使えるピン（C: 40,41,46,47 / P: 40,41） |
| `Machine::ADC.can_read?(pin)` | `machine.ADC.can_read(pin)` | `Machine.AdcCanRead(pin)` | |
| `Machine::ADC.read(pin)` | `machine.ADC.read(pin)` | `Machine.AdcRead(pin)` | 0〜4095、負 = エラー |
| `Machine::ADC.start(l=0, r=0)` | `machine.ADC.start(l=0, r=0)` | `Machine.AdcStart [l, r]` | 0,0 = 基板の既定 L/R。C の A6/A7 は 40,41 |
| `Machine::ADC.stop` | `machine.ADC.stop()` | `Machine.AdcStop` | |
| `Machine::ADC.active?` | `machine.ADC.active()` | `Machine.AdcActive` | |
| `Machine::ADC.stats` | `machine.ADC.stats()` | `Machine.AdcStats("peak0")` | frames dropped underruns fifo_over peak0 peak1 dc0 dc1 |
| `Machine::ADC.temperature` | `machine.ADC.temperature()` | `Machine.AdcTemperature` | RP2350 内蔵温度センサ（℃）。ADC 使用中は nil / None / -999 |

`start` の `l` は低い側（偶数チャンネル）、`r = l + 1`。`stats` の peak は読むと 0 に戻る。
ADC として使ったピンは `Machine::GPIO.init(pin)` で GPIO に戻せる。
温度は RP2350 の内蔵センサ（ADC のチャンネル 8）。ADC 使用中は読めない。
生の波形を 1 ブロック取り込む `adc_capture` は SGX ABI だけ（3 言語は単発・連続・stats・温度まで）。

## FrameBuffer (`Machine.fb`)

| Ruby | Python | BASIC |
|---|---|---|
| `width` / `height` | ✓ | `Width` / `Height` |
| `bits_per_pixel` / `bytes_per_pixel` | ✓ | `BitsPerPixel` (`Bits`) / `BytesPerPixel` |
| `clear([c])` | ✓ | `Cls [c]` / `FbClear [c]` |
| `pset(x,y,c)` / `pget(x,y)` | ✓ | `PSet` / `PGet` |
| `line` / `rect` / `fill_rect` | ✓ | `Line` / `Rect` / `FillRect` |
| `triangle` / `fill_triangle` | ✓ | `Triangle` / `FillTriangle` |
| `blit(sx,sy,w,h,dx,dy[,page[,key]])` | ✓ | `Blit ...` |
| `get_block(x,y,w,h)` | ✓ (bytes) | `GetBlock(x,y,w,h)` → a block number |
| `put_block(x,y,w,h,data[,key])` | ✓ | `PutBlock x,y,w,h,block[,key]` |

## LowRes (`Machine.lowres`)

| Ruby | Python | BASIC |
|---|---|---|
| `ready?` / `width` / `height` / `tiles` / `palettes` | ✓ | `LrReady` / `LrWidth` / `LrHeight` / `LrTiles` / `LrPalettes` |
| `palette(pal,i,r,g,b)` | ✓ | `LrPalette pal,i,r,g,b` (or `LrPalette(pal,i[,rgb555])`) |
| `pattern(tile,data)` | ✓ | `LrPattern tile,data$` (or per dot `LrPattern(tile,x,y[,c])`) |
| `map(pl,tx,ty,tile[,pal,h,v])` / `map_get` | ✓ | `LrMap pl,tx,ty,tile[,pal,h,v]` / `LrMapGet(pl,tx,ty[,"tile"/"pal"/"hflip"/"vflip"])` (no key: the raw 16-bit cell) |
| `fill_map(pl,tile[,pal])` | ✓ | `LrFillMap` |
| `scroll(pl,x,y)` | ✓ | `LrScroll` |
| `bg_visible(pl,on)` | ✓ | `LrBgVisible` (`LrShow`) |
| `obj_visible=` | ✓ (property) | `LrObjVisible on` (`LrObjShow`) |
| `obj(i,x,y,tile,w,h[,pal,pri,h,v])` | ✓ | `LrObj` |
| `obj_move` / `obj_hide` / `obj_get` | ✓ | `LrObjMove` / `LrObjHide` / `LrObjGet(i,key)` |
| `clear` / `raster_clear` | ✓ | `LrClear` / `LrRasterClear` |
| `backdrop(y,r,g,b)` / `raster(pl,y,clut,sx,sy)` | ✓ | `LrBackdrop` / `LrRaster` |
| `raster_wave(pl,table,phase)` | ✓ | `LrRasterWave pl,table$,phase` |

## Bitmap (`Machine.bitmap`, mode 7)

| Ruby | Python | BASIC |
|---|---|---|
| `ready?` / `width` / `height` | ✓ | `BmReady` / `BmWidth` / `BmHeight` |
| `clear` / `pset` / `pget` / `line` / `rect` / `fill_rect` | ✓ | `BmClear` / `BmPSet` / `BmPGet` / `BmLine` / `BmRect` / `BmFillRect` |
| `palette(i[,r,g,b])` | ✓ | `BmPalette` |
| `read(off,n)` / `write(off,s)` | ✓ | `BmRead(off,n)` / `BmWrite off,s$` (past the end: cut off, returns the count written) |

## Primitive drawing (2026-11-13, `SPEC_gfx.md`)

The same methods on `Machine.fb` (FrameBuffer), `Machine.bitmap` (Bitmap, mode 7) and `Machine::Image`.
Ruby / Python return the surface from the state and drawing methods, so calls chain (`fb.pen(c).brush(c2).ellipse(...)`).
BASIC: FrameBuffer members sit on `Machine` (`Machine.Ellipse`), the bitmap ones get `Bm` (`Machine.BmEllipse`), an image's get
`Img` with the handle first (`Machine.ImgEllipse h, ...`). `text_color` and `rgb` already belong to the text plane / Machine, so the
FrameBuffer ones in BASIC are `FbTextColor` / `FbRgb` (the bitmap and image ones are `BmTextColor` / `ImgTextColor`, `BmRgb` / `ImgRgb`).
Points: Ruby / Python take `[x0, y0, x1, y1, ...]` or `[[x0, y0], ...]`; BASIC takes up to 8 pairs as arguments, or none to use the
point buffer (`PtClear`, `PtAdd x, y, ...`, `PtBreak` between the contours of `PolyPolygon`, `PtCount`).

| Ruby | Python | BASIC | Notes |
|---|---|---|---|
| `reset_drawing` / `rgb(r,g,b)` | ✓ | `ResetDrawing` / `FbRgb(r,g,b)` | rgb: 0..31 to the surface's value (CLUT: the nearest palette number) |
| `pen(c[,w,style])` / `pen_ext(cap,join)` | ✓ | `Pen` / `PenExt` | `PS_*`, `CAP_*`, `JOIN_*`; width 1..64 |
| `brush(c[,style])` / `bk(mode[,c])` | ✓ | `Brush` / `Bk` | `BS_*` (solid, null, six hatches), `BK_TRANSPARENT` / `BK_OPAQUE` |
| `rop2(r)` / `fill_rule(r)` / `aa(on)` / `clip([l,t,r,b])` | ✓ | `Rop2` / `FillRule` / `Aa` / `Clip` | `R2_*`, `FILL_NONZERO` / `FILL_EVENODD`; clip with no arguments = whole surface |
| `matrix(a,b,c,d,e,f)` / `concat(...)` / `reset_matrix` / `get_matrix` | ✓ | `Matrix` / `Concat` / `ResetMatrix` / `GetMatrix(i)` | for the path coordinates only |
| `move_to` / `line_to` | ✓ | `MoveTo` / `LineTo` | |
| `polyline(pts)` / `polyline_to` / `poly_bezier` / `poly_bezier_to` | ✓ | `Polyline` / `PolylineTo` / `PolyBezier` / `PolyBezierTo` | bezier: 1 + 3k points |
| `arc` / `arc_to` / `pie` / `chord` `(l,t,r,b,xs,ys,xe,ye)` | ✓ | `Arc` / `ArcTo` / `Pie` / `Chord` | counter-clockwise from the start ray to the end ray |
| `angle_arc(x,y,r,start,sweep)` | ✓ | `AngleArc` | degrees |
| `rectangle` / `ellipse(l,t,r,b)` / `round_rect(l,t,r,b,ew,eh)` | ✓ | `Rectangle` / `Ellipse` / `RoundRect` | right and bottom are not included |
| `polygon(pts)` / `poly_polygon([pts, ...])` | ✓ | `Polygon` / `PolyPolygon` | |
| `begin_path` / `end_path` / `close_path` | ✓ | `BeginPath` / `EndPath` / `ClosePath` | |
| `path_move_to` / `path_line_to` / `path_quad_to` / `path_cubic_to` / `path_arc(cx,cy,r,a0,a1)` | ✓ | `PathMoveTo` / … / `PathArc` | Float coordinates through the matrix |
| `fill_path` / `stroke_path` / `fill_stroke_path` | ✓ | `FillPath` / `StrokePath` / `FillStrokePath` | |
| `bitblt(dx,dy,w,h,src[,sx,sy,rop,key])` | ✓ | `Bitblt` (src: 0 = fb, 1 = bitmap, or an image handle) | `SRCCOPY` … `WHITENESS`; key = transparent value |
| `stretch_blt(dx,dy,dw,dh,src,sx,sy,sw,sh[,rop,key])` | ✓ | `StretchBlt` | negative width / height mirrors |
| `draw_dib(dx,dy,dw,dh,bits,fmt,w,h[,palette,rop])` | ✓ (bytes) | `DrawDib dx,dy,dw,dh,bits$,fmt,w,h` | `DIB_*` |
| `font([face,height,weight,flags,escapement])` | ✓ | `Font` | `FONT_ROM` / `FONT_8X8`, `FW_*`, `FF_*`, escapement 0/900/1800/2700 |
| `text_color(c[,align,extra])` | ✓ | `FbTextColor` | `TA_*` |
| `text_out(x,y,s)` / `ext_text_out(x,y,opt,rect,s[,dx])` | ✓ | `TextOut` / `ExtTextOut x,y,opt,l,t,r,b,s$` | `ETO_OPAQUE`, `ETO_CLIPPED` |
| `draw_text(s,l,t,r,b[,flags])` | ✓ | `DrawText(...)` | the height; with `DT_CALCRECT` Ruby / Python return `[l,t,r,b]` |
| `text_extent(s)` | ✓ (tuple) | `TextExtentW(s$)` / `TextExtentH(s$)` | |

`Machine::Image`: Ruby `Machine::Image.new(w,h[,fmt])` / `.load(path[,fmt])`, Python `M.Image(w,h[,fmt])` / `M.Image.load(...)`,
BASIC `ImgNew(w,h[,fmt])` / `ImgLoad(path$[,fmt])` (a handle, negative on failure). `width` / `height` / `format`, `pset` / `pget`,
`clear([c])`, `free` (BASIC `ImgWidth(h)` … `ImgFree h`). Files: PNG, JPEG, GIF (the first picture), TIFF; `fmt` is `FMT_RGB555`
or `FMT_CLUT8` (the nearest colours of the FB palette). Images are freed when the program ends.
Checks: `samples/ruby/gfx.rb` / `samples/python/gfx.py` / `samples/basic/gfx.bas`; demos `gfxdemo.*` and `apps/gfxdemo`.
