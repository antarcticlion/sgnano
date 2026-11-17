# 3 言語をシェルに統合する段取り（実装の手引き）

版: 2026-11-02 ／ 仕様は 仕様メモ（内部）、積み残し。別のエージェントが 1 段ずつ進められるように、段ごとに「触る所・やること・確かめ方」を書く。
**各段は単独でコミットできる大きさにし、段ごとに実機で確かめる**。決まりごと（SRAM・フラッシュの置き場・書き込みの作法など）は docs/DEVELOPMENT.md に従う。

---

## 0. いまの形（2026-11-02 に調べた事実）

### 走らせる枠
- 走るプログラムの状態は `src/ruby/rbrun.c` の `R`（1 つだけ）。`R.state` が `RB_IDLE` でないと `rb_open` / `rb_open_repl` / `rb_open_shell` は「already running」で断る
- **シェル自体がこの枠を使っている**: `rb_open_shell` -> `R.is_sgx = R.is_shell = true` -> `sgx_start_task` -> `sgx_session_start_builtin(sgsh_builtin_main, ...)`（`src/sgx/sgx.c`）
- SG BASIC も SGX の session（`sgx_session_start_builtin(sgbasic_builtin_main, ...)`）。session の状態 `S` は 1 つだが、その中にプログラムを `MAX_PROGS`（4）まで持てる（`prog_new`、SGX の `spawn` はこれを使う）
- mruby は `rb_work` が `mb_task_create(&rb_tcb, "ruby", rb_task, ...)` で自分のタスク（優先度 9、スタック 32KB は PSRAM）を作って走らせる。ヒープなどは `run_mem_t`（`pmem_alloc`）
- MicroPython は `src/python/pyrun.c`（`py_open_file` / `py_open_repl`、状態 `PY`）。Ruby の `R` とは別の状態で、`py_active()` で見る
- `rb_work` は `sgx_live` の間、終わりを見るだけですぐ戻る（ファイラーのループは止まらない）

### 出力と入力が集まる所
| 言語 | 出力 | 入力 |
|---|---|---|
| mruby | `rbterm_write`（`src/ruby/rbterm.c:202`。puts / print / p、誤りの知らせも `rbterm_puts`、`rbrun.c` の 882・953・965 行あたり） | `rb_stdin_read`（`rbrun.c`。gets・STDIN.read、`rbfile_mrb.c` が呼ぶ） |
| MicroPython | `mp_hal_stdout_tx_strn` -> `sgnano_py_term_write`（`pyrun.c:576`）-> `rbterm_write`。Traceback も同じ道 | `mp_hal_stdin_rx_chr` -> `sgnano_py_key_read`（キーを 1 つずつ。REPL の行の編集と `input()`） |
| SG BASIC | SGX の `term_write` -> `a_term_write`（`sgx.c:352`）-> `rbterm_write` | SGX の `term_getline` -> `a_term_getline`（`sgx.c:353`）-> `rb_stdin_read` |
| シェル | 自前の端末 `term_out`（`src/shell/sh_term.c`）。コマンドは `io_t`（in / out / err）で読み書き（`src/shell/sh_int.h`） | `io_getline`（パイプ・`<` のバッファか、端末で 1 行） |

**つまり、出力は `rbterm_write`、入力は `rb_stdin_read` と `sgnano_py_key_read` の 3 か所を差し替えれば、3 言語の入出力をシェルへ向けられる。**

---

## 1. 段取り

### 段 1: 出力と入力の差し替え口（ファーム側、言語は変えない）
**【2026-11-02 済み】** `rbterm_set_sink` / `rbterm_sink_has_in` / `rbterm_sink_read`、`rbterm_write_err` / `rbterm_puts_err` を足した。エラーは `rbrun.c` の各所で stderr 側へ、MicroPython の Traceback は `sgnano_py_error_print`（`MICROPY_ERROR_PRINTER`）で stderr 側へ。sink が無いときの動きは変えていない（ホスト試験・実機の Ruby/Python で確認）。入力の読み口は段 2 のシェルから使う。

