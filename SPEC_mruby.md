# mruby/c とバイトコードコンパイラの組み込み（仕様、2026-10-11）

## 目標
- ファイラーで **Ruby のソース（`.rb`）またはバイトコード（`.mrb`）を Enter で実行**する。`.rb` は本体でコンパイルしてから実行する。
- REPL（対話）はファイラーの **I / Ctrl+F5**（2026-10-30）。VM を開いたまま 1 行ずつ走らせる。
- 実行中の画面は**モード1**（テキストのみ）を初期値とする。あとで別のモードへ切り替えられるよう、モードは引数で持つ（`rb_run_opts_t`）。
- **SRAM は可能な限り使わない**。ヒープ・バイトコード・ソース・スタックは PSRAM に置く。

## 部品と版（`third_party/`、版を固定する）
| 部品 | 版 | 役目 |
|---|---|---|
| mruby/c | release4.0.0 | VM（RITE `0400` を読む） |
| mruby-compiler2 | `e5691e7`（2026-10-10、picoruby/mruby-compiler2） | ソース -> バイトコード（`MRC_TARGET_MRUBYC`）。mruby 本体の mruby-compiler と同じもの |
| Prism | `c0e3781`（v1.9.0、ruby/prism） | 構文解析。生成物（`templates/template.rb` の出力）も取り込む |
- この組み合わせ（mruby/c + mruby-compiler2）は FemtoRuby と同じ。コンパイラは mruby/c のヒープ（`mrbc_raw_alloc`）からメモリを取る。
- ホストで「ソース -> バイトコード（202 バイト）-> 実行」まで通ることを確かめた（2026-10-11）。
- ARM（`-Os`）での大きさ: コードと定数 約 425KB（Prism 290KB・コンパイラ 66KB・mruby/c 66KB）、静的な RAM 約 3.6KB。

## メモリ
| もの | 置き場 | メモ |
|---|---|---|
| コード・定数 | フラッシュ | リンカの並びで `third_party/` と `src/ruby/` の `.text` `.rodata` をフラッシュへ |
| VM とコンパイラのヒープ | PSRAM（`pmem_alloc`、既定 1MB） | `mrbc_init_alloc()` に渡す。コンパイラも同じヒープを使う |
| ソース・バイトコード | PSRAM（ヒープの中か `pmem_alloc`） | ファイルは PSRAM へ読み込む |
| C のスタック | **PSRAM**（既定 32KB、ユーザー判断） | 走らせる間だけ MSP をこちらへ切り替える。割り込みの入口の退避も PSRAM へ書かれる。映像が乱れたら SRAM のアリーナへ切り替えられるようにしておく |
| 静的な変数（.data / .bss） | SRAM（mruby 本体は 4 バイト、`src/ruby` 全体で 871 バイト） | mruby 4.0 では VM の状態（`mrb_state`）もヒープ（PSRAM）に取るので、移す価値がある静的な変数は無い（2026-10-30 に map で確認） |
- PSRAM は「キャッシュを通らない窓」（`0x15...`）。FB を表示しないモード（モード1）なので、アプリ時間の外でも書いてよい（docs/DEVELOPMENT.md の決まり）。
  **FB を表示するモードで走らせるようにするときは、この前提が崩れる**（PSRAM への書き込み・フラッシュのコードの実行がアプリ時間の外に出る）ので、その時に設計し直す。

## 実行の流れ
1. ファイラーで `.rb` / `.mrb` を Enter -> ファイルを PSRAM へ読み込む -> モード1 へ（テキスト面だけ）。
2. 開始後の長い仕事として、PSRAM のスタックに切り替えて実行する:
   - `.rb`: mruby-compiler2 でコンパイル（バイトコードはヒープの中）-> コンパイラの作業領域を返す。
   - mruby/c のタスクを作って `mrbc_run()`。
3. **tick**: ハードのアラーム（1ms、優先度は描画より低い）の割り込み（SRAM）で `mrbc_tick()` を呼ぶ。`mrbc_tick` は SRAM に置く。
4. **アプリのループへ譲る**: スケジューラの1区切り（timeslice）ごとに呼ぶ口（`rrt0.c` に1行足す）で、前に譲ってから約 1 フレームたっていれば `app_yield()`。
   これで映像・USB・キー・ウォッチドッグが回る。空いているとき（`mrbc_hal_idle_cpu`）も `app_yield()`。
5. 出力（`puts` `print` `p`）は `hal_write` -> リングに溜め、アプリ時間にテキスト面の端末（スクロール）へ写す。UART のログにも出す。
6. **ESC** で止める（タスクを止めて後片付け）。終わったら「何かキーを押す」でファイラーへ戻る（モード2 に戻す）。
7. 例外は端末とログに出す。

## mruby/c の設定（`vm_config.h` の上書き）
- `MRBC_ALLOC_24BIT`（ヒープは 16MB まで）、`MRBC_USE_FLOAT 2`（double）、`MRBC_USE_MATH 1`、`MRBC_USE_STRING_UTF8 1`（日本語の文字列）、
  `MAX_SYMBOLS_COUNT` を増やす（コンパイルしたプログラムの名前の数に合わせて）。

