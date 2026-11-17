# MicroPython（組み込み VM、2026-10-30）

sgnano のファームに MicroPython v1.29.0 のコアを組み込み、ファイラーから REPL と `.py` を走らせる。
mruby と同じく、VM のコードはフラッシュ、ヒープとスタックは PSRAM に置く。

## 構成

| | |
|---|---|
| コア | `third_party/micropython/`（`py/`・`extmod/`・`shared/`・`tools/` だけ。ports は使わない） |
| ポート | `src/python/`（`mpconfigport.h`・`mphalport.c`・`pyrun.c`・各モジュール） |
| ライブラリ | `src/python/Makefile` が `build_micropython/rp2350/libmicropython.a` を作る（`CROSS=1`） |
| ファーム | `CMakeLists.txt` の `micropython_lib` カスタムターゲット。`src/python/pyrun.c` をリンク |
| フラッシュ配置 | `ld/placement.cmake` が `libmicropython.a` と `python/pyrun.c` の `.text/.rodata` をフラッシュへ |
| ヒープ | **PSRAM 512KB**（`pmem_alloc`、`pyrun.c` の `PY_HEAP_BYTES`） |
| スタック | **PSRAM 64KB**（`pmem_alloc`、`PY_STACK_BYTES`） |

## 走らせ方

- ファイラーで **`p`**: MicroPython の REPL（端末は Ruby と同じ `rbterm`）
- ファイラーで **`.py` を Enter**: ファイルを読んで実行
- リモートコマンド:
  - `PYTHON` … REPL を開始
  - `PYRUN <path>` … `.py` を実行（例: `PYRUN S:/pytest.py`）
- 終了: REPL は Ctrl-D、実行中は ESC（`py_key` が止める） 【追記 2026-10-31】REPL の入力待ちの ESC も REPL を抜ける。下の同じ日の節

## モジュール

| モジュール | 内容 |
|---|---|
| `machine` | `delay` / `sleep_ms` / `sleep_us` / `ticks_ms` / `ticks_us` / `key` / `key_wait` / `text_write` / `text_puts` / `text_clear` / `cols` / `rows` |
| `os` | `listdir` / `stat` / `remove` / `rename` / `mkdir` / `read_file` / `write_file`。パスはファイラーのいまのフォルダからの相対か `S:/...` |
| `fft` | `fft(re, im, inverse=False)`。`array('f')` の実部・虚数をその場で変換（2〜4096 点、2 のべき乗） |
| `socket` | `socket.tcp(host, port, timeout=5000)` / `socket.tls(host, port, verify=False, ca=None, timeout=10000)`。返る `Socket` は `send` / `recv` / `close` / `closed` / `available` / `peer` |
| 標準 | `math` / `time` / `random` / `framebuf` など（コアと extmod の範囲） |

## 実機で確認したこと

- REPL: `print(1+2)` → `3`、`import math; print(math.sqrt(2))` → `1.4142135`
- FFT: 256 点インパルス → `FFT 1.0 0.0`
- TCP: `socket.tcp('example.com', 80)` → `HTTP/1.1 200 OK`
- TLS: `socket.tls('www.debian.org', 443, False, None)` → `HTTP/1.1 200 OK`
- TLS + CA: `socket.tls('www.debian.org', 443, True, CA)` → 接続成功（CA は ISRG Root X1）
- `os`: `S:/PYTEST.TXT` に書いて `b'hello'` で読める。`stat` / `listdir` / `remove` も動作

## 注意

- Python 実行中は `render_park_on` を立てる（Ruby / SGX と同じ）。TLS の PSRAM アクセスと表示の取得が重ならないようにするため
- `import` はまだファイルから読まない（`mp_import_stat` は「無い」を返す）。`.py` の本体実行と REPL は動く
- `os` の相対パスは、Python を始めたときのファイラーのフォルダが基準
- REPL の行入力で `[` が落ちる現象がある（`.py` ファイル実行では起きない）。原因は未調査
- コアの `mp_state_ctx` などは SRAM の `.bss`。ヒープは PSRAM なので、大きいデータは GC ヒープに置かれる