- `rbterm.c` に「行き先」を足す: `rbterm_set_sink(void (*out)(const char *, unsigned, bool is_err, void *), void *user)`。立っていれば `rbterm_write` はテキスト面に描かず sink へ渡す
- 誤りの知らせ用に `rbterm_write_err` / `rbterm_puts_err` を足し、`rbrun.c` の SyntaxError・例外の表示、`pyrun.c` の Traceback（`mp_obj_print_exception` に渡す print を stderr の版に）をそちらへ
- 入力: `rb_stdin_read` と `sgnano_py_key_read` も、sink の「読む口」があればそこから読む（`int (*in)(unsigned char *buf, unsigned max, void *)`、0 = 終わり）
- sink を呼ぶのは言語のタスク（core1）。シェルの側でバッファへ貯めるだけにし、テキスト面へは描かない（描くのはシェル）
- 確かめ: sink が無いときは今までどおり（Ruby・Python・BASIC の testapp が変わらず動く。`scripts/stress_sgx.sh` も）

### 段 2: シェルの中から走らせる枠（入れ子）
**【2026-11-02 済み（`8164f15`）】**
- `R` を使っているのはシェルなので、子は別の枠で走らせる。案:
  - **mruby**: `rbrun.c` に「シェルの子」用の入口 `rb_child_run(path, argc, argv, sink)` を作る。`R` の実行の部分（`run_mem_t` の確保・`rb_task` の作成・後片づけ）を、シェルの状態と別に持てるように切り出す。画面の頼み（Machine）は `R` の `rq_kind` を使うので、子の間は `R` の頼みの受け口を子が使う（シェルは子の間は画面を触らず待つ）
  - **MicroPython**: もともと `PY` が別の状態なので、`py_open_file` に「sink と argv を受ける」版を足す（`py_child_run`）。シェルは `py_active()` が落ちるまで待つ
  - **SG BASIC・.sgx**: 同じ SGX の session の中で `prog_new` を使い、子のプログラムとして始める（`spawn` の組み込み版 `sgx_spawn_builtin`）。子の `term_write` / `term_getline` は、プログラムごとに sink を持たせて振り分ける（`a_term_write` で呼び手のプログラム `P` を見る）
- シェルは子が終わるまで眠って待つ（`SA->sleep_us`）。その間もキー（Ctrl-C）を見て、子を止める（mruby は `R.stop_req`、Python は `KeyboardInterrupt`、SGX は `sgx_force_stop` の子の版）
- 確かめ: シェルから子を走らせ、終わったらシェルに戻り、`$status` が仕様どおり。子の中で ESC・Ctrl-C で止まる

### 段 3: 画面モード
**【2026-11-02 済み（`3ffca0a`）】**
- 子が画面モード（2〜7）を変えたら、終わったときにモード 1 に戻し、シェルが `term_force_redraw()` する
- 子が FB・ローレゾ・ビットマップを使う間、シェルは描かない（テキスト面は子のものでもある。子の `text_put` などは子の画面）
- 確かめ: `mode3.rb`・`mode7.bas` などをシェルから走らせて戻る（`samples/*/testapp/`）

### 段 4: コマンド（仕様の §2〜§4）
**【2026-11-02 済み（`500e455`）】**
- `src/shell/sh_cmds.c` に `mruby` / `mirb` / `mrbc` / `micropython` / `mpy-cross`（入れるなら）/ `sgbasic` / `sgbc` を足す。スイッチは 仕様メモ（内部） のとおり
- 拡張子で走らせる: `run_argv`（`sh_main.c`）で、コマンドが見つからず語に `.rb` などが付いていればその言語で
- 組み込みの別名: `ruby` `irb` `python` `python3` `basic`（`sgsh_builtin_main` の初めに `sh_alias_set`）
- 引数: `ARGV`（mruby の `mrb_define_global_const` で）、`sys.argv`（`mp_sys_argv`）、BASIC の `COMMAND$`（新しい組み込みの関数。`src/basic/src/vm/builtins.c` と `keywords.def`）
- stdin をプログラムとして読む（ファイルを指定せず、stdin が端末でないとき）
- `-e` / `-c`（mruby）、`-c` / `-i` / `-X compile-only`（MicroPython）、`-e` / `-c` / `-i`（BASIC）
- `mrbc`: いまのファイラーの M（`rbrun.c` の `compile_only`）を子として。`sgbc`: sgbasic のコンパイル（ホスト版の `-C` の中身）
- 確かめ: 下の「試し」