## 取り込みに足す手直し（`third_party/` 側、最小限・印を付ける）
- `rrt0.c`: スケジューラの1区切りごとに呼ぶ口（`MRBC_HAL_AFTER_SLICE()`、既定は空）。`mrbc_tick` と下請けを SRAM へ置く印。
- HAL は `src/ruby/hal/hal.h`（自前）。

## 試験
- ホスト試験 `scripts/test_ruby.py`: ホストで「ソース -> バイトコード -> 実行」し、出力を期待値と比べる。`.mrb`（ホストでコンパイルしたもの）も読む。
- 実機: 映像（`underrun` / `fifo_stall` / `recover`）、テスト用アプリへ入れるか（SRAM の空き）、ESC で止まるか、長いループでもウォッチドッグが働かないか。

## あとで
- ~~REPL~~（2026-10-30）、~~画面モードの切り替え（Ruby から）~~、~~ファイルの読み書き・キー入力・音・描画のクラス~~、~~静的な変数を PSRAM へ~~（移すものが無いと確認）、~~`.mrb` を書き出す（コンパイルだけする）キー~~。残りは MIDI の入出力など（SPEC_sound.md）

## REPL（2026-10-30）

- ファイラーの一覧で **I**（または Ctrl+F5）。ファイルを開かず、いまのフォルダで VM を開いたまま 1 行ずつ走らせる
- 画面はモード 1（テキストのみ）。`>> ` のあとに Ruby を打ち、Enter。`def`・`if`・`do` など続きが要る行は `.. ` で次の行を待つ。
  空の行で続きを取り消す。**Ctrl-D**（行の頭）か **ESC** で終わり
- 走らせた結果は `=> 値`、例外は `Exception: ...`、構文の誤りは `SyntaxError: 行:桁: 理由`
- VM は行の間も開いたままなので、クラス・メソッド・定数は残る。ローカル変数は行ごとに消える（CRuby の irb と同じではない）
- 続きの判定は構文解析の「unexpected end of file」で行う（`src/ruby/mrb/rbcore_mrb.c` の `rb_repl_eval`）
- 実機（2026-10-30）: `1+1` -> `=> 2`、`def f(n)` / `n*2` / `end` の 3 行 -> `=> :f`、次の行の `f(21)` -> `=> 42`、
  `raise "boom"` -> `Exception: #<RuntimeError: boom>`、Ctrl-D で終わり（finished 44.986 秒、ヒープ 98,136 B、スタック 6,268 B）。
  `underrun=0`、`fifo_stall` は +4 程度。**REPL ではソースが無いので、実行前のキャッシュ無効化で `R.src == NULL` を触らない**（2026-10-30 に修正）

## 実装の結果（2026-10-11、実機）
- **動いた**: ファイラーで `.rb` を Enter -> コンパイル（268 バイトで 8ms）-> 実行。`.mrb` も Enter で実行。構文の誤りは「行:桁: 理由」、
  `sleep`（tick とアプリのループへ譲る）、ESC で止める（無限ループでも）、終わったら何かキーでファイラーへ。**M** で `.rb` をコンパイルして `.mrb` を書き出す。
- **速さ**: ヒープ・記号の表・ソース・スタックを、PSRAM の**キャッシュを通る窓**（`0x11...`）で使う。使う前に古い行を捨て（invalidate）、
  終わったら書き戻す（clean）。10 万回の `while` が 3.7 秒（キャッシュを通らない窓）-> 0.56 秒（ヒープだけ）-> **0.21 秒**（スタックも）。
  サンプルの hello.rb（fib(20) を含む）は 4.3 秒 -> 0.4 秒。
- **スタック**: PSRAM（キャッシュの窓）32KB。最高水位はコンパイルありで約 5KB、`.mrb` の実行だけなら約 2KB（`[ruby] finished ... stack used`）。
- **SRAM**: Ruby を外した版より **+1.7KB**（tick の割り込みと `mrbc_tick`・mruby/c のクラスの `.data` など）。
  はじめは +46KB だった: 取り込んだものが引き込む newlib の stdio・`malloc`・locale・`strtod`、pico の倍精度の数学関数・libm が、全体を SRAM に写す既定で
  SRAM に入った。→ `src/ruby/defines_tp.txt` で libc の関数を `src/ruby/rblibc.c`（自前の `strtod` など）へ付け替え、`MRC_NO_STDIO`、
  Ruby からしか呼ばない数学関数・libc の部品はリンカの並びでフラッシュへ（Ruby を外した版で SRAM に残らないことを確かめた）。
  実行の状態（`rbrun.c` の R）も PSRAM。テスト用アプリのアリーナの空きは 5,148 B。