## ビルド

```sh
make -C src/python            # ホストの REPL（build_micropython/host/firmware.elf）
make -C src/python CROSS=1    # RP2350 の libmicropython.a
ninja -C build                # ファーム（micropython_lib が先に走る）
```

## 描画性能と SRAM の優先順位（2026-10-30）

**描画性能を最優先する。** 画素ごと・ラインごとに読むデータは SRAM に置く。

- SRAM に残す: `vga_ring`、パレット、ラインバッファ、ローレゾのパターン RAM・マップ・作業領域、テキストのグリフ面
- PSRAM へ移してよい: 1 秒に 1 回程度しか触らないもの（`mb_prof`）、
  使っていない間だけ返せる USB の受け場（`ufi_bounce` / `m5_bounce`）、ファイラーの言語表
- テキストの文字コード・属性（`ch` / `at`）は **SRAM のまま**。PSRAM に移すと Ruby のテキスト描画・書き込みに影響するため
- ローレゾ面が SRAM に載らないときだけ、LAN の受け場（約 7.7KB）を返して再試行する。Python 終了時に LAN を戻す
- `vga_raster` は SRAM のまま（PSRAM にすると表示帯域が増え、ZMODEM が壊れたため）

## ゲームの移植（2026-10-30）

- `samples/python/testapp/jumps.py`: `S:/testapp/jumps.rb` の移植。低レゾ（モード5）の背景・地形・
  コイン・敵・ゴール・HUD・効果音・BGM。キーボードの `key_down` とパッドで操作する
- `samples/python/testapp/shogi.py`: `S:/testapp/shogi.rb` の移植。テキスト面の将棋（Position / Engine / Game）。
  初期局面の合法手 30 手、αβ探索、定跡、成り・持ち駒・打ちを実装
- ゲーム用に `machine.key_down` / `clear_keys` / `keyboard` / `locate` / `cursor` と
  `Machine::TEXT_*` / `KEY_*` の定数を追加
- `PYKEY <10進>`: 回帰テスト用に Python へキーを 1 つ送る。ESC（27）は `KeyboardInterrupt` になり、
  `vsync` / `wait_key` / `key` のどこでもスクリプトを止める

## 状態の行と ESC（2026-10-31、ユーザー指示）

- **状態の行**: Ruby と同じくテキスト面の 29 行目（白地・青、`STATUS_ROW` / `C_STATUS`）。
  `.py` は「名前  running  (ESC: stop)」、REPL は「MicroPython REPL  (Ctrl-D or ESC: quit)」、ESC で「stopping...」。
  終わったら「名前  finished  コンパイル x 秒  実行 y 秒 -- press any key」を出し、**何かキーでファイラーへ戻る**
  （以前は終わるとすぐ戻り、出力が見えなかった）。時間は Ruby と同じ書き方（ミリ秒に四捨五入、0 なら「0.001 秒未満」）。
  モード 7（テキスト 25 行）・テキスト面を消したモード 6 では見えない（Ruby と同じ）
- **ESC**: `MICROPY_KBD_EXCEPTION` を入れ、実行中の ESC（と pyexec が渡す Ctrl-C）で `mp_sched_keyboard_interrupt()` を呼ぶ。
  VM が分岐のたびに見るので、**`while True: x += 1` のような計算だけのループも止まる**（以前は止まらなかった）。
  実行中かどうかは `mp_hal_set_interrupt_char`（pyexec が実行の前後に呼ぶ）と `run_source` で持つ（`PY.executing`）
- **REPL の入力待ちの ESC**: ここで `KeyboardInterrupt` を投げると受け手（nlr）が無く `nlr_jump_fail` で止まる。
  キーの読み出しが Ctrl-C（打ちかけを捨てる）-> Ctrl-D（REPL を抜ける）を返して抜ける。実行中の ESC は止めたあと続けて REPL も抜ける
- 実機（USB メモリ・S:）: `while True` のループ・`mandel.py`・`mode5.py`・`jumps.py` が ESC で止まり、キーでファイラーへ戻る。
  REPL はプロンプトで ESC、`while True: pass` の実行中に ESC（Traceback のあと抜ける）