### 段 5: SG BASIC の言語の足し
**【2026-11-02 済み（`e59b656`。実機で `COMMAND$` と `SYSTEM 3` の `$status` まで確認）】**
- `COMMAND$`、`SYSTEM n`（終わりの番号）、`-e` の 1 行のプログラム（行番号なし）
- ホストの試し `make -C src/basic test` に足す（`src/basic/tests/run_tests.py`）

### 段 6: ドキュメント
**【2026-11-02 済み】**
- docs/DEVELOPMENT.md（シェルの行・積み残しを済みに）、`docs/notes/system.md` に日付の節、3 言語の解説書に「シェルから使う」節、`docs/machine_api.md` は変えない

---

## 2. 試し方

- 書き込み: `for i in 1 2 3; do scripts/flash_swd.sh --rescue; ADAPTER_SPEED=1000 SGNANO_FLASH_NO_CD_STOP=1 scripts/flash_swd.sh && sleep 14 && scripts/check_cores.sh && break; done`
  （2026-11-01: 既定の速さ 5000 では消す段で時間切れが続いた）
- シェルを起動: `python3 <rc.py の形で> "FCD A:/"` のあと `scripts/console.sh -k 'x'`。遠隔コマンドの送り方は docs/DEVELOPMENT.md の sgremote の節（`0x1E` で始まる行）
- 1 行ずつ打って結果を見る: `python3 scripts/sh_test.py lines.txt`（プロンプトが戻るまで待つ。`[` で始まる行はログとして落とすので、出力が `[` で始まる試しは避ける）
- 画面の見た目: シェルの `screenshot`（約 900KB の空きが要る。A: でよい。S: は足りない）で PNG にし、`scripts/zm.sh get --remote-file A:/scr_....png DIR` で取ってくる。**シェルが走っている間は ZMODEM の遠隔コマンドが「busy」で断られる**ので、`exit` してから
- 書き込みの試しは A:（FAT32）と B: / C:（HDD の exFAT / NTFS のときだけ。ドライブの文字はつなぎ方で変わるので `drives` で確かめる）。作ったものは消す
- 試しの例（段 4 のあと）:
  ```
  echo 'puts 1+2' > t.rb ; mruby t.rb
  mruby -e 'p ARGV' a b
  mruby t.rb | wc -l
  mruby -e 'raise "x"' 2> err.txt ; echo $status ; cat err.txt
  echo 'print(input())' > t.py ; echo hello | micropython t.py
  micropython -c 'import sys; print(sys.argv)' x y
  sgbasic -e 'PRINT 6*7'
  sgbc t.bas ; sgbasic t.sgb
  ```

## 3. 気をつけること（踏みそうな所）

- **シェルの静的な配列は SRAM の .bss に入る**。大きいものは PSRAM のヒープ（`sh_alloc`）から取る（2026-11-01 に 28KB 増えて直した）
- 言語のタスク（core1）から sink へ書く間に、シェルのタスクが同じバッファを読まないように（`mb_mutex` か、子が終わってから読む）
- 子の出力が大きいとき（`seq` 相当を何十万行）: パイプのバッファは PSRAM のヒープ（シェルは最大 2MB）。端末へは流しながら（貯めずに）描く
- `rbterm_open` は Ruby の端末の置き場を PSRAM に取る。sink のときは開かなくてよいか確かめる
- ファイラーの決まり: ファイラーに手を入れたら `FILER_REV_MINOR`（`src/filer/fchrome.h`）を 1 つ上げる