- **映像**: 実行・コンパイル・PSRAM のスタックで `underrun` / `fifo_stall` は増えない。
  【追記・2026-10-11】下の「戻るときの作り直し」は、戻るときにテストパターンを FB に描いてアプリ時間が 86ms に延び、同じフレームでファイラーを描き直していたのが原因だった
  （積み残し、`app_fb_keep` と「作り直したフレームはほかに何もしない」で対処）。M は引き続き FB を隠すだけ（作り直しが無いぶんモニタの同期も途切れない）。
  **M（コンパイルだけ）は画面モードを変えず FB を隠すだけ**にした: モード1 へ切り替えて戻し、一覧を読み直すと、表示経路の自動の作り直し
  （recover、underrun 約 400）が 9 回中 8 回起きた。起動時のバナーの終わり（モード 1 -> 2）でも同じ作り直しが起きることがあり（積み残し）、
  根は「モード 1 -> 2 の作り直しのあと、まれに描画が間に合わなくなる」と見ている（未解決）。ふつうの実行から戻るときは 8 回で 0 回。
- mruby/c の違い: `Range#reduce` が無い、`'0x1F'.to_i(16)` は 0、浮動小数点の表示が `302.400`・`1e-05` など（CRuby と違う）。
- サンプル: `samples/ruby/`（`.mrb` はホストの `build_host_ruby/host_ruby mrbc` で作ったもの）。
- 打ち込み: UART から `scripts/console.sh -k` でエディタへ打つときは、波かっこを `{LBRACE}` `{RBRACE}` で送る（`{名前}` が特殊キーになるため）。日本語は打てない。

## mruby 4.0.0 への差し替えの試作（2026-10-16）

mruby/c の代わりに mruby 4.0.0（2026-04-20、RITE `0400`）を載せられるか試した。CMake の `-DSGNANO_RUBY_VM=mruby`（既定は `mrubyc`）で組む。
mruby は `tools/mruby/build.sh` で `build_mruby/`（`.gitignore` の `build*/` に入る）に取ってきて組む。設定は `tools/mruby/rp2350.rb`（rake の設定。`GEMS` と HAL の gem `tools/mruby/hal-sgnano-task`・
`MRB_NO_STDIO`・`MRB_NO_BOXING`・`-Dabort=rb_mrb_abort -Dtime=rb_mrb_time`）。
正規表現は `mruby-onig-regexp`（`third_party/mruby-onig-regexp`、Onigmo 6.2.0 に 2026-10-23 の修正を適用）、JSON は `third_party/mruby-json`（mattn/mruby-json の固定版）を入れてある。

### 作り
- `src/ruby/mrb/rbcore_mrb.c`: `rbcore.h` の口を mruby で。割り当ては mruby の `mrb_basic_alloc_func()` を定義して mruby/c の割り当て器（`alloc.c`、TLSF）で
  PSRAM の 1MB から。コンパイラは mruby 同梱（yacc）。`.rb` も一度バイトコードにしてから `mrb_read_irep_buf` で読み、`mruby-task` のタスクにする
- 実行: `mruby-task`（時間で区切る切り替え。mruby/c と同じ形）。tick（`rbtick.c` の 1ms）から 4 回に 1 回 `mrb_tick()`。`mrb_task_run_once()` を回し、
  区切りごとに `rb_hal_after_slice()`（アプリのループへ譲る・ESC で longjmp）。終わったら `mrb_close`
- `print` / `puts` / `p` はここで定義（`puts` は mruby では mruby-io の側にある）
- `src/ruby/mrb/rbmachine_mrb.c`: Machine / FrameBuffer の mruby 版。描画は mruby/c 版と共通の `src/ruby/rbdraw.h`（切り出した）
- ファイル操作（File / Dir / IO）はまだ無い【追記 2026-10-16】下の「ファイル操作と既定への切り替え」で足した

### 実測（実機、FB を表示中の数は core0 を待たせる仕組みの下）
| | mruby/c | mruby（`-Os`、NO_BOXING） |
|---|---|---|
| SRAM（ビルド時の使用） | 253,576 B | 254,292 B（+716 B） |
| テスト用アプリの空き（F10） | 4,860 B | 3,580 B |
| フラッシュのコード | 870KB | 1,006KB |
| `HELLO.RB` | 約 0.4 秒 | 0.20 秒（コンパイル 4ms） |
| `MANDEL.RB`（文字のマンデルブロ） | 1.5 秒 | **0.95 秒** |
| 空の `while` 10 万回（モード1 / 2） | 210 / 733 ms | 201 / 712 ms |
| `pset` 1 万回（モード2） | 899 ms | 733 ms |
| `fill_rect` 1000 回 / `line` 1000 回 | 836 / 619 ms | 856 / 635 ms |
| `hat.rb` / `mandel640.rb` | 17〜18.3 秒 / 102 秒 | 20.5 秒 / 106.8 秒 |
| ヒープ（`MANDEL.RB`） | 約 16KB | 62KB |

- ESC で止まる、FB を表示したまま描いても乱れない（fifo_stall +1〜2）、mruby/c のコンパイラで書き出した `.mrb` も読める
- ホスト（x86）の mruby では、mruby/c で使えなかった書き方がほぼ使えた: `ensure`・lambda・`&:sym`・`Array.new(n) { }`・`count(x)`・`first(n)`・`inject`・`sum`・
  Struct・`format`・`String#%`・大きな整数・`"#{obj}"` の `to_s`・自分の `<=>` での `sort`・`case ... in`・`catch` / `throw`・`define_method`・`send`・Random・pack・
  Time・Fiber・`Float::INFINITY`・`round(2)`（正規表現は mruby-onig-regexp の Onigmo）

