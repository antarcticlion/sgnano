# sgsh から 3 言語を使う口の仕様（案）

版: 2026-11-02 ／ 積み残し（2026-11-02 に実装・実機確認まで済み）。

ユーザー指示: mruby と MicroPython は POSIX 版のコマンドの使い方を手本にそろえる。SG BASIC はそれに近い形で決める。
出力はシェルに取り込む（§5 の 1、2026-11-02 決定）。

---

## 1. コマンドの一覧

| 言語 | 実行・REPL | コンパイラ | 手本 |
|---|---|---|---|
| mruby | `mruby`、REPL は `mirb` | `mrbc` | mruby 4.0.0 の `mruby` / `mirb` / `mrbc`（`build_mruby/out/host/bin` の `-h` で確かめた） |
| MicroPython | `micropython`（引数なしで REPL） | `mpy-cross` | MicroPython v1.2x の UNIX 版と `mpy-cross` |
| SG BASIC | `sgbasic`（引数なしで直接モード） | `sgbc` | ホスト版 `src/basic/sgbasic` を、上の 2 つの形に寄せる（§4） |

- シェルの組み込みの別名（`alias` で上書きできる）: `ruby` = `mruby`、`irb` = `mirb`、`python` / `python3` = `micropython`、`basic` = `sgbasic`
- ファイル名だけで走らせる: `x.rb`・`x.mrb`・`x.py`・`x.bas`・`x.sgb`・`x.sgx`（拡張子で言語を選ぶ。`./x.rb` も）。`.mpy` は §3 の .mpy を入れたとき
- 終わりの状態（`$status`）: ふつうに終わったら 0、捕まえなかった例外・誤りは 1、`exit(n)` / `sys.exit(n)` / `SYSTEM n` は n
- 誤りの知らせ（例外・Traceback・`?SN ERROR`）は **stderr** へ。プログラムの出力は stdout へ
- 引数: プログラムの後ろの語は、Ruby の `ARGV`、Python の `sys.argv`（`sys.argv[0]` はファイル名）、BASIC の `COMMAND$`（§4）へ
- stdin: ファイルを指定せず、stdin が端末でなければ（パイプ・`<`）、stdin をプログラムとして読む（POSIX 版と同じ。`echo 'p 1+2' | mruby`）

## 2. mruby（mruby 4.0.0 の POSIX 版に合わせる）

```
mruby [switches] [programfile] [arguments]
  -b           load and execute RiteBinary (mrb) file   （.mrb は拡張子でも見分ける）
  -c           check syntax only                        （Syntax OK を stdout へ）
  -d           set debugging flags (set $DEBUG to true)
  -e 'command' one line of script                       （いくつも書ける。書いた順に 1 つのプログラムに）
  -r library   load the library before executing your script
  -v           print version number, then run in verbose mode
  --verbose    run in verbose mode
  --version    print the version
  --copyright  print the copyright
```

```
mirb [switches]                 Ruby の REPL（ファームの REPL。プロンプトは mirb と同じ "> "、続きの行は "* "）
  -v / -d / -r library           mruby と同じ意味
```

```
mrbc [switches] programfile...
  -c           check syntax only
  -o<outfile>  place the output into <outfile>; required for multi-files   （無ければ x.rb -> x.mrb）
  -v           print version number, then turn on verbose mode
  -g           produce debugging information
  --remove-lv  remove local variables
  --no-optimize disable peephole optimization
  --verbose / --version / --copyright
```

- 入れないもの: `-B<symbol>` / `-S` / `-s`（C の配列を書き出す。sgnano では使い道が無い）、`--no-ext-ops`
- `-r library`: `File` で読めるパス（相対はいまのフォルダ）。mruby の `require` は無いので、読み込んで先に走らせる

## 3. MicroPython（v1.2x の UNIX 版と mpy-cross に合わせる）

```
micropython [<opts>] [-X <implopt>] [-c <command> | -m <module> | <filename>] [args...]
  -h               print this help message
  -i               enable inspection via REPL after running command/module/file
  -O[N]            apply bytecode optimizations of level N
  -v               verbose (trace various operations); can be multiple
  -c <command>     execute command
  -m <module>      run module (as script)        （import がファイルから読めるようになってから。積み残し）
  -X compile-only  parse and compile only         （文法だけ確かめる）
  -X heapsize=<n>[K|M]   set the heap size for the GC （既定 512K。PSRAM から）
```