## グリッチと速さ（2026-10-31、ユーザー指示: mandel.py が mandel.rb より著しく遅い）

### グリッチ: 起動のたびに fifo_stall が約 145 回
- `PYTHON` / `PYRUN` のたびに `fifo_stall` が 1 回の起動でまとめて約 145 回（ローレゾを使わない `pytest.py` でも、変更前の版でも）。終わりでは出ない。
- **原因**: `py_start` が、表示の取得の間 core1 を待たせる印（`render_park_on`）を**タスクを作ったあと**に立てていた。その前に PSRAM へ触る処理
  （ヒープ 512KB のキャッシュの行を捨てる・`mb_task_create` がスタック 64KB を 0xA5A5A5A5 で塗る）が待たせなしで走り、表示の取得とぶつかった。
- **対処**: `py_start` の頭で立てる（Ruby の `rbrun.c` と同じ順）。あわせて、ヒープ・スタック・ソースのキャッシュの古い行を、使う前と返すときに捨てる
  （以前は捨てておらず、汚れた行があとで次の持ち主の上へ書き戻されるおそれがあった）。起動 1 回あたり 145 -> 1 回（`pytest.py`）
- 見本の画面モードを切り替える分（1 回の切り替えで 7〜10 回）は Ruby と同じで残る

### 速さ: mandel.py 4.61 秒 -> 1.12 秒（mandel.rb は 0.58 秒）
| 手 | mandel.py |
|---|---:|
| 前（ファイラーのモード 2 のまま） | 4.61 秒 |
| **走らせる間はモード 1（FB なし）**（Ruby と同じ。FB を表示していると表示の取得のたびに core1 が待たされる） | 1.35 秒 |
| **`MICROPY_OPT_COMPUTED_GOTO`・`MICROPY_OPT_MAP_LOOKUP_CACHE`・`MICROPY_OPT_LOAD_ATTR_FAST_PATH`、VM と GC を `-O2`** | 1.12 秒 |
| （試しただけ）`MICROPY_OBJ_REPR_C`（float を 1 語に埋め込み、計算のたびに GC のヒープへ確保しない） | 0.64 秒 |

- `MICROPY_OBJ_REPR_C` は出力が mandel.rb と全行一致し速いが、**float の仮数部が 2 ビット減る**（`math.sqrt(2)` = 1.4142132、16777216.0 が 16777220.0、
  0.001 を 1000 回足すと 0.9999466）。**採らない**（2026-10-31 ユーザー判断: 精度を優先）
- 残りの差は、MicroPython の float が計算のたびに GC のヒープ（PSRAM）へ確保すること（REPR_A）と、VM のコードがフラッシュにあり PSRAM のヒープと XIP キャッシュを取り合うこと。
  VM（vm・runtime・objfloat・gc・map・obj で約 15KB）を SRAM に置く手は、ローレゾ面の SRAM が足りなくなるので採らない
- FPU は使えている（objfloat.o に VADD / VMUL）

## 倍精度（DCP）と NaN boxing（2026-10-31、ユーザー指示）
- **`MICROPY_FLOAT_IMPL_DOUBLE`**: Python の float を倍精度に。計算はファームの `--wrap` で pico_double の DCP の版へ（mruby と同じ。M33BEATOS が
  タスクごとに DCP の状態を切り替える）。精度は CPython と同じ（`1/3` = 0.3333333333333333、`math.sqrt(2)` = 1.4142135623730952、0.001 を 1000 回足して 1.0000000000000006）
- **`MICROPY_OBJ_REPR_D`（NaN boxing）**: 値（`mp_obj_t`）を 64 ビットにし、倍精度の数を GC のヒープへ確保せずに値のまま持つ。
  `mp_int_t` も 64 ビットになり、小さな整数は 47 ビット。大きな整数は MPZ（`objint_longlong.c` は 32 ビットの `mp_int_t` を前提にしていて使えない）