### つまずいたところ
- **既定のワードボクシングでは浮動小数がヒープのオブジェクトになり**、`MANDEL.RB` が 3.2 秒・ヒープ 950KB。`MRB_NO_BOXING` で 0.95 秒・62KB
- **C のメソッドで `mrb_get_args(mrb, "*", ...)` を使うと、呼ぶたびに引数を配列に写す**（`pset` 1 回が約 50µs 重かった）。`mrb_get_argc` / `mrb_get_argv` で直した
- **mruby の `abort` が newlib の `raise` -> `signal` -> `malloc` を引き込み、SRAM が約 6KB 増えた**。mruby/c と同じく自前の関数へ向けた
- `-O2` で組むとフラッシュが 80KB 増え、VM の素の繰り返しは速くなったが `MANDEL.RB` は 1.5 秒と遅くなった（フラッシュのキャッシュの当たりが減ったためと推測）。`-Os` のままにした
  【訂正 2026-10-31】よく使う関数を並べたうえで `-O2` にした（下の 2026-10-31 の節）

## ファイル操作と既定への切り替え（2026-10-16）
**mruby が既定になった**（`-DSGNANO_RUBY_VM=mruby`。mruby/c は `-DSGNANO_RUBY_VM=mrubyc` で残す）。`libmruby.a` はリポジトリに入れず、
`tools/mruby/build.sh`（`scripts/build.sh` は無ければ呼ぶ。初回 15〜20 分）で `build_mruby/` に組む。

### 2 つの案を比べて、自前のクラスにした
| | 案A: 自前の IO・File・Dir（採用） | 案B: mruby 標準の mruby-io・mruby-dir + HAL |
|---|---|---|
| CRuby との一致（`samples/ruby/fs_compat.rb` 65 行、ホスト） | **65 / 65** | 29 / 65 |
| 実機（HDD の A: FAT32 / B: exFAT / C: NTFS） | **3 つとも 65 / 65**、`underrun=0` | 走らせていない |
| SRAM（ビルド時の使用） | 254,588 B | 282,636 B（+28KB。テスト用アプリに入れない） |
| 組めるか | そのまま | `MRB_NO_STDIO` と組めない（`mruby/io.h` が `#error`）。`open`・`read`・`write`・`lseek`・`close`・`stat` を HAL を通さずに POSIX へ直接出すのでドライブに届かない。`dup`・`waitpid` も要る |

- 共通の下回り `src/ruby/rbfh.{h,c}`: 開いたファイルの表（8 個）、中身を丸ごと PSRAM（`rb_big_alloc`）に持って閉じるときに書き戻す、いまのフォルダ、`rbfs`・`rbpath` を使う
- `src/ruby/mrb/rbfile_mrb.c`: クラスと Errno（C）と前置き（Ruby、`ensure` が使える）。`IOError` は mruby の中核に無いので定める。`IO::SEEK_*` も前置きで
- `src/ruby/mrb/rbkernel_mrb.c`: `print` / `puts` / `p`（`MRB_NO_STDIO` なので）
- 試験: `scripts/test_mruby.py`（ホストの実行器 `scripts/host_mruby/main.c` で `fs_compat.rb` を CRuby の出力と 1 行ずつ比べる。`machine.rb`・`demo.rb`・`fileio.rb` も）
- テスト用アプリの空き（F10）: **3,292 B**（mruby/c では 4,860 B）

### 実機で見つけて直したもの
- **mruby-task の不具合: 機器を待つ C のメソッドの中で投げた例外が `rescue` を飛び越えた**（`rescue` の本体も次の行も走らず、`end` の後から続いた）。
  待つ間（`app_yield`）に tick が切り替えの印を立て、例外の受け口へ飛んだ直後の `NEXT` で切り替わる。再開のとき `mrb_vm_exec` が `mrb->exc` を消すので、
  `OP_EXCEPT` が nil を受け取り `rescue` に合わない。ホストには tick が無いので出ない。
  **例外を持っている間は切り替えない**ように `vm.c` の `RETURN_IF_TASK_STOPPED` を直した（`tools/mruby/patches/0001-task-switch-pending-exception.patch`、`build.sh` が当てる）
- **NTFS: 子のブロックを持つようになったフォルダは、中を全部消しても「空でない」で消せなかった**（ルートが空の葉を指したまま残る）。使っている INDX ブロックを見て、
  どれも「おしまい」だけなら空とする（`src/fs/ntfs_w.inc` の `D_EMPTY`。mruby/c 版にも効く。`test_fs.py` に足した）

### そのほか確かめたこと（実機）
- **M** で `.rb` -> `.mrb`（464 バイト）、書き出した `.mrb` を Enter で走らせて同じ出力
- 書き込みを続けるスクリプトを ESC で止めても、止まり方はきれいで、ファイルも壊れない（FAT32）
- 起動直後と F10 の往復 2 回で `underrun=0 recover=0`