- 引数なしなら REPL（いまのファイラーの p と同じ）。REPL を抜けるのは Ctrl-D
- `mpy-cross`: `.mpy` を書き出すには MicroPython の `MICROPY_PERSISTENT_CODE_SAVE` と、読む側の `MICROPY_PERSISTENT_CODE_LOAD` を有効にする（いまはどちらも 0）。
  入れるかは作業のときに決める（入れれば mruby の .mrb と同じく、`micropython x.mpy` で走る）

```
mpy-cross [<opts>] [-X <implopt>] <input filename>
  -o <output>      output file for compiled bytecode (defaults to input with .mpy extension)
  -s <source>      source filename to embed in the compiled .mpy file
  -O[N]            apply bytecode optimizations of level N
  -v               verbose
  -X heapsize=<n>  set the heap size for the GC
```

## 4. SG BASIC（上の 2 つに寄せた案）

ホスト版 `sgbasic` の使い方（`-q`・`-C`・`-o`・`--version`・`-h`）を残し、mruby・MicroPython にある口を足す。

```
sgbasic [switches] [programfile] [arguments]
  -e 'statement'   1 行のプログラム（いくつも書ける。行番号は付けなくてよい）       ← mruby -e / micropython -c に当たる
  -c               check syntax only（コンパイルだけして誤りを stderr へ。Syntax OK）   ← mruby -c
  -i               走り終わったら直接モード（OK のプロンプト）に残る                   ← micropython -i
  -b               .sgb として読む（拡張子でも見分ける）                                  ← mruby -b
  -q, --quiet      バナーと OK を出さない（ホスト版と同じ）
  -w, --width N    端末の幅（既定は端末の桁 = 80）
  --long-errors    長い名前の誤り（ホスト版と同じ）
  -v               版を出してから走らせる
  --version        版（SG BASIC Rev03.001）
  -h, --help
```

- 引数なしなら **直接モード**（`OK` のプロンプトで `LIST`・`RUN`・`LOAD` など。いまの sgbasic の対話の形）。抜けるのは `SYSTEM` か Ctrl-D
- 引数: プログラムの後ろの語は `COMMAND$`（GW-BASIC と同じく、空白でつないだ 1 つの文字列）。新しく足す関数
- 終わりの状態: `END` / 最後まで走った = 0、誤りで止まった = 1。`SYSTEM n`（n を足す）で n
- `sgbc`（コンパイラ。mrbc に合わせる）

```
sgbc [switches] programfile
  -o<outfile>      出力（無ければ x.bas -> x.sgb）
  -c               check syntax only
  -v / --version
```

- ホスト版の `sgbasic -C x.bas -o x.sgb` も、同じ意味のまま受ける（ホストの試しが使っている）

## 5. 作業のときに決めること

1. **画面と入出力の形**: **(b) に決めた**（2026-11-02 ユーザー判断: シェルから使う人は POSIX の作法を期待する）。
   puts / print / PRINT をシェルの端末（バックログにも入る）へ流し、stdin（gets / input / INPUT）・stdout・stderr・パイプ・リダイレクトをつなぐ。
   各言語の端末の口（Ruby の `rbterm`、MicroPython の `mp_hal_stdout_tx_strn`、SG BASIC の `term_write` / `term_getline`）をシェルの io へ差し替える
2. **入れ子の手直し**: シェル自体が走るプログラムの枠（`rbrun.c` の R・SGX の session）を 1 つ使っているので、その中から言語を走らせられるようにする
3. `mpy-cross` と `.mpy`: **いまは入れていない**（`mpy-cross` のコマンドはあるが、`MICROPY_PERSISTENT_CODE_SAVE` / `LOAD` が 0 なので「not built in this firmware」を返す。§3。`micropython -m` も import がファイルから読めるようになるまで未対応）
4. 画面モード: 言語が画面モード（2〜7）を変えたら、終わったときにシェルのモード 1 へ戻して描き直す