- 直したこと: `gc_collect` がスタックの長さを `sizeof(mp_uint_t)`（8 になる）で割っていて、根の半分しか調べなくなるところだった -> `sizeof(void *)`。
  ポインタと `mp_obj_t` の行き来は `MP_OBJ_FROM_PTR` / `MP_OBJ_TO_PTR`（例外の値・`os.listdir`）
- 実測（秒）:

  | スクリプト | 単精度（REPR_A） | 倍精度（REPR_A） | 倍精度 + REPR_D |
  |---|---:|---:|---:|
  | mandel.py | 1.115 | 1.155 | **0.867** |
  | m640.py | 46.11 | | **42.47** |
  | hat.py | **6.43** | | 9.69 |

  hat.py だけ遅くなった。1 点ごとに Python の `pset`・`rgb` を呼び、モード 2（FB を表示）で core1 が取得のたびに待たされる中で、
  値が 64 ビットになって増えた PSRAM の読み書き（呼び出しのフレームなど）が効いているとみる（倍精度の `cos`・`** 0.5` の分は 1 点 20µs 足らず）。未対処
- 1 万回の時間（ms、REPR_D、モード 1）: ループだけ 44、`math.cos` 85、`x ** 0.5` 146、`math.sqrt` 80、掛け算 58、整数 34
- 確かめ: GC を回しながらの確保・大きな整数・47 ビット・例外・文字列・`os`・`fft` の 17 項目、mode5・jumps・shogi・hat・m640

## S:/testapp の .py の画面の確かめ（2026-10-31、ユーザー報告: hat.py・m640.py の FB が出ない、jumps.py は遠景だけ）
- **FB が出ない**: モード 1・FB なしで始めるようにしたあと、`M.mode = 2` などで FB を表示し直していなかった -> FB を使うモード（2・3・4）なら表示する（`9dec971`）
- **jumps.py が遠景だけ**: スクロール・面の表示・OAM は Ruby と共通の影（`rbm_lr_*`）に書くが、本物へ写すのが Ruby の実行中だけだった
  （BG0 の縦スクロールが効かず透明な行を見せていた）-> Python のアプリ時間にも `rbm_lr_apply`、ローレゾを開いたら `rbm_lr_shadow_reset`（`9dec971`）
- **ラスタの指定が次の .py に残る**: raster.py のあとの pad.py・sound.py・shogi.py に背景のグラデーションが出た -> 始めと終わりに `vga_raster_clear`（Ruby と同じ）
- **式の値が端末に出る**: `.py` を REPL の形でコンパイルしていて、`LR.pattern` の戻り値（64）が何十行も出た -> `mp_compile(..., false)`
- 確かめ（描き上がった表示ラインを SWD で読んで色を数える）: mode0〜7・hat・m640・mandel・raster・tablet・pad・sound・shogi・jumps の 17 本。jumps.py は jumps.sgx と同じ色（山・地面・空のグラデーション）

## hat.py が遅くなった件（2026-10-31）
- 前の比べ（単精度 6.43 秒 -> REPR_D 9.69 秒）は、どちらも「モード 2 で FB が出ない」不具合の間に測っていて、表示の取得による core1 の待たせが無かった。
  FB が出るいまは hat.py 25.4 秒（Ruby の HAT.RB は 12.8 秒）。モード 2 は段ごとにモード 1 の約 3.5 倍
- 1 回あたり（モード 1）: Python で書いた関数の呼び出しが REPR_D で 3.4 -> 16.7µs。C の関数（`machine.rgb` 5.7 -> 6.7µs）・`math.cos`（5.5 -> 6.7µs）はほぼ変わらない。
  呼び出しのフレーム・例外の受け口が載る Python のスタック（PSRAM 64KB）への読み書きが、値が 64 ビットになって増えたため
  （スタックを SRAM の 16KB に置くと 7.5µs。ただしローレゾ面が開けなくなるので採らない）
- **`prelude.py` の C の関数を呼ぶだけの包み 36 個を外し、組み込みの関数をそのまま置いた**（利用者のクラスの組み込みの関数は staticmethod と同じに振る舞う）:
  `M.rgb` 47.6 -> 5.3µs、`fb.pset` 30.4 -> 5.5µs