### 手引きの作り直し（2026-10-16）
- `docs/sgnano_ruby_guide.md` / `.pdf` を mruby に合わせて作り直した。使える・使えないは `build_mruby/probe/probe.rb`（ホスト）と、要所（整数のあふれ・浮動小数の表示・
  `printf`・`sleep`・速さ）を実機で確かめた
- **ホスト試験のライブラリも整数を 32 ビットに**（`MRB_INT32`。ファームは 32 ビット + NO_BOXING で元から 32 ビット。ホストは 64 ビットになっていて、あふれ方が違った）
- `printf` は mruby では mruby-io の側にあるので、`rbkernel_mrb.c` に足した（`format` に任せて端末へ）
- mruby と CRuby の違いで目立つもの: 整数のあふれは RangeError（mruby/c は黙って折り返した）、浮動小数の表示は 15 桁、**`$!` はいつも nil**、
  `Time` は無い（正規表現は Onigmo の gem、`Set` は gem を入れてある）。**`Data`・`JSON`・`Enumerator::Lazy` / `Chain`・トップレベルの `include`/`extend`・`require` / `load` / `require_relative` は 2026-11-02 に追加**。**`system` / `exec` は積み残し**（`mruby -r` はシェルが前置きで走らせるだけで `Kernel#require` ではない）

## ファイルの属性と日時・Time（2026-10-16）
- `File.stat`（`File::Stat`: `size` `file?` `directory?` `ftype` `mtime` `ctime` `birthtime` `atime` `mode` `writable?`、sgnano の `attributes` `readonly?`
  `hidden?` `system?` `archive?`）・`File.mtime` など・`File.chmod`（書き込みの許可のビットだけ）・`File.attributes` / `File.set_attributes`（`File::ATTR_*`）。
  読み出し専用は、開いて書く・追記・消す・名前の変更が `Errno::EACCES`（開くときに断る。消すのも断るのは Windows に倣った）
- 下回り: `rbfs_stat_ex`（属性と日時つき）・`rbfs_set_attr`、`rbfh_stat_ex`・`rbfh_set_attr`（開いて変えたファイルは先に書き出す）。ドライブ側は `docs/notes/storage.md`
- **`Time` は自前（`src/ruby/mrb/rbtime_mrb.c`、日本時間だけ）**。mruby-time は newlib の `localtime`・`mktime`（と TZ の仕組み）を SRAM に引き込むので使わない。
  中身は `@t`（UTC の秒）と `@u`（µs）。いまは `rbm_utc_us()`（NTP の時計。合わせていなければ 2026-10-04 12:00 + 起動からの時間）。整数が 32 ビットなので 2038-01-19 まで
- `Machine.clock_set?`
- 試験: `fs_compat.rb` に 9 項目（stat・mtime・chmod・読み出し専用への書き込み・Time）を足して 74 項目、CRuby と全部一致。sgnano だけの振る舞いは
  `samples/ruby/attr.rb`（隠し・システム・アーカイブ、消す・名前の変更を断る、フォルダの印、時計を決めた `Time.now`）を `scripts/host_mruby/attr.expected` と比べる。
  実機（HDD の A:、NTP あり）でも時計の行のほかは同じ出力

## キー入力（2026-10-16）
- ファイラーの `rb_key()`（アプリ時間）が、ESC のほかのキーを実行の状態（PSRAM）の環（64 個）に入れる。ESC は今までどおり実行を止める
- **標準入力** `rb_stdin_read()`（`rbrun.c`）: 行が尽きたら 1 行打ってもらう（端末に出し、カーソルは `_`。BS・Enter、行の頭の Ctrl-D / Ctrl-Z で終わり）。
  打った行は消して `rbterm_write` で出し直す（UART のログには打ち終えた行だけが出る）。`gets`・`getc`・`read` など IO の stdin はこれを使う。
  `$stdin.read` は終わり（Ctrl-D）まで、`read(n)` は n バイトか終わりまで待つ（ホストの stdin は一度に返すので、実機で見つけて直した）
- **Machine**: `key`（待たない）・`wait_key`・`key_down?`（`usbkbd_key_down`: HID の Usage を表から逆に引き、ブート側の 6 キーか NKRO のビットマップを見る。
  修飾キーは 0x100〜0x102）・`clear_keys`・`keyboard?`・`key_name`、定数 `KEY_*`
- 待つ所はどれも 1 周ずつ譲り、ESC なら止める。関数はフラッシュ（`rbrun.c` は丸ごとフラッシュ）。SRAM は増えていない
  （`usbkbd_key_down` が `keycode_to_ascii`・`nkro_is_down` を呼ぶと、SRAM の `kbd_nkro_report` の展開が変わって 0.3KB 増えたので、表を直接引く）
- 試験: `samples/ruby/keyin.rb`（ホストは stdin と環境変数 `RBM_KEYS`・`RBM_DOWN` で流し込む。`test_mruby.py`）。実機でも同じ出力（BS で直した行・
  getc・read・Ctrl-D の nil・特殊キーの名前）、`Machine.key` で a・Up・F5、`wait_key` で Left、入力待ちの ESC で止まる