- `prelude.h` は `python3 scripts/make_py_prelude.py` で `prelude.py` から作る（`prelude.py` を直したら必ず作り直す）

## m640.py の中のボトルネック（2026-10-31）
- FB を表示した状態で m640.py 202.7 秒（Ruby の M640.RB 116.9 秒）。core1 の PC を DWT_PCSR で止めずに 5000 回読むと:
  **70% が `core1_bell_isr`**（表示の取得の間 core1 を待たせる。Ruby も同じ）、残りの Python の時間のうち辞書引き（`mp_map_lookup`）9%・
  64 ビットの割り算（`__udivmoddi4`）1.3%・`qstr_hash` / `find_qstr`
- **REPR_D に特有の 2 つ**（`py/map.c` を手直し。`third_party/micropython/SGNANO_PATCHES.md`）:
  - 辞書引きの結果を覚える場所の番号 `MAP_CACHE_OFFSET` が「下位 32 ビットを 2 つ右へ」で、REPR_D の qstr（下位が `(番号 << 1) | 1`）では
    隣り合う名前が同じ場所を取り合っていた（zr・zi・zr2・zi2 のように続けて作った大域変数で毎回辞書を引き直す）-> 1 つ右へ
  - `hash % map->alloc` が 64 ビットの割り算だった -> 32 ビットで
- 結果: m640.py **202.7 -> 100.3 秒**（Ruby より速い）、辞書引き 9.0 -> 4.0%。mandel.py 0.89 秒。辞書・集合の確かめ 22 項目、jumps・shogi の画面
- 残り: 待たせ（70%）は FB を表示する限りかかる。Python で書いた関数の呼び出しは REPR_D で 16.6µs（単精度 3.4µs）のまま（PSRAM のスタック）

## hat.py の中のボトルネックと、VM のコードの配置（2026-10-31）
- hat.py（FB 表示）23.2 秒・Ruby の HAT.RB 12.8 秒。PC の内訳は 69% が表示の取得の待たせ、残りは VM・辞書引き・演算・`** 0.5`（`dpow_1`）・`int()` に散る
- **`int(float)`**（`py/objint.c`）: 整数への変換の演算・バッファの確かめに失敗してから float を見ていた -> float を先に。**`x ** 0.5`**（`py/objfloat.c`）: x が正なら `sqrt`
- **コードの配置で速さが ±20% 揺れる**: この 2 つを足しただけで hat.py は 23.2 -> 16.3 秒、m640.py は 100.4 -> 121.3 秒（m640.py は直した道をほとんど通らない）。
  VM はフラッシュから走り、XIP キャッシュ（16KB・2 ウェイ・1 ウェイ 8KB）を PSRAM のヒープ・スタックと分け合うので、並びのずれでよく使う関数どうしが同じ場所を取り合う
- **よく使う関数を 8KB の境目から 1 つながりに並べた**（`ld/placement.cmake` の `SGNANO_PY_HOT`。VM 本体と飛び先の表・辞書引き・浮動小数点の演算・大域変数・呼び出し・反復など約 9KB を 1 段目、
  二項演算・呼び出しの状態の用意・添字などを 2 段目。順番は PC を数えた結果）。SRAM は使わない
- 結果（FB 表示）: **hat.py 23.2 -> 12.0 秒**（Ruby 12.8 秒）、**m640.py 100.4 -> 92.1 秒**、**mandel.py 0.89 -> 0.74 秒**。jumps・mode5・shogi の画面も確かめた
- MicroPython 本体の手直しは `third_party/micropython/SGNANO_PATCHES.md`。よく使う関数の並びは、MicroPython を差し替えたら PC を数え直して見直す


## 2026-11-01: 終わったあとファイラーに戻らない（青い背景だけ）を直した