## C の関数が呼んだブロックの途中のタスク切り替え・GC（2026-10-16）
**症状**: ポリゴン版のデモ（NEON CIRCUIT）が、パレットを `Array.new(160) { |i| Machine.rgb(...) }` で作る所で止まり、ウォッチドッグで再起動した。
ウォッチドッグを切ったファーム（`-DSGNANO_WATCHDOG_MS=0`、`build_nowdt/`）で再現させると core0 が HardFault（CFSR = IBUSERR、PSP に積まれた PC が 0x89101800 というでたらめな値、
LR は mruby の `iv_get`・`mrb_ary_set` の中）。ファイルを使わない `Array.new(n) { }`・`each`・`map` の繰り返しだけでも同じく落ちた（`Integer#times` は mrblib の Ruby なので落ちない）。

**原因**: mruby-task は区切り（tick 3 回）で `switching` を立て、VM は命令の切れ目（`RETURN_IF_TASK_STOPPED`）で `mrb_vm_exec` から戻ってタスクを切り替える。
C の関数が `mrb_yield` で呼んだブロックの途中だと、入れ子の `mrb_vm_exec` が戻ってブロックが nil を返したことになり、C の関数はそのまま進む。後でタスクが再開すると、
もう無い C の枠へ戻って壊れる。mruby-task の `sleep` / `Task.pass` は C の境（`ci->cci > 0`）を調べて避けているが、区切りの切り替えは調べていなかった。

**対処**（`tools/mruby/patches/0002-task-no-switch-in-c-block.patch`）: 切り替えの印が立ったとき、C の境の中なら切り替えずに印を下ろし、`sgnano_task_nested_slice()`
（`rbcore_mrb.c`。区切りの残りを数え直してから `rb_hal_after_slice()` = アプリのループへ譲る・ESC なら止める）を呼んで続ける。
区切りの残り（`timeslice`）は 0 になったときにだけ印を立てるので、数え直さないと二度と譲らず、ウォッチドッグが働いた。vm.c には何もしない弱い既定を置く（ホストの mrbc など）。

**もう一つ**（`0003-gc-count-malloc-bytes.patch`）: mruby の GC は物の数で回るので、大きな String・Array（`File#read`・`unpack`・`get_block`）を作り続けると、
物が少ないままヒープ（1MB）が尽きて `Out of memory` になった（デモを真似た読み込み + `unpack` 600 回で）。`mrb_realloc_simple` で確保したバイト数を数え、256KB ごとに
`mrb_full_gc`（確保に失敗したとき mruby 自身が全部の GC を回すのと同じ所）。`get_block` だけに入れていた数え方はこれに置き換えた。

**確かめ**（実機）: ブロックを C から呼ぶ繰り返し 30 秒で all ok・`slow loop` なし、途中の ESC で 4 回とも止まる。デモの読み込みを真似たもの（584KB を `rb` で開く・
200 フレーム x 読み + `unpack` を 3 回）が最後まで走り、ヒープの使用は 961KB -> 233KB、underrun 0。
ホストの実行器はタスクの区切りで動かしていないので、この不具合はホスト試験では出ない。

**`tools/mruby/build.sh`**: 手直しが前の手直しの行を書き換えると、逆に当てて「当たっているか」を見る方法が使えないので、当てたものを `.sgnano_patches` に書いておく形にした。

## 2026-10-18 追記
- 実行するコアは core1（M33BEATOS のアプリのタスク）。上の実測の表の「FB を表示中の数」は core0 で走っていたときのもの。いまの数は `docs/sgnano_ruby_guide.md` §10
- **Sound** を足した（`src/ruby/mrb/rbsound_mrb.c`、`SPEC_sound.md`）。初めて使ったときに音を開き、終わり・ESC で閉じる（`rbrun.c`）。ホストの実行器には入れていない

## 2026-10-23 追記: Ruby を独立したタスクに
- **Ruby は M33BEATOS の自分のタスク（`ruby`、優先度 9）で走る**（`src/ruby/rbrun.c`）。`rb_work` はヒープ・シンボル表・スタック（PSRAM 32KB、キャッシュを通る窓）を
  取ってタスクを作って戻り、アプリのループはそのまま回り続ける。終わった（`MB_T_DEAD`）のを見て後片づけ（`rb_finish`: 音を閉じる・スタックの最高水位・ヒープの数・返す）
- 以前の「10ms ごとに `app_yield` でアプリのループを 1 周回す」と、スタックを替える `call_on_stack` はやめた（`#if 0` で残した）。待ち（`vsync`・`sleep`・画面の頼み）は眠って待つ:
  - `vsync` はフレームの数（`video_frame_count`）が進むまで 1ms ずつ眠る。止める頼み（ESC）を見る
  - 画面のモードの切り替えなど表示の資源を触る頼み（`machine_request`）は、アプリのタスクがアプリ時間に受けて行い、Ruby は終わるまで 0.5ms ずつ眠る
  - mruby の `mrb_hal_task_idle_cpu` は 1ms、`mrb_hal_task_sleep_us` は 1ms ずつに分けて眠る
- **ファイル操作**（`rbfs.c`）の口は `usb_lock` を取って呼び、待つ間は重なった段数ごと手放して眠る（`SPEC_m33beatos.md` の `usb_lock`）。アプリのタスクから呼ぶときは今までどおり `app_yield`
- 実測（実機）: `fs_compat.rb` が FAT32・exFAT・NTFS で CRuby と 74 行一致、`machine.rb`・`blit.rb`・`textattr.rb`・`mode456.rb` が all ok、`demo.rb`・`mode3.rb` が ESC で止まる、
  `bench.rb`・`hat.rb`（24.1 -> 14.1 秒）・`sound.rb`・`mandel640.rb`（95.9 -> 77.9 秒）が最後まで走る、表示は underrun 0
- **`Machine.tablet`**（2026-10-23）: ペンタブレット（ワコム Graphire 系）の状態の Hash。`connected`・`ready`・`name`・`proximity`・`tool`（`:pen` / `:eraser` / `:mouse` / nil）・
  `x`・`y`・`pressure`・`x_max`・`y_max`・`pressure_max`・`tip`・`button1`・`button2`・`pad`（bit0 / bit1 = 板のボタン）・`wheel`（累計）。見本 `samples/ruby/tablet.rb`（ペンで描く）。
  ホストの実行器では `connected: false`

## 2026-10-29 ヒープの最高水位と複数 VM の試し（ホストのみ）

- 本体と同じ mruby/c の TLSF 割り当て器をホストの配列の上で使う計測器を足した
  （`scripts/measure_mruby_heap.py`、`scripts/host_mruby/main.c` の `HEAP_KB`）
- 1MB のヒープでの最高水位: `hello.rb` 270KB、`demo.rb` 354KB、`bench.rb` 422KB、
  `fileio.rb`・`regexp.rb`・`mode3.rb`・`mode456.rb`・`mode7.rb` 270KB。`fs_compat.rb` は 1MB では
  Out of memory（空き 500KB でも 320KB の一時領域が連続して取れない）。2MB では 972KB で最後まで走り、
  1.25MB でも通る。**通常は 1MB で足りるが、小さくするのは危ない**。`fs_compat.rb` を 1MB の
  固定ヒープで通すには 1.25〜1.5MB が要ると当時は測っていた。2026-11-03 の 64KB 動的ヒープで解消
  （2026-11-05 実機で 320KB x2 + `File.read` を確認）
- `third_party/mrubyc/src/alloc.c` に `mrbc_alloc_pool()` / `mrbc_alloc_set_pool()` を足し、
  VM ごとに別の TLSF プールを持てるようにした。512KB のプール 2 つで mruby を 2 つ動かす
  `scripts/test_mrbpool.py` が通る（ポインタの番地で持ち主のプールを選ぶ）
- これは VM と割り当て器の共存まで。`rbrun.c` の `R` / `RS`、`rbcore_mrb.c` の `M`、
  `rbterm` / `rbfs` / `rbmachine` のグローバル、`rbfile_mrb.c` などのクラスのポインタはまだ 1 つなので、
  実機で同時に 2 つの Ruby を走らせるには、これらをインスタンスごとに分ける作業が要る
- 実機（2026-10-29）: 1MB ヒープで `samples/ruby/textattr.rb` が **all ok**（217ms、ヒープ 112,284 B、
  スタック 6,108 B）、`blit.rb` が **all ok**（434ms、ヒープ 109,684 B）、`fileio.rb` が **done**
  （ヒープ 104,152 B）。実行中の `[pmem]` で、ヒープが 0x15000180 の低位、スタック・端末・シンボル表・
  実行状態・端末が高位、固定の 4 ページの FB と重ならないことを確認した。`ruby state` 3,980 B は
  実行後も高位に残る。`fs_compat.rb` の 320KB は 1MB ヒープでは未解決（積み残し）

## 2026-10-31 -O2 とよく使う関数の並び（ユーザー指示: mruby のチューニング）
- FB 表示中（モード 2）の HAT.RB の core1 の PC: 67〜70% が表示の取得の間の待たせ（`core1_bell_isr`）、19% が `mrb_vm_exec`、残りは `iv_get`・`flo_to_i`・`math_cos`・`mrb_vm_find_method` などに散る（M640.RB は VM が 25%）
- **`-O2`**（`tools/mruby/rp2350.rb`、`SGNANO_MRUBY_OPT` で替えられる）と、**VM のすぐ後ろに VM から呼ぶ小さい関数を熱い順に並べる**（`ld/placement.cmake` の `SGNANO_RB_HOT`、8KB の境目から。
  `mrb_vm_exec` は -O2 で 35KB あり XIP キャッシュ 16KB より大きいので、並べるのは周りの約 3KB）。フラッシュは約 90KB 増える

  | | -Os（前） | -O2 | -Os + 並べる | **-O2 + 並べる** |
  |---|---:|---:|---:|---:|
  | MANDEL.RB | 0.584 秒 | 0.516 | 0.520 | **0.363**（-38%） |
  | HAT.RB | 14.60 秒 | 14.42 | 14.12 | **10.13**（-31%） |
  | M640.RB | 76.4 秒 | 59.8 | 65.9 | **48.8**（-36%） |