ユーザー報告: hat.py のあとファイラーへ戻ると青い背景だけで、ESC（F2・F3 を初めに戻す）で戻った。終わりの画面モードがファイラーと同じ（hat.py はモード 2）だと、
`py_free` が画面モードを切り替え直さず、ファイラーにも描き直しを伝えていなかった（端末を閉じて消えたテキスト面のまま）。
Ruby・SG BASIC（`rbrun.c` の `close_now` が `filer_enter()`、ファイラーの VIEW_RUBY の終わりが `text_clear`）と同じく、閉じたフレームは
ファイラーの全体の描き直し・一覧の読み直し・テキスト面の消去だけをする（`filer.c` の `filer_app_time`、Rev01.070）。
遠隔の `RSTAT` が Python の時間を返していなかった（Ruby・SGX の最後の時間を返した）のも直した（`rb_note_timing`）。

速さ（実機、2026-11-01、FB 表示はモード 2）: mandel.py 0.74 秒（MANDEL.RB 0.43・mandel.bas 1.11）、hat.py 12.0〜15.1 秒（HAT.RB 10.5・hat.bas 15.1）、
m640.py 94.0 秒（M640.RB 50.6・m640.bas 69.3）。`samples/python/bench.py`（`samples/ruby/bench.rb` と同じ項目）の結果は `docs/sgnano_python_guide.md`

## 2026-11-01 ホストの組み立てを直した

- `make -C src/python`（ホストの REPL、`build_micropython/host/firmware.elf`）が組めなかった: リンクの規則が無かった（`PROG = firmware.elf` で mkrules.mk の規則を使う）、`mp_hal_set_interrupt_char` が無かった（`uart_core.c` に空の口）
- 組めても `print` すら引けなかった: NaN boxing（`MICROPY_OBJ_REPR_D`）はポインタが 32 ビットの前提で、64 ビットのホストでは壊れる。**ホストは `-m32` で組む**（実機と同じ表し方のまま試せる）。`2**100`・`1/3`・`math.sqrt(2)`・`str.format`・内包表記が実機と同じ結果
- ホストの版は MicroPython の minimal の土台のままで（prelude も走らない）、`machine`・`os`・`fft`・`socket` は入っていない（言語の核の試し用）

## 2026-11-01 モジュールを足した（json・io と open・errno・binascii・hashlib・heapq・cmath）

- 設定 `mpconfigport.h` と `Makefile` の並び（`extmod/modjson.c` `modbinascii.c` `modheapq.c` `modhashlib.c`）。`io`・`errno`・`cmath` は py の中。コードはフラッシュで SRAM は増えない
- `binascii.hexlify` は `MICROPY_PY_BUILTINS_BYTES_HEX` が要る。`crc32` は deflate が要るので入れていない
- `hashlib` はファームの mbedTLS（`sha1.c`・`sha256.c` は TLS のためにもう入っている。頭は pico-sdk の mbedtls と `src/net/mbedtls_sgnano_config.h`）。ホストには mbedTLS が無いので `__arm__` のときだけ
- **`open()` は prelude の `_SgFile`**（`io.IOBase` の子。ファイルを丸ごと読んで StringIO / BytesIO に持ち、閉じるとき `os.write_file` で書き戻す）。`io.IOBase` の子なので `json.dump(obj, f)` / `json.load(f)` も通る（はじめは普通のクラスにして「stream operation not supported」）。組み込みの `open`（`sgopen.c`）は `__main__` の `_sg_open` へ渡す口
- 実機（`S:/bench`）: json・hexlify・base64・heapq・cmath・errno、sha256("abc") と sha1("abc") が既知の値、`open` の w・a・r・r+b・x・無いファイル・行ごとの for・`json.dump` / `load` を確かめて消した。mandel.py 0.81 秒【追記 2026-11-02】`S:/bench` の中身はユーザーが `S:/testapp` へ移した
- 【注意】prelude.py を直したら `ninja -C build` が prelude.h を作り直す。直す台本が途中で止まっていて prelude.py が変わっておらず、古い前置きのまま「KeyError: _sg_open」になった

## 2026-11-04 ファイラーからの .py 起動

- 手操作の `.py` 起動は、ファイラータスク（core1）ではなく **core0 のアプリ時間の後**
  （`filer_pending_python_app_time()`）で `py_open_file` を呼ぶ。ファイラータスクの中で同期読み出しをすると、
  core0 の `filer_work` を待つ間に core0 がファイラーのフレーム終了を待ち、ウォッチドッグ再起動になる。
- リモートの `PYRUN` は元から core0 なので同じ経路。`mode4.py` は lowres 32KB / 64 パレットで起動し、
  `tile 256 is out of range` は出ない（precomp 廃止で SRAM が戻ったため）。

## 2026-11-04 積み残し（性能）の見直し

- **FB を表示している間の待たせ（約 70%）**は、`render_park_on` が表示の取得の間 core1 を待たせる性質そのもので、
  FB を出す限り避けられない（Ruby・SGX も同じ）。Python 側だけで縮める手はない。
- **Python のスタック（PSRAM 64KB）**を SRAM の 16KB に置くと、Python で書いた関数の呼び出しが 16.6µs -> 7.5µs になるが、
  ローレゾ面（パターン・マップ・作業場）が SRAM に開けなくなるため採らない（2026-10-31 の測定）。
- PSRAM スタックのうち実際に触るのは上の方だけなので、スタックの大きさを 64KB から縮めても XIP キャッシュの
  取り合いはほとんど変わらない見込み。**スタックの置き場所を変える案は、この tradeoff で保留**。
- いまできる範囲（VM と GC を `-O2`、computed goto、辞書引きのキャッシュ、REPR_D の割り算の修正、
  `SGNANO_PY_HOT` の配置）は実施済み。`mandel.py` 0.74 秒・`m640.py` 92 秒・`hat.py` 12.0 秒（FB 表示）。

## 2026-11-11 GPIO / PIO2 / MIDI / Music（ABI 5.0）

- `machine.GPIO`・`machine.PIO2`（ABI 5.0）と、`machine.MIDI`・`machine.Music`（ABI 4.13 / 4.4）を
  **型ではなく 1 つのインスタンス**としてモジュールに置いた。MicroPython は型オブジェクトの locals 辞書にある
  組み込み関数を「最初の引数が self か」で検査するため、`machine.PIO2.sm_claim(0)` や
  `machine.MIDI.read(1)` が `argument has wrong type` になっていた。インスタンスにすると self が
  正しく渡り、引数付きのメソッドが動く。
- prelude の `Machine` に `Music` / `MIDI` / `GPIO` / `PIO2` の別名を足した（`M.Music.play(...)`,
  `M.PIO2.sm_claim(0)` など）。
- `machine.ADC`（ABI 5.1）も同じインスタンスの形で足した。`pins()` / `can_read(pin)` / `read(pin)` /
  `start(l=0, r=0)` / `stop()` / `active()` / `stats()`。C ボードは GP40/41（A6/A7）と GP46/47（専用 L/R）、
  P ボードは GP40/41。prelude の `Machine` からは `M.ADC`。ABI 5.2 で `temperature()`（℃、float。
  連続取り込み中は None）を追加した。
- **2026-11-11 の修正**: `machine.ADC` はインスタンスなので、メソッドは self を受け取る。
  `pins()` / `can_read(pin)` / `read(pin)` が self なしで定義されていて、
  `TypeError: function takes 1 positional arguments but 2 were given` になっていた。
  `MP_DEFINE_CONST_FUN_OBJ_1` / `_OBJ_2` に直した。`temperature()` は self だけを受ける。
- **メモリの注意**: `api.py` は lowres / ビットマップを開いた後に ADC を始めるため、
  PSRAM の連続した空きが無いと `ADC.start()` が `-ENOMEM` になる（`adcstart=0`）。
  ADC 単体（`adcfull.py`）では `pins` / `read` / `temperature` / `start` / `stats` / `stop` が通る。
- 実機（C ボード、ABI 5.0/5.1）: `api.py` は `pio2=1` / `pio2load=1` / `pio2fifo=1` で `API-END`。
  `machine.MIDI.read(1)` / `write(b"\x90\x3c\x64")` / `input_route()` と、
  `machine.Music.playing()` / `position()` が動くことを確認した。
- PIO2 の自己テストは `pull block` / `mov isr, osr` / `push block` の 3 語（`0x80A0`, `0xA0C7`, `0x8020`）。
  `pull` だけでは OSR が ISR に移らず、RX に 0 が出る。