- 2 つは組で効く（片方だけでは 1〜2 割）。MicroPython は変わらない（mandel.py 0.745 秒・hat.py 12.4 秒）
- 2026-10-16 の -O2 が遅かったのは、並びがなりゆきで VM と周りの関数がキャッシュの同じ場所を取り合っていたためと考える（MicroPython の 2026-10-31 と同じ形）。mruby を差し替えたら PC を数え直して並びを見直す

## 2026-10-31 注意: バイナリの文字列の `size` はバイト数ではない
- `MRB_UTF8_STRING` で組んでいるので、`String#size` は UTF-8 として数えた文字の数。`File.open(path, "rb")` で読んだバイナリでも同じ（CRuby は ASCII-8BIT になり `size` = バイト数）。
  939,728 バイトの zip を `read(65536)` で読んで `size` を足すと 901,445、`bytesize` なら 939,728（読み込みは正しい）。**バイナリの長さは `bytesize` で数える**



## 2026-11-02 追加 gem（Data / JSON / Rational / Complex / CMath / Lazy / Chain / toplevel-ext）

ユーザー指示（追加 gem を検討）で、標準の mruby 4.0.0 と比べて抜けていたものと、JSON を足した。2026-11-02 に Bigint / Rational / Complex / CMath も足した（Rational は mruby-bigint が前提）。

- `GEMS`（`tools/mruby/rp2350.rb`）: `mruby-data` / `mruby-enum-lazy` / `mruby-enum-chain` / `mruby-toplevel-ext`
- JSON: `third_party/mruby-json`（mattn/mruby-json `b9871a463a1c7b7c81a3100aa128a17539ad7e53`、MIT）。parson の malloc/free を
  `mrb_malloc` / `mrb_free` にし、`MRB_DISABLE_STDIO` でファイル入出力（fopen/fputs）を外した。
- ホスト試験: `scripts/test_mruby.py` に `samples/ruby/gems2.rb`（Data / Lazy / Chain / JSON）を追加。全項目 OK
  （`fs_compat.rb` 74/74、既存の sample もそのまま）。
- ファームの増分: `.text` +8,996 B、`.rodata` +527 B、`.data` +562 B、`.bss` +3 B。SRAM は 341,968 B（+8,196、空き 182,320 B）、
  フラッシュの像は 2,446,200 B（+34,552 B）。`libmruby.a` は 11,643,546 -> 12,394,646 B（アーカイブ）。
- `require` / `load` / `require_relative`（`src/ruby/mrb/rbkernel_mrb.c`）も追加した。`require` は `$LOADED_FEATURES` で一度だけ、`load` は毎回。
  `.rb` は同じ VM でコンパイルして実行、`.mrb` はバイトコードとして読む。探索は「読み込み中のファイルのフォルダ → `$LOAD_PATH`（既定 `["." , "S:/SystemFiles/ruby"]`）→ S:/」。`require_relative` は読み込み中のファイルのフォルダだけ。
  見つからなければ `LoadError`。

## 2026-11-03 Kernel#system / exec

積み残しの残り。mruby から sgsh の 1 行実行を呼ぶ。

- `system(cmd)`: `sh_run_text` を走らせ、終了番号 0 なら `true`、それ以外は `false`。シェルが使えなければ `nil`。
  出力は `rb_out_write`（Ruby の端末・sgsh の sink）へ流す。
- `exec(cmd)`: 同じく走らせ、その終了番号で mruby を終える（`rb_mrb_exit_with_status` -> `run_main` の `setjmp` へ `longjmp`）。
- **sgsh が走っているとき**は、そのシェルの環境（cwd・変数・ヒープ）を使って実行する。`cd` は呼び手に残らないよう元に戻す。
  出力は sh_term へ直に書く（子の環が詰まって止まらないように）。
- **sgsh の外**（ファイラーから走らせた Ruby）では、256KB の PSRAM を取って画面を持たない一時的なシェルを作る。
  ファイル操作は Ruby と同じ `rbfs`（FAT・exFAT・NTFS・S:）を使う。終わったらヒープを返す。
- **入れ子の言語は起動しない**（mruby・MicroPython・SG BASIC・`.sgx`）。同じ SGX セッション／Ruby の状態を共有しているため。
  `ls`・`cat`・`cp`・`mv`・`rm`・`mkdir` などのシェル組み込みと、シェルから見えるファイル操作が対象。
- ホスト試験は `scripts/host_mruby/main.c` の強い `rb_shell_system_run`（`/bin/sh`）と `rb_mrb_exit_with_status`（`exit`）で確かめる。
  `scripts/test_mruby.py` に `samples/ruby/system.rb`（true / false / echo / 見つからないコマンド）と `exec.rb`（3 で終わる）を追加。
