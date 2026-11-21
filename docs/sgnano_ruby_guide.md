# sgnano Ruby プログラミング仕様書（mruby 環境）

版: 2026-11-17 ／ 対象: sgnano のファームウェア（RP2350B、mruby 4.0.0）

この文書は、sgnano で動く Ruby のプログラムを**ほかの人や AI が書く**ための仕様書です。使える書き方・クラス・メソッドは、
実機と同じ処理系をホストで動かして**一つずつ確かめたもの**です（推測ではありません）。ここに無いメソッドは「無い」と考えてください。

【2026-11-17 の変更】**FB・ビットマップ・画像の描画**（線・図形・パス・文字・転送）と**圧縮と書庫**（`Machine::Archive`）を足した（§7・§6。ABI 5.3・5.12）。描画は `Machine.fb`・`Machine.bitmap`・`Machine::Image` が同じメソッドを持ち、状態と描画のメソッドは自分を返すので続けて書ける。

【2026-11-01 の変更】**同じ機械を Python（MicroPython）と SG BASIC からも同じ口で使える**ようになった（対応表 `docs/machine_api.md`、
仕様書 `docs/sgnano_python_guide.md`・`docs/sgnano_basic_guide.md`）。そろえるために Ruby に足したもの: 定数 `Machine::TEXT_GRAY`（8）と別名 `TEXT_UNDER`・`TEXT_DH`・`TEXT_DW`、
`lr.obj_visible`（読む）。**ローレゾのマップは 1 ます 16 ビット**（ABI 3.0、2026-10-31: タイル 0〜1023・パレット 0〜15。§7）。速さの表（§10）を測り直し、Python・BASIC と並べた。

【2026-10-29 の変更】**倍角の上下左右ライン**を、半角セルごとではなく倍角文字全体の外周だけに引くようにした（取り消し線はセルごと）。
**`Machine.text_attr_at(x, y, attr)`** を足し、セルの字を変えずに属性だけを書き換えられるようにした（倍角の印と位置の印は残す。§7）。
**`Sound.play` が SGT（SGNO TRACKER の曲）も再生できる**ようになった（`samples/sound/NOISE_ROCK.SGT`、§9。ABI 1.5）。

【2026-10-25 の変更】**`eval`・`binding`**（文字列のコードを走らせる。`instance_eval` / `class_eval` に文字列も、`Proc#binding`。§4。mruby-eval・mruby-binding・mruby-proc-binding）。**`Set`**・**`Method` / `UnboundMethod`**（`obj.method(:name)`）・**`ObjectSpace`**（数とメモリの量）を足した（§4。mruby-set・mruby-method・mruby-objectspace・mruby-os-memsize）。**【2026-11-02】`Data`・`JSON`・`Rational`・`Complex`・`CMath`・`Enumerator::Lazy` / `Enumerator::Chain`・トップレベルの `include`/`extend`・`require` / `load` / `require_relative` を足した（§4。mruby-data・mruby-json・mruby-enum-lazy・mruby-enum-chain・mruby-toplevel-ext、require は `src/ruby/mrb/rbkernel_mrb.c`）。**
終わりの状態の行に、コンパイルと実行の時間を出すようにした（§2）。

【2026-10-24 の変更】**画面モード 7**（320x200x8 のビットマップ、`Machine.bitmap`・`Machine::Bitmap`、§7）と **ペンタブレット**（`Machine.tablet`、§7）を足した（どちらもファームは 2026-10-23 から）。
C で書くプログラム（外部実行ファイル `.sgx`）は別の文書 `docs/sgx_abi.md`（PDF は `docs/sgx_abi.pdf`）。

【2026-10-18 の変更】**音**（`Sound`、§9）を足した。速さの表（§10）を、表示の仕組みを変えた（パイプライン化）あとのファームで測り直した。

【2026-10-16 の変更】処理系を mruby/c 4.0.0 から **mruby 4.0.0** に替えた。`ensure`・lambda・`Struct`・`case ... in` などが使えるようになり、
「黙って無視する」メソッドは無くなった。整数は 32 ビットの Fixnum で、あふれると **Bigint**（mruby-bigint）に昇格する。
2026-10-17 に**画面モード 3**（CLUT8 の FB・ローレゾ面、§7）と**画面モード 4〜6**（CLUT4 の FB・FB なし・ローレゾだけ、§7）を足した。2026-10-16 に、**テキストの属性と位置**（ANSI のエスケープ列・`Machine.text_attr`・`locate`・`text_put`、§5・§7）、**三角形と矩形のブロック転送**（`fb.triangle`・`fill_triangle`・`blit`・`get_block`・`put_block`、§7）、**ファイルの属性と日時**（`File.stat`・`File.mtime`・`File.chmod`・`File.set_attributes`）と **`Time`**（§6・§8）、**キー入力**（`gets` と `Machine.key` など、§5・§7）を足した。

---

## 1. 環境のあらまし

| 項目 | 内容 |
|---|---|
| 処理系 | mruby 4.0.0（組み込み向けの Ruby）。ソースは本体の中でコンパイルする |
| 画面 | 640x480（31kHz）。重ねる面は 3 つ: **テキスト面**（80 桁 x 30 行。上 28 行がプログラムの出力の端末、最下行が状態の行）、**フレームバッファ（FB）**（640x480、形式は RGB555・CLUT8（256 色）・CLUT4（16 色）、4 ページ）、**ローレゾ面**（320x240、BG 2 面 + オブジェクト 128 個）。`Machine.mode` の**画面モード 0〜6** で組み合わせを選ぶ（0 なし / 1 テキスト / 2 + RGB555 / 3 + ローレゾ + CLUT8 / 4 + ローレゾ + CLUT4 / 5 テキスト + ローレゾ / 6 ローレゾだけ。§7）。始めはモード 1 |
| メモリ | ヒープ 1MB（PSRAM）、スタック 32KB。ソースは 1MB まで |
| 整数 | 32 ビットの Fixnum（-2147483648〜2147483647）。あふれると **Bigint** に昇格する（`2 ** 100` も扱える） |
| 浮動小数 | 倍精度（double）。`p` / `to_s` の表示は**有効 15 桁**（`1.0/3` は `0.333333333333333`、`1e20` は `1.0e+20`） |
| 文字列 | UTF-8。`size` / `length` は文字数、`bytesize` はバイト数 |
| 入力 | 行の入力は `gets`（標準入力）、1 つずつは `Machine.key`・押している間は `Machine.key_down?`（§5・§7）。**ESC は実行を止める**（プログラムには届かない） |
| 出力 | `puts` / `print` / `p` / `printf` は画面の端末（上 28 行）と、開発用のシリアルの両方へ |

## 2. プログラムの置き場と実行

- USB メモリなどのドライブ（FAT・exFAT・NTFS）に、拡張子 `.rb`（ソース）か `.mrb`（バイトコード）で置く
- ファイラーでファイルを選んで **Enter** で実行。始めは**画面モード 1**（テキストだけ）
- 実行中は画面の最下行が状態の行（「running (ESC: stop)」）。**ESC** で止める（書き込みの途中でもファイルは壊れない）
- 終わると「finished  コンパイル 0.018 秒  実行 0.069 秒 -- press any key」（`.mrb` は実行だけ。ミリ秒に四捨五入、0 なら「0.001 秒未満」。実行は走り始めてから finished を出す直前まで）。何かキーでファイラーへ戻る。画面モードと FB の表示は実行前に戻り、FB に描いた絵は残る
- ファイラーの **M** で `.rb` をコンパイルし、同じフォルダに `.mrb` を書き出す（コンパイルは 200 バイトで約 3ms なので、差は小さい）
- ファイラーの **I**（または Ctrl+F5）で **REPL**（2026-10-30）。VM を開いたまま 1 行ずつ Ruby を走らせる。`>>` のあとに打って Enter、
  `def`・`if`・`do` などの続きは `..` で待つ。結果は `=> 値`、例外は `Exception: ...`。**Ctrl-D**（行の頭）か **ESC** で終わり
- 構文の誤りは「SyntaxError: 行:桁: 理由」と出る。捕まえなかった例外は「Exception: #<クラス: メッセージ>」
- **ソースは ASCII で書くのが安全**（コメントも英語に）。文字列の中の日本語は表示できるが、本体のエディタでは ASCII しか打てない。
  日本語の文字列は `"\u65E5\u672C"` のようにも書ける

### 2.1 シェルから使う（2026-11-02）

ファイラーで **x** を押すとシェル **sgsh** が開く。mruby のコマンドは POSIX 版に寄せてある。

```
mruby [switches] [programfile] [arguments]
mruby -e 'puts 1+2'                 # 1 行のプログラム。いくつも書ける
mruby -c file.rb                    # 文法だけ（Syntax OK）
mruby -r library.rb -e 'p ARGV' a b # 先に library.rb を走らせる
mruby file.rb a b                   # ARGV = ["a", "b"]（ファイル名は入らない）
mirb                                # Ruby の REPL（Ctrl-D / ESC で終わり）
mrbc file.rb                        # file.mrb を書き出す（-o out、-c は文法だけ）
mruby file.mrb                      # バイトコードを走らせる
```

- `ruby` は `mruby`、`irb` は `mirb` の別名（`alias` で上書きできる）
- `file.rb` のように**拡張子だけで**走らせられる。`run file.rb a b` でも同じ
- シェルのパイプ・リダイレクト・stdin がそのまま使える: `echo 'p 1+2' | mruby`、`mruby -e 'puts 1' > out.txt`
- 出力はシェルの端末、`SyntaxError` や例外は stderr（`2>` で分けられる）。`$status` は正常 0、例外・誤り・Ctrl-C は 1
- 実行中に **Ctrl-C**（または Shift+ESC）で子だけを止めてシェルへ戻る。子が画面モード 2〜7 を使ったら、終わりにモード 1 へ戻して描き直す

## 3. 言語として使える書き方

確かめて**使える**もの:

- `class`（継承・`super`・`initialize`・`attr_accessor` / `attr_reader`）、`module` と `include`、インスタンス変数・グローバル変数（`$x`）・定数
- `def`（省略できる引数・キーワード引数・`*args`・ブロック引数・`yield`・`block_given?`・1 行の `def f(x) = x + 1`）
- `if` / `unless` / `case`〜`when`（範囲も）/ `case`〜`in`（パターンマッチ）/ 三項演算子 / `while` / `until` / `loop` / `break` / `next`
- `begin`〜`rescue`〜`else`〜`ensure`、`retry`、`raise`、自分の例外クラス（`class MyErr < StandardError; end`）、`catch` / `throw`
- `lambda` / `proc` / `->(x) { }` / `&:sym`、`Class.new`・`define_method`・`send`・`respond_to?`・`instance_variable_get` / `set`・`freeze`
- `Struct`、`Fiber`、`Comparable`（自分の `<=>` で `sort` も `clamp` も）、`Enumerator`（`each_slice(2).to_a` など）
- 多重代入（`a, b = b, a`）、文字列の式展開（`"#{x}"`、自分のクラスの `to_s` も呼ばれる）、ヒアドキュメント（`<<~EOS`）、シンボル、
  ハッシュの書き方（`{ a: 1, "b" => 2 }`）、範囲（`1..10`、`1...10`）
- `Float::INFINITY`、`format` / `sprintf` / `String#%`（`"%05.2f" % x`）、`Integer("12")`、`10.to_s(2)`
- 正規表現（`Regexp.new("...")`・`=~`・`match`・`scan`・`gsub` / `sub`）。Onigmo 6.2.0 に 2026-10-23 のセキュリティ修正を適用したもの。
  **正規表現リテラル `/.../` は mruby の構文では使えない**ので、`Regexp.new("\\d+")` のように書く。
  例: `m = Regexp.new("(\\d+)-(\\d+)").match("10-20"); m[1] #=> "10"`

**無い**もの（代わりの書き方）:

| 書き方 | 状態 | 代わりに |
|---|---|---|
| `$!`（いまの例外） | **いつも nil**（`x = (foo rescue $!)` も nil） | `rescue => e` で受けて `e` を使う |
| `String#encoding` | 無い | UTF-8 だけ |
| 大きな整数（`2 ** 100`） | Bigint（mruby-bigint。メモリを使う） | Float（`2.0 ** 100`） |

## 4. 組み込みのクラスとメソッド

CRuby の基本的なメソッドはほぼある。下は確かめたもの（`respond_to?` と値で）。

| クラス | メソッド |
|---|---|
| Object（どこでも） | `puts` `print` `p` `printf` `sprintf` `format` `raise` `sleep(秒)` `sleep_ms(ミリ秒)` `loop` `rand` `srand`（§8） `catch` `throw` `lambda` `proc` `is_a?` `kind_of?` `nil?` `class` `dup` `inspect` `to_s` `frozen?` `freeze` `send` `respond_to?` `tap` `then` `itself` |
| Integer | 四則・`**`・ビット演算、比較 `abs` `to_i` `to_f` `to_s`（`to_s(2)` も）`chr` `clamp` `times` `upto` `downto` `step` `even?` `odd?` `zero?` `gcd` `lcm` `divmod` `pow` `digits` `bit_length` `succ` |
| Float | 四則・`**`、比較 `abs` `to_i` `to_f` `to_s` `round`（`round(2)` も）`floor` `ceil` `truncate` `nan?` `infinite?` `finite?` `divmod` |
| String | `+` `*` `<<` `[]` `[]=` `%` `size` `length` `bytesize` `to_i` `to_f` `to_s` `to_sym` `chomp` `strip` `split` `index` `include?` `start_with?` `end_with?` `upcase` `downcase` `capitalize` `swapcase` `tr` `delete` `squeeze` `sub` `gsub`（文字列でも `Regexp` でも）`reverse` `center` `ljust` `rjust` `chars` `bytes` `lines` `each_char` `each_byte` `each_line` `getbyte` `setbyte` `byteslice` `slice` `insert` `partition` `count` `hex` `oct` `succ` `ord` `unpack` `empty?` |
| Array | `new(n) { }` `[]` `[]=` `<<` `push` `pop` `shift` `unshift` `first(n)` `last(n)` `include?` `index` `delete_at` `clear` `min` `max` `minmax` `uniq` `reverse` `join` `+` `-` `&` 和集合 `each` `each_with_index` `map` `select` `reject` `find` `inject` / `reduce` `sum` `count(x)` / `count { }` `sort` `sort_by` `min_by` `max_by` `flatten` `zip` `each_slice` `each_cons` `shuffle` `sample` `fill` `rotate` `compact` `take` `drop` `take_while` `tally` `group_by` `partition` `each_with_object` `cycle` `product` `combination` `permutation` `bsearch` `pack` `any?` `all?` `none?` `empty?` |
| Hash | `[]` `[]=` `each` `each_key` `each_value` `map` `keys` `values` `size` `key?` / `has_key?` `has_value?` `fetch` `delete` `merge` `select` `reject` `to_a` `sort_by` `min_by` `sum` `count` `find` `any?` `all?` `transform_values` `group_by` `filter_map` `dup` `empty?` `clear` |
| Range | `each` `first(n)` `last` `===` `map` `to_a` `include?` `sum` `min` `max` `select` `size` `count` `each_slice` |
| Math | `sqrt` `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `exp` `log` `log10` `log2` `hypot` `cbrt` など、定数 `Math::PI` `Math::E` |
| 例外 | `StandardError` `ArgumentError` `TypeError` `RuntimeError` `IndexError` `KeyError` `RangeError` `NameError` `NoMethodError` `FrozenError` `StopIteration` `FloatDomainError` `IOError` `EOFError` `NotImplementedError` `ZeroDivisionError` `SystemCallError`、`message` |

| Set（2026-10-25） | `Set.new(配列)` `Set[1, 2]` `<<` `add` `add?` `delete` `delete?` `include?` `member?` `size` `empty?` `clear` `merge` `subtract` `\|`（和）`&`（積）`-`（差）`^`（片方だけ）`subset?` `superset?` `proper_subset?` `proper_superset?` `disjoint?` `intersect?` `==` `each` `map` `select!` `reject!` `classify` `divide` `to_a` `inspect`。**`Array#to_set` は無い**（`Set.new(a)` で） |
| Method（2026-10-25） | `obj.method(:name)` -> Method: `call` `[]` `arity` `name` `owner` `receiver` `parameters` `unbind` `to_proc`（`map(&obj.method(:f))`）`>>` `<<`（合成）。`Klass.instance_method(:name)` -> UnboundMethod: `bind(obj)` `bind_call(obj, ...)` |
| eval・Binding（2026-10-25） | `eval(文字列 [, binding])`（まわりのローカル変数を読み書きできる）`binding` -> Binding: `eval(文字列)` `local_variable_get(:x)` `local_variable_set(:x, v)` `local_variable_defined?(:x)` `local_variables` `receiver`。`obj.instance_eval("...")` / `Klass.class_eval("def m; end")`（ブロックでも）、`proc { }.binding`。構文の誤りは `SyntaxError`（`rescue SyntaxError => e`）。1 回の `eval` はその場でコンパイルする（短い文で約 1ms） |
| ObjectSpace（2026-10-25） | `count_objects`（`{TOTAL:, FREE:, T_STRING: ...}`）`each_object(Klass) { }` `memsize_of(obj)`（バイト）`memsize_of_all`。メモリ切れの見当に |
| Data（2026-11-02） | `Data.define(:x, :y)` -> 値クラス。`new(1, 2)` / `new(x: 1, y: 2)`、`x` `y`、`==` `members` `to_h` `inspect`（`#<data Point x=1, y=2>`）`dup` `freeze`。不変の小さな値に向く |
| Enumerator::Lazy（2026-11-02） | `enum.lazy` から `map` `select` `reject` `take` `drop` `first(n)` `force` など。無限列・大きい列を途中まで |
| Enumerator::Chain（2026-11-02） | `enum.chain(other, ...)`、`+`、`each` `to_a` `size`。複数の列をつなぐ |
| JSON（2026-11-02） | `JSON.parse` / `load`（文字列 -> Hash / Array / 数 / 文字列 / true / false / nil）、`JSON.generate` / `stringify` / `dump` / `pretty_generate`、`Object#to_json`。**ファイル入出力（`JSON.parse_file` など）は無い** |
| Rational（2026-11-02） | `Rational(1, 2)` / `5r`。`numerator` `denominator` `to_i` `to_f`、四則・比較。整数の割り算を正確に扱う |
| Complex（2026-11-02） | `Complex(1, 2)` / `1+2i`。`real` `imaginary` `abs` `conjugate`、四則・比較、`Complex.polar` / `rectangular` |
| CMath（2026-11-02） | `CMath.sqrt` / `exp` / `log` / `sin` / `cos` / `tan` / `asin` / `acos` / `atan` / `sinh` / `cosh` / `tanh` / `asinh` / `acosh` / `atanh`。負数・複素数の平方根など |
| require / load（2026-11-02） | `require "foo"`（一度だけ。返り値 true / false）、`require_relative "foo"`（読み込み中のファイルのフォルダ）、`load "foo"`（毎回）。探索は「読み込み中のファイルのフォルダ → `$LOAD_PATH`（既定 `["." , "S:/SystemFiles/ruby"]`）→ S:/」。`.rb` はコンパイルして同じ VM、`.mrb` はバイトコード。見つからなければ `LoadError`。`$LOADED_FEATURES` を見る |
| `system` / `exec`（2026-11-03） | `system("ls S:/")` は sgsh の 1 行実行でコマンドを走らせる。終了番号 0 なら `true`、それ以外は `false`、シェルが使えなければ `nil`。出力は Ruby の端末へ出る。`exec("...")` はコマンドを走らせ、その終了番号で mruby を終える。**言語や `.sgx` を中から入れ子に起動することはできない**（同じセッションを共有するため。`ls`・`cat`・`cp`・`mkdir` などのシェル組み込みとファイル操作が対象） |

確かめて**無かった**もの: Integer の `pred`、Range の `step`（`1.step(10, 2)` は使える）、String の `scan`、`Array#to_set`。
`system` は別のプロセスを作らず、ファームの中の sgsh を走らせる。sgsh の外（ファイラーから走らせた Ruby）では、その場限りのシェル（ヒープ 256KB、画面なし）を作って実行する。`system` の中の `cd` は呼び手のフォルダを変えない（元に戻す）。
整数の `1 / 0` は `ZeroDivisionError`、`1.0 / 0` は `Infinity`。

## 5. 出力と待ち

- `puts` / `print` / `p` / `printf` は画面の上 28 行の端末へ（下から上へ流れる）。1 行 80 桁で折り返す。日本語（全角）も出る。
  改行（`\n`）・タブ・`\r`（行の頭へ）・`\b`（1 つ左へ）と、**ANSI のエスケープ列**（2026-10-16、下の表）を扱う。ほかの制御文字は捨てる
- **文字の色と属性**（2026-10-16）: 字は**いまの属性**（初めは明るい白・黒地）で書かれる。変え方は 2 つ（混ぜてよい）
  - ANSI のエスケープ列（CRuby の端末向けの書き方がそのまま使える。UART のログでも色が付く）:

    | 列 | 意味 |
    |---|---|
    | `\e[0m` | 初めの属性に戻す |
    | `\e[1m` / `\e[22m` | ボールド / 戻す |
    | `\e[4m` `\e[24m` ・ `\e[9m` `\e[29m` ・ `\e[53m` `\e[55m` | 下線・取り消し線・上線 / 戻す |
    | `\e[5m` / `\e[25m` | 点滅（1 秒に 1 回）/ 戻す |
    | `\e[7m` / `\e[27m` | 反転 / 戻す |
    | `\e[30m`〜`\e[37m`・`\e[90m`〜`\e[97m` / `\e[39m` | 文字の色（黒・赤・緑・黄・青・紫・水・白、90〜は明るい色）/ 初めの色 |
    | `\e[40m`〜`\e[47m`・`\e[100m`〜`\e[107m` / `\e[49m` | 背景の色 / 初めの色 |
    | `\e[行;桁H`（1 から数える）・`\e[A` `\e[B` `\e[C` `\e[D` | カーソルを動かす |
    | `\e[2J` ・ `\e[K` | 画面を消す（カーソルは動かない）・行の右を消す |
  - `Machine` のメソッド（§7。回転・縦倍角・横倍角はこちらだけ）
- 端末はテキスト面にあるので、`Machine.text_visible = false` で隠せる（FB の絵を見せたいとき）
- `sleep(秒)`（小数も可）・`sleep_ms(ミリ秒)` は待つ（その間も画面・USB は動く）
- 標準入出力: `STDOUT` `STDERR` `$stdout` `$stderr` は端末へ（【追記 2026-11-06】シェル sgsh から走らせたときは `STDERR` / `$stderr` は stderr として分かれる: `2> file`・パイプでは stdout と混ざらない。以前は stdout に書いていた）
- **標準入力（2026-10-16）**: `gets` `STDIN.gets` `$stdin.read` `getc` `readlines` などは、キーボード（USB か UART）から 1 行ずつ打ってもらう。
  打っている字は端末に出る（カーソルは `_`）。**BS** で 1 文字消す、**Enter** で行の終わり（`"\n"` が付く）、**行の頭で Ctrl-D**（か Ctrl-Z）で
  「入力の終わり」（`gets` は nil、`read` はそこまで）。打てるのは ASCII の字だけ（日本語・IME は無い）。待っている間は状態の行が「input」になる
  - 例: `print "name? "; name = gets.chomp`、終わりまで読む: `while (l = gets); ...; end`
  - 1 行は 250 バイトまで

## 6. ファイル（File・Dir・IO）

CRuby に近い形。`samples/ruby/fs_compat.rb`（74 項目）の出力が CRuby と**すべて同じ**になることを確かめてある（ホスト。実機の FAT32・exFAT・NTFS では
属性と日時を足す前の 65 項目）。

- パスは `"A:/dir/name.txt"`（ドライブ文字つきの絶対パス）か、いまのフォルダからの相対。`Dir.pwd` の始めは**スクリプトのあるフォルダ**
- 読み書き: `File.read(path)` `File.write(path, s)` `File.binread` `File.binwrite` `File.readlines` `File.foreach(path) { |l| }`
  `File.open(path, mode) { |f| ... }`（mode は `"r"` `"w"` `"a"` `"r+"` `"w+"` `"a+"`、`"b"` を付けてもよい）
- 開いたファイル: `read(n)` `gets`（区切りも）`getc` `getbyte` `each_line` `each_byte` `each_char` `readlines` `write` `print` `puts` `<<`
  `seek(n, IO::SEEK_SET / SEEK_CUR / SEEK_END)` `pos` `rewind` `eof?` `size` `flush` `close` `closed?`
- 名前・フォルダ: `File.exist?` `file?` `directory?` `size` `delete` `rename`（同じフォルダの中）`File.join` `basename` `dirname` `extname` `expand_path`
  `Dir.mkdir` `rmdir` `entries` `children` `each_child` `exist?` `empty?` `chdir`（ブロック付きも）`pwd`
- **属性と日時**（2026-10-16）: `File.stat(path)` -> `File::Stat`（`size` `size?` `zero?` `file?` `directory?` `ftype` `mtime` `ctime` `birthtime` `atime`
  `mode` `readable?` `writable?` `executable?`、sgnano の `attributes` `readonly?` `hidden?` `system?` `archive?`）、`File.mtime` `atime` `ctime` `birthtime`
  `writable?` `readable?`、開いたファイルの `f.stat` `f.mtime` `f.chmod`
  - 日時は `Time`（日本時間）。`mtime` = 書いた、`ctime` / `birthtime` = 作った、`atime` = 最後に開いた（FAT は日付だけ）。FAT・exFAT は 2 秒単位（exFAT は 1 秒まで）
  - 書くときの日時は本体の時計（LAN の NTP で合わせる）。**合わせていなければ 2026-10-04 12:00**（電池が無いので、LAN が無いと時計は分からない）。`Machine.clock_set?` で分かる
  - `File.chmod(0444, path)` で読み出し専用、`File.chmod(0644, path)` で外す（書き込みの許可のビットだけを見る）
  - 印をまとめて: `File.attributes(path)` -> Integer、`File.set_attributes(path, File::ATTR_HIDDEN | File::ATTR_ARCHIVE)`。
    `File::ATTR_READONLY`（1）`ATTR_HIDDEN`（2）`ATTR_SYSTEM`（4）`ATTR_DIRECTORY`（16、読むだけ）`ATTR_ARCHIVE`（32）。フォルダにも付けられる
  - **読み出し専用のファイルは、書く・追記・消す・名前の変更が `Errno::EACCES`**（Windows と同じ。CRuby の Linux と違い、消すのも断る）。読むのはできる
  - CD のファイルはどれも読み出し専用の印つき。日時は記録の日時
- ドライブ: FAT12/16/32・exFAT・NTFS は読み書き・名前の変更・フォルダの作成ができる。CD（ISO9660）は読むだけ
- 失敗は `Errno::ENOENT` `Errno::EEXIST` `Errno::ENOTEMPTY` `Errno::EISDIR` `Errno::ENOTDIR` `Errno::EROFS` `Errno::ENOSPC` `Errno::EIO` など（どれも `SystemCallError` の子）。
  閉じたファイルへの読み書き・読み出し専用への書き込みは `IOError`、知らない mode は `ArgumentError`
- 開いたファイルは中身を丸ごとメモリに持ち（1 つ 4MB まで、同時に 8 つまで）、`close` のとき（閉じ忘れ・ESC で止めたときは終わるとき）に書き戻す
- 1 回の読み書きは USB の都合で 0.1〜0.6 秒かかる。小さな書き込みを何度も繰り返さず、まとめて書く（1 つのファイルに 1000 回 `write` してから `close` は速い）

### システムのドライブ S:（SystemDrive、2026-11-02）
S: の空きとデフラグ。USB のドライブの空きは扱わない（`fs_free` / `usbfat_free` を使う）。

| 書き方 | 意味 |
|---|---|
| `SystemDrive.clusters` | データのクラスタ数（1,021） |
| `SystemDrive.free_clusters` / `free_bytes` | 空きのクラスタ数・バイト数（FAT を読んで数える） |
| `SystemDrive.map` | 1 クラスタ 1 バイトの String（0 = 空き、1 = 使用） |
| `SystemDrive.defrag_start` | ファイルの一覧を作る。`[ファイル数, 動かす中身のクラスタ数]`、始められなければ nil |
| `SystemDrive.defrag_step` | 1 歩進める。`[書いたクラスタ数, 全体, 見終えたファイル数, 全体, 終わったか]` |
| `SystemDrive.enfrag_start` / `enfrag_step` | 2 クラスタ以上のファイルをランダムに切り裂く（デフラグの試験・鑑賞用）。形は defrag と同じ |
| `SystemDrive.enfrag_seed(n)` | エンフラグの乱数の種（省くと起動からの時間） |
| `SystemDrive.zero_start` / `zero_step` | 空きクラスタを 0 で書く。`zero_step` は `[書いた数, 全体, 終わったか]` |
| `SystemDrive.active?` / `abort` | 途中か / やめる（ESC で止めたときは `rb_core_cleanup` が片付ける） |

- デフラグはフォルダを動かさず、ファイルだけを低い所へ寄せる。1 回の `defrag_step` で 4KB を 1 つ書くので、Ruby の画面を止めずに進められる
- 見本は `samples/ruby/defrag.rb`（モード 7 の Windows 95 風。S:/sbin/defrag.rb に置く）。`Enter` / `S` = デフラグ、`Z` = 空きの 0 クリア、`Q` = 終わる。
  `samples/ruby/enfrag.rb`（S:/sbin/enfrag.rb）は、2 クラスタ以上のファイルをランダムに切り裂く「エンフラグ」。デフラグの試験と地図の鑑賞用
- デフラグの途中で電源を切っても、元のファイルは壊れない（行き先の鎖を FAT に書く前に中身を写し、フォルダの項目を変えるまで元の鎖を消さない）

### 圧縮と書庫（Machine::Archive、2026-11-17、ABI 5.12）

- 方式（`fmt`）: `STORE` `DEFLATE`（生の deflate）`ZLIB` `GZIP` `BZIP2` `LZMA`（.lzma、13 バイトの頭）`XZ`（.xz、LZMA2）。
- `Machine::Archive.compress(s[, fmt[, level]])` -> String（バイト列）。fmt の既定は `GZIP`、level は 0〜9（既定 6）。
- `Machine::Archive.decompress(s[, fmt])` -> String。fmt を省くと先頭のバイトから見分ける。**4MB まで**。
- `Machine::Archive.compress_file(in, out[, fmt[, level]])` / `.decompress_file(in, out)`: 1 つのファイルを .gz / .bz2 / .xz / .lzma に。
- `Machine::Archive.list(path)` -> Hash の配列（`name` `size` `csize` `mtime` `crc` `dir`）。書庫は名前で見分ける（.zip / .7z / .tar / .tar.gz / .tar.bz2 / .tar.xz / .tar.lzma。1 つだけの圧縮も項目 1 つで返る）。
- `Machine::Archive.extract(path[, dest[, only]])` -> 書いたファイル数。フォルダは作り、同じ名前は置き換える。`only` は名前（フォルダなら下も）。
- `Machine::Archive.create(path, paths[, method[, level]])` -> 入れた数。`paths` はファイルかフォルダ（中身ごと）。`method` は **ZIP のときだけ**（`STORE` `DEFLATE` `BZIP2` `LZMA`）。tar の圧縮は名前（.tar / .tar.gz / .tar.bz2 / .tar.xz / .tar.lzma）で決まる。
- 作業場は PSRAM（プログラムのヒープは使わない）。入らなければ段を下げ、それでも足りず **FB を出していないとき**は FB の 4 ページ（2.4MB）を借り、返すときに 0 で消す（前に描いた絵は消える）。
- 長い呼び出しは **ESC で止められる**。誤りは `RuntimeError`（理由は英語）。
- 見本: `samples/ruby/arctest.rb`（シェルの `zip` / `7z` / `tar` と突き合わせる実機の試し）。

## 7. 画面: Machine と Machine::FrameBuffer

詳しくは `docs/machine_api.md` と本節。

| 書き方 | 意味 |
|---|---|
| `Machine.mode = 2` | テキスト + FB（RGB555、640x480）。0 = 表示なし、1 = テキストだけ、**3 = テキスト + ローレゾ + FB（CLUT8）**、**4 = テキスト + ローレゾ + FB（CLUT4）**、**5 = テキスト + ローレゾ**、**6 = ローレゾだけ**（2026-10-17、下の節）、**7 = テキスト（25 行）+ 320x200x8 のビットマップ**（2026-10-23、下の節）。8 以上は ArgumentError |
| `Machine.mode` | いまのモード |
| `Machine.fb_visible = true` | FB を見せる・隠す（モード 2 にすると見せる）。`Machine.fb_visible?` で読む |
| `Machine.text_visible = false` | テキスト面（端末）を隠す・見せる。`Machine.text_visible?` で読む |
| `Machine.vsync(n = 1)` | n フレーム（1 フレーム約 16.7ms）待つ。アニメーションの区切りに |
| `Machine.rgb(r, g, b)` | 0..255 の各色から画素の値（Integer）。実際の色は各 5 ビット（32 段階） |
| `Machine.ms` | 起動からのミリ秒（経過時間を測る） |
| `Machine.key` | 次のキー（届いた順）。無ければ nil（待たない）。値は文字のコード（`"a"` は 97）か特殊キーの `Machine::KEY_*` |
| `Machine.wait_key` | キーが来るまで待って返す |
| `Machine.key_down?(k)` | いま押しているか。k は `"a"`（1 文字）・`Machine::KEY_UP` など・`Machine::KEY_SHIFT` / `KEY_CTRL` / `KEY_ALT`。**USB キーボードだけ**（UART では常に false） |
| `Machine.clear_keys` | 届いて取っていないキーを捨てる |
| `Machine.keyboard?` | USB キーボードがつながっているか |
| `Machine.key_name(k)` | `"a"`・`"Enter"`・`"Up"`・`"F5"`・`"Ctrl-C"` など（表示用） |
| `Machine.clock_set?` | 本体の時計を LAN の NTP で合わせてあるか（合わせていなければ `Time.now` とファイルの日時は仮のもの） |
| `Machine.pages` | FB のページ数（4。各 640x480） |
| `Machine.display_page = p` | 表示するページ（0〜3）。フレームの境目で切り替わる（切り替わるまで待つ）。`Machine.display_page` で読む |
| `Machine.write_page = p` | FrameBuffer が描くページ（0〜3）。`Machine.write_page` で読む。範囲の外は ArgumentError |
| `fb = Machine.fb` | FrameBuffer を得る（`Machine::FrameBuffer.new` と同じ） |
| `fb.width` / `fb.height` | 640 / 480 |
| `fb.clear(color = 0)` | 全体を塗る（0 は黒）。1 回 約 33ms（モード 4 は 4ms） |
| `fb.pset(x, y, color)` | 点を打つ |
| `fb.pget(x, y)` | 画素の値。範囲の外は nil |
| `fb.line(x0, y0, x1, y1, color)` | 線を引く |
| `fb.rect(x, y, w, h, color)` | 矩形の外枠 |
| `fb.fill_rect(x, y, w, h, color)` | 塗りつぶした矩形 |
| `fb.triangle(x0, y0, x1, y1, x2, y2, color)` | 三角形の外枠（3 本の線） |
| `fb.fill_triangle(x0, y0, x1, y1, x2, y2, color)` | 塗りつぶした三角形（辺の上の画素も塗る。頂点の順はどちら回りでもよい） |
| `fb.blit(sx, sy, w, h, dx, dy [, page [, key]])` | 矩形のブロック転送: ページ `page`（省くか nil なら書き込みページ）の (sx, sy) から w x h を、書き込みページの (dx, dy) へ写す。同じページで重なってもよい。`key` を渡すとその色の画素は写さない（透明色） |
| `fb.get_block(x, y, w, h)` | 矩形を String に取り出す（w * h * 2 バイト。1 画素 2 バイト・下位バイトが先、行の順）。画面の外は 0。全部で 640x480 画素まで |
| `fb.put_block(x, y, w, h, s [, key])` | `get_block` の String を (x, y) へ書く。`key` の色は書かない。String の長さが w * h * 2 でなければ ArgumentError |

- 座標は Integer か Float（切り捨て）。画面の外は描かない（線・矩形・三角形・ブロック転送は切り取られる）。w・h が 0 以下なら何も描かない
- 絵（スプライト）を動かすには: 見えていないページ（例えば 3）に絵を描いておき、`fb.blit(0, 0, 32, 32, x, y, 3, 0)` で写す（0 = 黒を透明に）。
  背景を戻すのも `blit`（背景を置いたページから同じ所を写す）。`get_block` / `put_block` は絵を変数に持つとき（`samples/ruby/blit.rb`）
- 描くページと表示するページが同じなら、描いたものはすぐ画面に出る。ちらつかせたくないときは**ダブルバッファ**: 見えていない
  ページ（`write_page`）に描き、描き終えたら `display_page` で切り替える（`samples/ruby/flip.rb`）
- 終わると、ページは実行前（ファイラーの F6 / F7 で選んだもの）に戻る
- 色は `Machine.rgb` で作る（画素のビットの並びは基板で違うことがあるので、数を直接書かない）
- キーの定数: `KEY_ENTER`（13）`KEY_BS`（8）`KEY_TAB`（9）`KEY_DEL`（127）`KEY_SPACE`（32）`KEY_UP` `KEY_DOWN` `KEY_LEFT` `KEY_RIGHT`（0x90〜0x93）
  `KEY_PGUP` `KEY_PGDN` `KEY_HOME` `KEY_END` `KEY_INS`（0x94〜0x98）`KEY_F1`〜`KEY_F12`（0x81〜0x8C）`KEY_SHIFT` `KEY_CTRL` `KEY_ALT`（key_down? 用）。
  Ctrl+英字は 1〜26（Ctrl-A = 1）、Shift+F1〜F12 は 0xA1〜0xAC。**ESC は届かない**（実行を止める）
- `Machine.key` と `gets` は同じ環からキーを取る（`gets` で待っている間に打ったキーは行に入る）。キーは 64 個まで貯まり、あふれた分は捨てる
- ゲームのような使い方: 毎フレーム `Machine.key_down?(Machine::KEY_LEFT)` で動かし、`Machine.vsync` で区切る（USB キーボードのとき）。
  UART のように「押している間」が分からないときは `Machine.key` で 1 つずつ
- テキスト面は FB の上に重なる。文字の無い所は透けて FB が見える

### テキストの属性と位置（2026-10-16）
端末（画面の上 28 行 x 80 桁）の字の色・飾りと、書く位置を決める。属性は 1 つの整数（色 2 つと印の組み合わせ）。

| 書き方 | 意味 |
|---|---|
| `Machine.tattr(fg, bg = 0, flags = 0)` | 属性の数を作る。`fg`・`bg` は 0〜15 の色、`flags` は下の印を `\|` でつなぐ |
| `Machine.text_attr = a` / `Machine.text_attr` | いまの属性（`puts`・`print` の字に付く）を決める / 読む |
| `Machine.text_color(fg, bg = nil)` | いまの属性の色だけ変える（印はそのまま。`bg` を省けば背景もそのまま） |
| `Machine.locate(x, y)` / `Machine.cursor` | カーソルを (x, y) へ（0〜79, 0〜27）/ `[x, y]` |
| `Machine.text_put(x, y, str [, attr])` | (x, y) から str を置く。**カーソルは動かない**、右端で切れる（折り返さない）。使った桁を返す。`attr` を省けばいまの属性 |
| `Machine.text_attr_at(x, y, attr)` | セルの字はそのまま、属性だけ書き換える。倍角の印（`TEXT_DOUBLE_WIDTH` / `TEXT_DOUBLE_HEIGHT`）と位置の印（全角の右側・右半分・下半分）は残す。戻り値は新しい属性（2026-10-29） |
| `Machine.text_get(x, y)` | `[字, 属性]`。空きは `" "`、全角・横倍角の右側は `""`。範囲の外は nil |
| `Machine.text_clear(attr = Machine::TEXT_CLEAR)` | 全部を空白にしてカーソルを左上へ（属性を渡せばその地の色で塗る） |
| `Machine.text_cols` / `Machine.text_rows` | 80 / 28 |

- 倍角文字を構成する半角1セルずつ属性を変えるときは、`text_put` のあとに `text_attr_at` を各セルへ呼ぶ。
  全角の縦横倍角なら 4x2 の8セル。`text_attr_at` が残すのは倍角の印と位置の印だけで、線の印は渡した値に置き換わる
  （残したい線も `attr` に含める。色・線・反転などの変えたい印を渡す）

- 色（`Machine::TEXT_*`、PC-98 の 16 色）: `TEXT_BLACK`(0) `TEXT_BLUE`(1) `TEXT_RED`(2) `TEXT_MAGENTA`(3) `TEXT_GREEN`(4) `TEXT_CYAN`(5) `TEXT_YELLOW`(6) `TEXT_WHITE`(7、灰色に近い)、
  明るい色 `TEXT_BRIGHT_BLUE`(9) `TEXT_BRIGHT_RED`(10) `TEXT_BRIGHT_MAGENTA`(11) `TEXT_BRIGHT_GREEN`(12) `TEXT_BRIGHT_CYAN`(13) `TEXT_BRIGHT_YELLOW`(14) `TEXT_BRIGHT_WHITE`(15)。8 も黒
- 印: `TEXT_BOLD` `TEXT_UNDERLINE` `TEXT_STRIKE` `TEXT_OVERLINE` `TEXT_LEFT_LINE` `TEXT_RIGHT_LINE` `TEXT_REVERSE` `TEXT_BLINK`、回転 `TEXT_ROT90` `TEXT_ROT180` `TEXT_ROT270`（字を時計回りに）、
  `TEXT_DOUBLE_WIDTH`（横倍角: 1 字が 2 桁、全角は 4 桁）`TEXT_DOUBLE_HEIGHT`（縦倍角: 下の行も使う。その行の改行は 2 行進む）、
  `TEXT_FG_TRANSPARENT` `TEXT_BG_TRANSPARENT`（字・地を透かして FB を見せる）。
  左・右ラインは画面の左端・右端（回転しても同じ）。全角は文字全体の外側。倍角は、倍角文字全体の外周にだけ 1 ドットで引く
  （半角の文字セルごとには引かない。取り消し線だけはセルごと。2026-10-29）
- 決まった属性: `TEXT_DEFAULT`（初め: 明るい白・黒地）、`TEXT_CLEAR`（空き: 地が透けている）
- 別名（Python・BASIC と同じ名前、2026-11-01）: `TEXT_GRAY`（8）、`TEXT_UNDER` = `TEXT_UNDERLINE`、`TEXT_DH` = `TEXT_DOUBLE_HEIGHT`、`TEXT_DW` = `TEXT_DOUBLE_WIDTH`
- 例: `Machine.text_attr = Machine.tattr(Machine::TEXT_BRIGHT_YELLOW, Machine::TEXT_BLUE, Machine::TEXT_BOLD)`、
  `Machine.text_put(0, 27, " SCORE 1200 ", Machine.tattr(0, Machine::TEXT_CYAN))`（いちばん下の行に帯を置く）
- 見本: `samples/ruby/textdemo.rb`（全部の属性を並べる）、試験: `samples/ruby/textattr.rb`

### 画面モード 3: CLUT8 の FB とローレゾ（2026-10-17）
`Machine.mode = 3` で、FB は **CLUT8**（640x480、1 画素 1 バイト = パレットの色の番号 0〜255）になり、その上に**ローレゾ面**（320x240 を縦横 2 倍、
BG 2 面 + オブジェクト 128 個）、いちばん上にテキスト面が重なる。

**FB（CLUT8）**: `Machine.fb` のメソッドはそのまま使え、**色はパレットの番号**（`Machine.rgb` ではなく 0〜255）。`pget` も番号を返す。
`get_block` / `put_block` の String は 1 画素 1 バイト。`fb.bytes_per_pixel` で形式が分かる（1 = CLUT8、2 = RGB555）。

| 書き方 | 意味 |
|---|---|
| `Machine.fb_palette(i, r, g, b)` / `Machine.fb_palette(i)` | 番号 i（0〜255）の色を決める（0〜255）/ `[r, g, b]` |

- モード 3 に入ったときのパレット: 0〜215 = 6x6x6 の色の立方体（**番号 = 赤 x 36 + 緑 x 6 + 青**、各 0〜5）、216〜255 = 黒から白への灰色 40 段

**ローレゾ（`lr = Machine.lowres`）**: 8x8 画素のタイルをマップ（64 x 64 ます = 512 x 512 画素、端で折り返す）に並べる BG が 2 面（0 = 手前、1 = 奥）と、
オブジェクト（スプライト）が 128 個。画素は 1 バイトで、**0〜127 = パレットの色、128（`Machine::LowRes::TRANSPARENT`）= 透過**（下の面・FB が見える）。
パレットは `lr.palettes` 本（多くて 64 本、ファイラーから走らせると SRAM の空きに合わせて 32 本前後）x 128 色。**マップのますから指せるのはパレット 0〜15**（ABI 3.0）。

| 書き方 | 意味 |
|---|---|
| `lr.palette(pal, color, r, g, b)` | パレット pal（0〜`lr.palettes - 1`）の色 color（0〜127）を決める |
| `lr.pattern(tile, data)` | タイルの番号 tile から絵を書く。data は String（1 バイト 1 画素）か Integer の Array。8x8 の 1 タイル = 64 バイト（行の順） |
| `lr.tiles` | 使えるタイルの数（512〜2048。ファイラーから走らせると空きの SRAM に合わせて決まる。LAN をつないだ実機は 512） |
| `lr.map(plane, tx, ty, tile, pal = 0, hflip = false, vflip = false)` | 面 plane のます (tx, ty)（0〜63）にタイルを置く。**tile は 0〜1023（パターンの先頭 64KB）、pal は 0〜15**。反転もできる |
| `lr.map_get(plane, tx, ty)` / `lr.fill_map(plane, tile, pal = 0)` | `[tile, pal, hflip, vflip]` / 全部のますを同じタイルに |
| `lr.scroll(plane, x, y)` | 面の左上に見せるマップの位置（0〜511） |
| `lr.bg_visible(plane, on)` / `lr.obj_visible = on` | 面 / オブジェクト全体を出す・隠す（`lr.obj_visible` で読める） |
| `lr.obj(i, x, y, tile, w, h, pal = 0, pri = 0, hflip = false, vflip = false)` | オブジェクト i（0〜127）を (x, y) に出す。w は 8・16・32・64、h は 1〜256。絵はタイル tile から **w x h バイトを行の順に**（16x16 なら 256 バイト = 4 タイルぶん）。pri（0〜2）は BG との前後 |
| `lr.obj_move(i, x, y)` / `lr.obj_hide(i)` / `lr.obj_get(i)` | 位置だけ変える / 隠す / `[x, y, tile, shown]` |
| `lr.clear` | マップを 0 番のタイルに、オブジェクトを全部隠し、スクロールとラスタリストを 0 に（パターンとパレットは残る） |
| `lr.backdrop(y, r, g, b)` | 表示ライン y（0〜479）の背景色。テキスト・ローレゾ・FB の奥に出る |
| `lr.raster(plane, y, clut, sx, sy)` | 表示ライン y の BG plane のパレット補正 clut（マップのパレット番号に足す）とスクロール補正 sx/sy（画素） |
| `lr.raster_wave(plane, table, phase)` | 1 バイト 1 要素の String（128 = 0）から、全表示ラインの x 補正を一括で書く。ライン y は `table[(phase + y) % table.size] - 128`。毎フレーム phase を +1 すると波が動く |
| `lr.raster_clear` | ラスタリストを全ライン「指定なし」に戻す |
| `lr.width` / `lr.height` / `lr.palettes` / `lr.ready?` | 320 / 240 / パレットの本数 / 開いているか |

- **オブジェクト・スクロール・表示の切り替えは次のフレームの頭にまとめて効く**（描いている途中で半分だけ動いて見えないよう）。1 フレームぶん動かしたら `Machine.vsync`
- パレット・パターン・マップはすぐ書き換わる（表示の途中だと、そのフレームだけ上下で古い絵と新しい絵が混ざることがある）
- **表示の負荷の目安**（実機で測った値、1 ペアの予算 127µs）: CLUT8 + BG 2 面 + オブジェクト 4 個で、ふだん約 82µs。4 個が同じラインに集まると、
  BG を 1 面だけスクロールして約 112µs、2 面ともスクロールすると約 122µs（予算ぎりぎり）。**同じラインに 6〜8 個が重なると予算を越え**、ラインが遅れて画面が乱れる。
  同じ高さに集まるオブジェクトは少なく、動かさない面はスクロールしない。
  始めに絵・マップを大量に書いている間も重くなる（気になるなら書く間は `lr.bg_visible(0, false)` などで隠す）
- 終わるとローレゾ面は閉じる（中身は消える）
- **ラスタオペレーションリスト**（2026-10-28）: `lr.backdrop` / `lr.raster` で、表示ラインごとの背景色・BG の CLUT/スクロールを
  指定できる。`lr.raster_wave` はサイン波テーブル（512 / 384 個など）から全ラインの x 補正を一括で書き、
  位相を毎フレーム +1 すると波が動く。アプリ時間に書く（`lr.raster_clear` で全ラインを消す。
  書かないラインはグローバルの背景色と `lr.scroll` の値のまま）
- 見本: `samples/ruby/lowres.rb`（FB のグラデーション・星空・流れる床・弾む玉。先頭の `MODE` で 3〜6 を選ぶ）、
  `samples/ruby/raster.rb`（ラインごとの背景色・CLUT・スクロール。3/4/5/6 でモード、r でリストの有無、q で終わる）、試験: `samples/ruby/mode3.rb`

### 画面モード 4・5・6（2026-10-17）
ローレゾ面（`Machine.lowres`）の使い方はモード 3 と同じ。違うのは FB だけ。

| モード | 画面 | FB（`Machine.fb`） |
|---|---|---|
| 4 | テキスト + ローレゾ + FB | **CLUT4**（640x480、1 画素 4 ビット = 色の番号 0〜15）。`fb.bits_per_pixel` は 4、`bytes_per_pixel` は 1 |
| 5 | テキスト + ローレゾ | 画面に出ない（RGB555 のページに描ける。モード 2 にすると見える） |
| 6 | ローレゾだけ（320x240 そのままのタイミング） | 画面に出ない。**テキスト面も出ない**（`puts` は UART のログにだけ出る。`Machine.text_visible?` は false） |

- **CLUT4**: 色は 0〜15（16 以上は下の 4 ビット）。モード 4 に入ったときのパレットはテキスト面と同じ PC-98 の 16 色（0 黒・1 青・2 赤・3 紫・4 緑・5 水・6 黄・7 白、8〜15 はその明るい色。15 = 白）。
  `Machine.fb_palette(i, r, g, b)` で 0〜15 を変えられる。`get_block` / `put_block` の String は **1 画素 1 バイト（0〜15）**、`blit` の透明色も 0〜15
- 負荷（実機、1 ペアの予算 127µs）: `lowres.rb` で、モード 3 は約 82µs（玉が同じラインに集まると約 112µs）、**モード 4 は約 81µs（同 97µs）**、
  モード 5 は約 61µs、モード 6 は約 59µs。
- **Ruby の速さ**: FB を表示している間は、表示が FB を読むあいだ Ruby が待たされる。空ループでモード 2 は FB なしの約 3 倍、**モード 4 は約 1.3 倍**かかる（§10）。
  モード 1・5・6 は待たない。たくさん計算する絵はモード 4〜6 が向く
- モード 6 では ESC で止めても画面に知らせは出ない（終われば何かキーでファイラーへ戻る）
- **重さの上限**: モード 3 で テキスト + ローレゾ 2 面 + CLUT8 の FB を全部出すと、表示が予算を越える（1 ペア約 150µs）。
  その上 FB を読む間はプログラムが待たされるので、ほとんど進まなくなる。モード 3 では面を減らす（`samples/ruby/testapp/mode3.rb` は BG0 だけで始める）
- 見本: **`samples/ruby/testapp/mode0.rb`〜`mode6.rb`**（以前のファームのテスト用アプリを Ruby にしたもの。同じフォルダの `WTF4CH.mid` をくり返し鳴らし（`m` で一時停止）、画面の下に使えるキーを出す。画面モードごとに 1 つ。`scripts/make_testapp_rb.py` で作る）
- 試験: `samples/ruby/mode456.rb`

### 機械の状態（読むだけ、2026-10-17）
どれも Hash（鍵は記号）を返す。テスト用アプリの Ruby 版（`samples/ruby/testapp/`）のステータス行が使う。

| 書き方 | 中身 |
|---|---|
| `Machine.video_info` | `:timing`（タイミングの名前）`:mode_name` `:fb`（FB の形式）`:line_hz` `:frame_hz`（Float）`:frames` `:underrun` `:fifo_stall` `:recover` `:late_start` `:late_render` `:pair_max`（[µs, µs]） |
| `Machine.sys_info` | `:uptime`（秒）`:mem_free` `:mem_largest`（SRAM の空き）`:usb_devices` `:hubs` `:pads` `:usb_reinit` `:usb_wedged` `:keyboard` `:kbd_vid` `:kbd_pid` `:kbd_leds`（bit0 Num・bit1 Caps・bit2 Scroll）`:mouse` |
| `Machine.mouse` | `:connected` `:buttons`（bit0 左・bit1 右・bit2 中）`:x` `:y` `:wheel`（起動からの累計） |
| `Machine.pad(i)` | i = 0〜3。つながっていなければ nil。`:vid` `:pid` `:hat`（0〜7 = 上から時計回り、8 = 中立）`:buttons`（bit0 = 1 番）`:buttons_n` `:axes`（6 個、無い軸は nil） |
| `Machine.storage(i)` | i = 0〜3（USB ストレージ）。nil か `:vendor` `:product` `:mb` |

- 作るたびに Hash ができる（ゴミになる）。1 フレームに 1 回くらいにする

### ヒープ（2026-11-03）
Ruby のヒープは 64KB から始まり、空きが 32KB を切ると 64KB ずつ増える。空きが 128KB 以上になると、
まるごと空いた 64KB の塊を返す（`Machine.heap_reserve` で指定した最小値までは返さない）。

| 書き方 | 中身 |
|---|---|
| `Machine.heap_reserve(n)` | 最小ヒープを n バイトに上げる（64KB〜4MB）。戻り値は、いま確保してある合計 |
| `Machine.heap_info` | `:min` `:total` `:used` `:free` の Hash |
| `Machine.heap_total` / `Machine.heap_free` / `Machine.heap_min` | 合計・空き・最小値（バイト） |
| 例 | `Machine.heap_reserve(512 * 1024)` で 512KB を必ず確保してから大きなファイルを読む |

### ゲームパッド（2026-10-18）
`Machine.vsync` を呼ぶたびに、4 台ぶんのパッドの状態を写し取る（vsync を使わないなら `Machine.pad_update` で写す）。
「押している」はいまの写し、「押した・離した瞬間」は前の写しとの差で決まる。i はパッドの番号 0〜3、n はボタンの番号 1〜32。

| 書き方 | 中身 |
|---|---|
| `Machine.pad_button?(i, n)` | いま押している |
| `Machine.pad_pressed?(i, n)` / `pad_released?(i, n)` | 前の vsync から、押した / 離した |
| `Machine.pad_dir(i)` | 向き `[dx, dy]`（各 -1 / 0 / 1、**上が -1**）。十字キーと左スティック（半分より倒したとき）のどちらでも |
| `Machine.pad_stick(i, :left / :right [, dead])` | スティック `[x, y]`（-1.0〜1.0、上が -1.0）。中央の遊び dead（既定 0.15）の内は 0.0。右は Z・Rz があればそれ（F310 など）、無ければ Rx・Ry |
| `Machine.pad_axis(i, a [, dead])` | 軸 a（0 X・1 Y・2 Z・3 Rx・4 Ry・5 Rz）を -1.0〜1.0 で。無い軸は 0.0 |
| `Machine::PAD_X` `PAD_A` `PAD_B` `PAD_Y` `PAD_LB` `PAD_RB` `PAD_LT` `PAD_RT` `PAD_BACK` `PAD_START` `PAD_LS` `PAD_RS` | ボタンの番号（1〜12）。**F310 の D モードの並びにそろえてある**（DS3・Switch Pro も記述子と機種の対応表から変換する。`samples/ruby/pad.rb` で確かめる） |
| `Machine::PAD_UP` `PAD_DOWN` `PAD_LEFT` `PAD_RIGHT` | 向き（29〜32 番）。`pad_pressed?(0, Machine::PAD_UP)` のように、ボタンと同じ口で使う |

- つながっていないパッドはどれも「押していない」・`[0, 0]`・0.0。パッドの番号が 0〜3、ボタンが 1〜32 の外なら ArgumentError
- F310 は背面の切り替えを **D** にする（X は XInput で、HID でないので読めない）。つないでも出てこないときは抜き挿しか、リセット
- 見本: `samples/ruby/pad.rb`（押しているもの・スティックの値・押した / 離した瞬間を出す）、試し: `samples/ruby/padcheck.rb`

```ruby
x = 320
loop do
  Machine.vsync
  dx, = Machine.pad_dir(0)
  x += dx * 4
  fire if Machine.pad_pressed?(0, Machine::PAD_A)   # 押した瞬間だけ
end
```

### 画面モード 7: 320x200x8 のビットマップ（2026-10-23）
`Machine.mode = 7` で、320x200・1 画素 1 バイト（256 色のパレットの番号）のビットマップ（VGA のモード 13h と同じ形）。表示は縦横 2 倍の 640x400 で、
テキスト面（**25 行**）を上に重ねる（端末の `puts` も 25 行）。VRAM は SRAM にあるので、いつ書いてもすぐ画面に出る（FB を読む待ちも無い）。
`bm = Machine.bitmap` で描く口（`Machine::Bitmap`）を取る。

| 書き方 | 中身 |
|---|---|
| `bm.ready?` | ビットマップ面が開いている（モード 7 を選んだ） |
| `bm.width` / `bm.height` | 320 / 200 |
| `bm.clear(c = 0)` | 全部を色 c に |
| `bm.pset(x, y, c)` / `bm.pget(x, y)` | 点を描く / 読む（範囲の外は描かない。`pget` は nil） |
| `bm.line(x0, y0, x1, y1, c)` | 線 |
| `bm.rect(x, y, w, h, c)` / `bm.fill_rect(x, y, w, h, c)` | 枠 / 塗りつぶし |
| `bm.palette(i)` | 色の番号 i（0〜255）の色 `[r, g, b]`（各 0〜255） |
| `bm.palette(i, r, g, b)` | 色の番号 i の色を決める（すぐ効く。実際の色は各 5 ビット） |
| `bm.write(offset, s)` | String のバイトをそのまま offset（= y * 320 + x）から書く。書いたバイト数を返す（行や絵をまとめて描く。`pset` よりずっと速い） |
| `bm.read(offset, n)` | offset から n バイトを String で（はみ出た分は短くなる） |

- 既定のパレット: 0〜15 = テキストと同じ PC-98 の 16 色、16〜231 = 6x6x6 の色の立方体、232〜255 = 灰色 24 段
- モード 7 でないとき（ビットマップ面が開いていない）に描くと RuntimeError
- 表示の面に直に描く（2 枚の面は無い）。動くものは消して描き直すか、`write` で行ごとにまとめて書く
- 見本と確かめ: `samples/ruby/mode7.rb`

```ruby
Machine.mode = 7
bm = Machine.bitmap
bm.clear(0)
200.times { |y| bm.write(y * 320, (0...320).map { |x| (x + y) & 255 }.pack("C*")) }   # a pattern, one row at a time
bm.palette(15, 255, 255, 0)            # color 15 = yellow
bm.line(0, 0, 319, 199, 15)
```

### ペンタブレット（2026-10-23）
`Machine.tablet` がいまの様子を Hash（鍵は記号）で返す。つながっていなくても Hash を返し、`:connected` が false。
対応する機種はワコムの Graphire 系（`056A:0010`〜`0016`、Graphire4 = Bamboo。ハブ越しのロースピードでも）。

| 鍵 | 中身 |
|---|---|
| `:connected` / `:ready` | つながっている / タブレットの形に切り替え終わった |
| `:name` | 機種の名前（無ければ nil） |
| `:proximity` | ペンが板の上にある |
| `:tool` | `:pen` / `:eraser` / `:mouse`（離れていれば nil） |
| `:x` `:y` | 位置（0〜`:x_max`、0〜`:y_max`） |
| `:pressure` | 筆圧（0〜`:pressure_max`） |
| `:x_max` `:y_max` `:pressure_max` | それぞれの最大（機種で違う） |
| `:tip` | ペン先が触れている |
| `:button1` `:button2` | ペンの横のボタン |
| `:pad` | 板のボタン（ビットごと） |
| `:wheel` | ホイールの回した量の累計 |

- ペンが板の上にある間は、マウスカーソルもペンの位置へ動く
- 作るたびに Hash ができる（ゴミになる）。1 フレームに 1 回くらいにする
- ホイールの向きと 1 刻みの大きさは確かめ切れていない
- 見本: `samples/ruby/tablet.rb`（C 版は `apps/testapp/tablet.c` -> `tablet.sgx`）
- 【訂正 2026-10-25】前の版で「鍵は文字列」と書いたのは誤り。鍵は記号（`t[:x]`）

```ruby
Machine.mode = 2
fb = Machine.fb
loop do
  Machine.vsync
  t = Machine.tablet
  next unless t[:connected] && t[:proximity] && t[:tip]
  x = t[:x] * 640 / t[:x_max]         # to screen coordinates
  y = t[:y] * 480 / t[:y_max]
  fb.pset(x, y, Machine.rgb(255, 255, 255))
end
```

### GPIO / PIO2 / MIDI（2026-11-11）

C ボードでは GPIO と PIO2、DIN MIDI と USB MIDI ホストが使える（ABI 5.0）。

- `Machine::GPIO.init(pin)` / `set_dir(pin, out)` / `set_pull(pin, pull)` /
  `set_function(pin, func)` / `put(pin, v)` / `get(pin)`。ピンは 0〜47。
  C ボードで空いているのは GP34〜41（GP44/45 はコンソール、42/43 は MIDI、46/47 は ADC）。
  P ボードは GP42/43・GP46/47。
- `Machine::PIO2.available?`。`load([語, ...])` は pioasm（RP2350、絶対ピン番号）の
  16 ビット語を載せ、置いた位置を返す。`sm_claim(sm)` / `sm_unclaim(sm)`（sm = 0〜3）、
  `sm_config(sm, offset, div_int = 1, frac8 = 0, wrap_top = 31, wrap_bottom = 0, fifo_join = 0)`、
  `sm_pins(...)`、`sm_shift(...)`、`sm_clkdiv(...)`、`sm_enable(sm, on)`、
  `sm_put(sm, v)` / `sm_get(sm)`（待たない。空なら nil）、`sm_set_pins(...)` / `sm_set_pindirs(...)`。
  PIO2 は 1 つのプログラムが占有し、終わると SM・命令メモリ・FIFO をファームが片づける。
  使えるピンは 16〜47（GPIOBASE=16）。
- `Machine::MIDI.available?`（DIN）/ `usb?`（USB MIDI ホスト）/ `read([max])` / `write(s)` /
  `set_route(in, out)`（bit0 = DIN、bit1 = USB）。C ボードの DIN は GP42/43。
- `Machine::Music.play(path[, loop])` / `stop` / `pause` / `volume` / `position` / `length` も
  同じ（VGM/VGZ・MP3/OGG/WAV）。
- `Machine::ADC.pins`（C は `[40,41,46,47]`、P は `[40,41]`）、`can_read?(pin)`、`read(pin)`（0〜4095）、
  `start(l = 0, r = 0)`（96kHz の連続取り込み。C の A6/A7 は `start(40, 41)`）、`stop`、`active?`、
  `stats`（Hash: `frames` `dropped` `underruns` `fifo_over` `peak0` `peak1` `dc0` `dc1`）。
  `temperature` は RP2350 内蔵温度センサ（℃、Float）。ADC 使用中は nil。
  ADC は 1 つなので、`start` の間の `read` はエラー（`-16` = EBUSY）。

ピンを使わない PIO2 の自己テスト:

```ruby
pio = Machine::PIO2
pio.sm_claim(0)
off = pio.load([0x80A0, 0xA0C7, 0x8020])   # pull block / mov isr, osr / push block
pio.sm_config(0, off, 1, 0, off + 2, off, 0)
pio.sm_enable(0, true)
pio.sm_put(0, 0x12345678)
v = nil
1000.times { v = pio.sm_get(0); break if v }
pio.sm_enable(0, false)
pio.sm_unclaim(0)
```

### FB・ビットマップ・画像の描画（2026-11-13）

`Machine.fb`（FrameBuffer）、`Machine.bitmap`（モード 7 の Bitmap）、`Machine::Image` は**同じ描画のメソッド**を持つ。
状態と描画のメソッドは自分を返すので、続けて書ける（`fb.pen(c).brush(c2).ellipse(0, 0, 639, 479)`）。

- 状態: `reset_drawing` / `rgb(r, g, b)`（0〜31。CLUT では一番近いパレット番号）/ `pen(c[, w, style])`・`pen_ext(cap, join)` /
  `brush(c[, style])`・`bk(mode[, c])` / `rop2(r)` `fill_rule(r)` `aa(on)` `clip([l, t, r, b])`（引数なしで全面）/
  `matrix(a, b, c, d, e, f)` `concat(...)` `reset_matrix` `get_matrix`
- 線と図形: `move_to` `line_to` `polyline(pts)` `polyline_to` `poly_bezier` `poly_bezier_to` /
  `arc` `arc_to` `pie` `chord(l, t, r, b, xs, ys, xe, ye)` / `angle_arc(x, y, r, start, sweep)` /
  `rectangle` `ellipse(l, t, r, b)` `round_rect(l, t, r, b, ew, eh)` / `polygon(pts)` `poly_polygon([pts, ...])`。
  点は `[x0, y0, x1, y1, ...]` か `[[x0, y0], ...]`。右と下の端は含まない
- パス（Float・行列を通す）: `begin_path` `end_path` `close_path` `path_move_to` `path_line_to` `path_quad_to`
  `path_cubic_to` `path_arc(cx, cy, r, a0, a1)` / `fill_path` `stroke_path` `fill_stroke_path`
- 転送: `bitblt(dx, dy, w, h, src[, sx, sy, rop, key])` / `stretch_blt(dx, dy, dw, dh, src, sx, sy, sw, sh[, rop, key])`
  （負の幅・高さで反転）/ `draw_dib(dx, dy, dw, dh, bits, fmt, w, h[, palette, rop])`
- 文字: `font([face, height, weight, flags, escapement])`（`FONT_ROM` / `FONT_8X8`、`FW_*`、`FF_*`、0 / 900 / 1800 / 2700）/
  `text_color(c[, align, extra])` `text_out(x, y, s)` `ext_text_out(x, y, opt, rect, s[, dx])` /
  `draw_text(s, l, t, r, b[, flags])`（`DT_CALCRECT` で `[l, t, r, b]` を返す）`text_extent(s)`
- 定数: `PS_*` `CAP_*` `JOIN_*` `BS_*` `BK_*` `R2_*` `FILL_NONZERO` / `FILL_EVENODD` `SRCCOPY`〜`WHITENESS` `DIB_*` `TA_*` `ETO_*` `DT_*`
- `Machine::Image`: `Machine::Image.new(w, h[, fmt])` / `.load(path[, fmt])`、`width` `height` `format` `pset` `pget`
  `clear([c])` `free`。PNG・JPEG・GIF（1 枚目）・TIFF。`fmt` は `FMT_RGB555` / `FMT_CLUT8`
- 見本: `samples/ruby/gfx.rb`（実機で `gfx: all ok`）、デモ `samples/ruby/gfxdemo.rb`

## 8. 乱数と時間

- `rand` -> 0.0 以上 1.0 未満、`rand(n)`（整数）-> 0 以上 n 未満の整数、`rand(x)`（小数）-> 0.0 以上 x 未満。`Random.new(seed).rand(n)` もある
- `srand(n)` で種を決める（同じ種なら同じ並び）
- `Machine.ms` で経過時間を測る（`t0 = Machine.ms` ... `Machine.ms - t0`）
- **`Time`**（2026-10-16、日本時間 +09:00 だけ）: `Time.now` `Time.at(秒 [, µs])` `Time.local(年, 月, 日, 時, 分, 秒)`（`mktime`、`Time.new(...)` も）、
  `year` `month` / `mon` `day` / `mday` `hour` `min` `sec` `usec` `wday` `yday` `to_i` `to_f` `to_a` `utc_offset`（32400）`zone`（"JST"）、
  `+` `-`（時刻どうしの差は秒の Float）`<=>` `==`・Comparable、`to_s`（"2026-10-16 10:02:04 +0900"）`inspect` `strftime`
  （`%Y %m %d %e %j %H %I %M %S %L %N %p %a %A %b %B %u %w %y %z %Z %s %F %T %D %R %c %%`、`%-d` で詰める）
  - 時計を合わせていなければ `Time.now` は 2026-10-04 12:00 + 起動からの時間。`Machine.clock_set?` で分かる
  - 2038-01-19 を越える日時は扱えない（整数が 32 ビットのため RangeError）。`utc` `gmtime` `Time.gm` は無い

## 9. 音: Sound（2026-10-18）

PT8211 の音源を、**ポートを直接**（ノートオン・オフ・ADSR）と、**曲データ（SMF = 標準 MIDI ファイル、SGT = SGNO TRACKER の曲）の再生**の 2 通りで鳴らす。
初めて `Sound` のメソッドを呼んだときに音が出るようになり、プログラムが終わる（ESC で止めたときも）と全部止まって消音される。
**値は実機で確かめた**（ホストの実行器には Sound が無い）。

### ポート

| 書き方 | 中身 |
|---|---|
| `Sound.channels` | ポートの数（いまは **4**。`ch` は 0〜3） |
| `Sound.note_on(ch, note, vel = 100)` | 音を出す。`note` は MIDI のノート番号 0〜127（60 = 真ん中のド、69 = A4 = 440Hz）、`vel` 1〜127 |
| `Sound.note_off(ch)` | 離す（リリースに入る） |
| `Sound.adsr(ch, a, d, s, r)` | エンベロープ。各 0〜127。形は SID（C64 の音源チップ）: アタック 2ms〜8 秒、ディケイ・リリース 6ms〜24 秒、`s` はサステインのレベル（127 = 最大） |
| `Sound.volume(ch, v)` / `Sound.expression(ch, v)` / `Sound.pan(ch, v)` | MIDI の CC7（既定 100）・CC11（既定 127）・CC10（既定 64）。0〜127。パンは 0 = 左、64 = 中央、127 = 右 |
| `Sound.master(v)` | 全体の音量 0〜127（既定 127） |
| `Sound.wave(ch, w)` | 波形: `Sound::SINE` `TRIANGLE` `SAW` `SQUARE` `PULSE25` `ORGAN` `NOISE` |
| `Sound.program(ch, gm)` | GM の音色番号 0〜127（48 = Strings など）を、こちらの波形と ADSR に置き換えて設定する |
| `Sound.bend(ch, b, range = 2)` | ピッチベンド -8192〜8191、`range` は半音で |
| `Sound.freq(ch, hz)` | 音程を Hz で直に（Float でよい） |
| `Sound.all_off` | 全ポートを離す |
| `Sound.level(ch)` / `Sound.phase(ch)` | エンベロープのいまのレベル（0〜255）と段（`:idle` `:attack` `:decay` `:sustain` `:release`） |
| `Sound.mode(ch)` / `Sound.set_mode(ch, m)` | ポートのモード `Sound::WT`（ウェーブテーブル）/ `STREAM` / `NOISE_MODE`（RNG のノイズ）/ `PCM`（下の `pcm` の標本をループ） |
| `Sound.pcm(ch, data)` | `PCM` 用の標本。符号付き 8 ビットの String を 1〜32 バイト（32 未満は 0 で埋める）。音程は `note_on` のノートで決まる（2026-10-30） |

- `Sound::NOISE_MODE` は 4ch 目のドラム用（2026-10-29）。RNG から起動時に作った 32 サンプルの波形を、WT と同じ音程・音量・ADSR で鳴らす。
  `Sound.set_mode(ch, Sound::NOISE_MODE)` にすると波形は自動で `Sound::NOISE` になる（`Sound.wave` は不要）。ほかの波形に戻すときは
  `Sound.set_mode(ch, Sound::WT)` にしてから `Sound.wave(ch, ...)` を呼ぶ。ノイズモードの間は `Sound.wave` の値は使われない

- `Sound::PCM` は 8 ビットの 32 サンプルをループする Paula 風（2026-10-30）。`Sound.pcm(ch, data)` で標本を渡し、`Sound.set_mode(ch, Sound::PCM)` にしてから
  `note_on` する。音量・ADSR・パンは WT と同じ。32 サンプルなので、高い音ほど 1 周期が短くなる（`note_on` のノートで PIO の分周が決まる）

- 範囲の外の値は ArgumentError（`no such sound channel 4 (0..3)`、`note 128 is out of range (0..127)` など）
- 実機の値: `adsr(0, 0, 40, 90, 50)` で鳴らして 0.1 秒後は `:sustain`・レベル 180、離して 0.5 秒後は `:idle`・0

### 曲データ（SMF / SGT）

| 書き方 | 中身 |
|---|---|
| `Sound.play(song, loop = false)` | BGM を始める（鳴っていれば替える）。`song` はファイルのパスか、`"MThd"`（SMF）／`"SGTRK"`（SGT）で始まる String（中身そのもの） |
| `Sound.stop` / `Sound.pause` / `Sound.resume` | 止める・一時停止（鳴っている音は離す）・再開 |
| `Sound.playing?` / `Sound.paused?` | 進んでいるか（一時停止の間も true）・一時停止しているか |
| `Sound.position` / `Sound.length` | 頭からの時間・曲の長さ（ms。長さはテンポの変化も入れた値） |
| `Sound.tempo(percent)` | 速さ 25〜400（100 = そのまま） |
| `Sound.sfx(song, ch)` | 効果音のフレーズを、ポート `ch` を占有して鳴らす（BGM はその間そのポートを使わない。同時に 2 本まで） |
| `Sound.sfx_stop(ch)` / `Sound.sfx_playing?(ch)` | |
| `Sound.reserve(ch, true/false)` | ポートを BGM に使わせない（自分で `note_on` するポートに）。`true` のとき、そのポートで BGM が鳴っていれば、いま止めて返す。`false` で返すときは WT モードに戻し、BGM の次の音で波形・ADSR を送り直す（ノイズの効果音の音色が残らない）。効果音の間だけ借りて、終わったら `false` で返せる（2026-10-29） |

- BGM は MIDI の 16 チャンネルを空いているポートへ割り当てる（4 つより多い音が重なると、いちばん古い音を止める）
- **SGT は 4 トラックを 4 ポートで鳴らす**（2026-10-29、ABI 1.5）。音色 0〜8（WT + NOISE）と効果 A/C/D/F/H/P/Q を扱う。
  SGT の再生中は `Sound.sfx`（効果音）は使えない
- 音色は GM のプログラムチェンジを置き換える。**SMF の MIDI チャンネル 10（ドラム）はノイズの短い一発で鳴る**（2026-10-29）。パン（CC10）も左右のゲインに効く（2026-10-30）
- 扱う出来事: ノートオン・オフ、CC7・CC11・CC64（サステイン）・CC120・CC121・CC123、ピッチベンドとその幅（RPN 0）、プログラムチェンジ、テンポ
- 曲の再生は裏で進む（プログラムが計算していても止まらない）。プログラムが終わると止まる
- 見本: `samples/ruby/sound.rb`（前半はポート、後半は `samples/sound/WTF4CH.mid`（4 チャンネル・45 秒）。Space で一時停止、`+` / `-` で速さ、`e` で効果音）。
  SGT は `samples/ruby/sound_sgt.rb`（`samples/sound/NOISE_ROCK.SGT`、ノイズ・ドラムのロック）。

```ruby
Sound.wave(0, Sound::SQUARE)
Sound.adsr(0, 0, 40, 90, 50)
Sound.note_on(0, 69, 110)      # A4
Machine.vsync(30)
Sound.note_off(0)

Sound.play("WTF4CH.mid")
while Sound.playing?
  break if Machine.key == 113   # q
  Machine.vsync
end
Sound.stop
```

## 10. 速さの目安（実機で測った値）

2026-11-01 に、いまのファームで測り直した。項目は `samples/ruby/bench.rb`（モード 1・2・4 で同じことをする）。Python（`samples/python/bench.py`）と
BASIC（`samples/basic/bench.bas`）でも同じ項目を測り、右に並べた。モード 4 の色は 0〜15 の番号（1 画素 4 ビット）なので、同じ絵でも書くバイト数が少ない。

| 内容 | モード 1（FB なし） | モード 2（RGB555 の FB を表示） | モード 4（CLUT4 の FB を表示） | （参考）Python / BASIC のモード 2 |
|---|---|---|---|---|
| 空の `while`（`i += 1`）10 万回 | 0.11 秒 | 0.36 秒 | 0.14 秒 | 0.51 / 1.63 秒 |
| `fb.pset` 1 万回（`10000.times` のブロックの中で） | - | 0.87 秒（1 点 約 0.09ms） | 0.33 秒 | 0.33 / 1.31 秒 |
| `fb.fill_rect(x, y, 64, 48, c)` 1000 回 | - | 0.51 秒（1 回 約 0.5ms） | 0.12 秒 | 0.53 / 0.60 秒 |
| `fb.line(0, 0, 639, y, c)`（画面の端から端）1000 回 | - | 0.37 秒 | 0.33 秒 | 0.31 / 0.39 秒 |
| `fb.fill_triangle`（64x48 の直角三角形）1000 回 | - | 0.73 秒 | 0.25 秒 | 0.56 / 0.80 秒 |
| `fb.fill_triangle`（画面の半分、約 15 万画素）100 回 | - | 2.2 秒（1 回 約 22ms） | 0.32 秒 | 2.5 / 2.1 秒 |
| `fb.triangle`（大きな外枠）1000 回 | - | 1.0 秒 | 0.81 秒 | 0.92 / 1.0 秒 |
| `fb.blit` 64x48 1000 回（透明色なし / あり） | - | 3.9 秒 / 3.3 秒（1 回 約 4ms） | 1.3 秒 / 2.1 秒 | 3.7 / 4.2 秒（なし） |
| `fb.get_block` / `fb.put_block` 64x48 1000 回 | - | 3.6 秒 / 1.3 秒 | 1.1 秒 / 1.5 秒 | 4.2 / 3.0 秒（get） |
| `fb.clear`（640x480 全体）100 回 | - | 3.3 秒（1 回 約 33ms） | 0.37 秒（1 回 約 4ms） | 3.7 / 3.7 秒 |

| プログラム（FB はモード 2） | Ruby | Python | BASIC |
|---|---|---|---|
| `MANDEL.RB`（80x24 の文字のマンデルブロ、モード 1） | 0.43 秒 | 0.74 秒 | 1.11 秒 |
| `HAT.RB`（`Math.sqrt`・`cos` 2 回の点を 4.4 万個、点は約 1 万） | 10.5 秒 | 12.0〜15.1 秒 | 15.1 秒 |
| `M640.RB`（640x480、最大 64 回の繰り返し、上下対称） | 50.6 秒 | 94.0 秒 | 69.3 秒 |

- **FB を表示している間は遅い**: 空ループでモード 2 は約 3 倍、モード 4 は約 1.3 倍。表示の乱れを防ぐため、表示が FB を読む間は Ruby を待たせているため。
  たくさん計算する絵は**モード 4**（16 色）か、FB を出さないモードで計算してから見せる
- 画素を 1 つずつ `pset` するより、`fill_rect` や `line` でまとめて描く方がずっと速い（`fill_rect` 1 回で 3000 画素）
- `blit` は塗りより遅い（元を PSRAM から読むため）。全面を毎フレーム写すような使い方はできない。動く所だけ写す
- 全面の `clear` はモード 2 で 1 回 33ms（2 フレーム）。アニメーションで毎フレーム全面を消さず、動いた所だけ消す
- 重い計算をするときは途中で `puts` で進み具合を出すと、止まっていないことが分かる。プログラムは自動で画面・USB に譲るので、
  `vsync` を呼ばなくても固まらない
- 描く命令の重さは 3 つの言語でほぼ同じ（ファームの同じ処理）。違いは式の計算の速さ（空ループで Ruby < Python < BASIC）

## 11. 制限のまとめ（書くときの注意）

1. 整数は 32 ビットの Fixnum。21 億を超える計算は Bigint に昇格する（メモリを使う。`2 ** 100` も可）。速さ優先なら Float を使う（`2.0 ** 40`）
2. `require` / `load` / `require_relative` がある（`$LOAD_PATH` は既定で `.` と `S:/SystemFiles/ruby`。見つからなければ `LoadError`）。`Time` は日本時間だけ。`$!` はいつも nil（`rescue => e` で受ける）
3. 入力は `gets`（行）と `Machine.key`（1 つずつ）。ESC はプログラムに届かない（実行を止める）。日本語の入力は無い
4. 画面モードは 0〜7（3〜6 でローレゾ面、7 で 320x200x8 のビットマップ）。USB 機器を直接扱う口はまだ無い。モード 6 ではテキスト面が出ない
5. 音はポート 4 つ。SGT（4 トラック）・ノイズ（`Sound::NOISE_MODE`）・SMF のチャンネル 10 のドラム・パン（CC10）・PCM（32 サンプル）が使える。ローレゾのオブジェクトは不透明のみ
6. 1 つのプログラムが使えるメモリは 1MB。大きな配列（10 万要素など）は避ける。640x480 の画素を配列に持つと足りない

## 12. ひな形

```ruby
# Title: what this program does (ASCII only)
Machine.mode = 2
Machine.text_visible = false        # show only the picture
fb = Machine.fb
fb.clear
t0 = Machine.ms
# ... draw ...
fb.fill_rect(100, 100, 200, 100, Machine.rgb(255, 128, 0))
fb.line(0, 0, 639, 479, Machine.rgb(255, 255, 255))
Machine.text_visible = true
printf("done in %.2f s\n", (Machine.ms - t0) / 1000.0)
```

アニメーション:

```ruby
Machine.mode = 2
Machine.text_visible = false
fb = Machine.fb
fb.clear
x = 0
black = 0
c = Machine.rgb(0, 255, 255)
t0 = Machine.ms
while Machine.ms - t0 < 10000           # 10 seconds
  fb.fill_rect(x, 200, 40, 40, black)   # erase the old one
  x = (x + 4) % 600
  fb.fill_rect(x, 200, 40, 40, c)       # draw the new one
  Machine.vsync
end
```

ファイル:

```ruby
File.open("log.txt", "w") do |f|
  10.times { |i| f.puts "line #{i}" }
end                                     # written back here
p File.readlines("log.txt").size        # => 10
begin
  File.read("missing.txt")
rescue Errno::ENOENT => e
  puts "not found: #{e.message}"
end
```

## 13. AI に書かせるときの指示（そのまま渡せる要約）

- 処理系は mruby 4.0（CRuby とほぼ同じ書き方が使える）。`require` / `load` / `require_relative` がある（正規表現は `Regexp.new`、`Set` は `Set.new(a)`、`Data` は `Data.define`、`JSON` は `JSON.parse` / `JSON.generate`）。`$!` は nil なので例外は `rescue => e` で受ける
- `Time` は日本時間だけ。ファイルの日時は `File.mtime(path)`、属性は `File.stat(path)`。読み出し専用は書く・消す・名前の変更が `Errno::EACCES`
- 整数は 32 ビットの Fixnum で、あふれると Bigint に昇格。速さ優先なら Float で
- 画面は `Machine.mode = 2` にしてから `Machine.fb` に描く。色は `Machine.rgb(r, g, b)`。座標は 640x480。ページは 4 枚（`write_page` に描き `display_page` で見せる）
- 画面モード 3: `Machine.mode = 3` で FB は CLUT8（色は 0〜255 の番号、`Machine.fb_palette(i, r, g, b)`）、`lr = Machine.lowres` で 320x240 のタイルの BG 2 面とオブジェクト 128 個（`lr.pattern` `lr.map`（タイル 0〜1023・パレット 0〜15）`lr.obj` `lr.obj_move` `lr.scroll`）。オブジェクトは同じラインに 4 個くらいまで。モード 4 は FB が CLUT4（色 0〜15）で負荷が軽い、5 は FB なし、6 はローレゾだけ（テキストが出ない）
- 画面モード 7: `Machine.mode = 7`、`bm = Machine.bitmap` に 320x200 で描く（色は 0〜255 の番号、`bm.palette(i, r, g, b)`）。`pset` `line` `rect` `fill_rect` `clear`、まとめて書くのは `bm.write(y * 320 + x, str)`。テキストは 25 行
- ペンタブレット: `t = Machine.tablet` -> `t[:x]` `t[:y]`（0〜`t[:x_max]` など）・`t[:pressure]`・`t[:tip]`（触れている）・`t[:proximity]`（板の上）・`t[:tool]`（`:pen` / `:eraser`）
- 文字の色・飾り: `puts "\e[1;31m赤い太字\e[0m"` のような ANSI のエスケープ列か、`Machine.text_attr = Machine.tattr(fg, bg, Machine::TEXT_BOLD)`。位置は `Machine.locate(x, y)`、決まった所に置くのは `Machine.text_put(x, y, str, attr)`（28 行 x 80 桁）
- 描画: `pset` `pget` `line` `rect` `fill_rect` `triangle` `fill_triangle` `clear`。ブロック転送は `blit(sx, sy, w, h, dx, dy, page, key)`（ページ間も、透明色も）と `get_block` / `put_block`（String）
- ファイルは CRuby と同じ `File` / `Dir` / `IO`（パスは `A:/...` か相対）。失敗は `Errno::*`
- キー入力: 行は `gets`（Ctrl-D で nil）、1 つずつは `Machine.key`（無ければ nil）・`Machine.wait_key`、押している間は `Machine.key_down?`。ESC は使えない（実行を止める）
- パッドの振動（DS3）: `Machine.pad_rumble(0, weak, strong)`（weak 0/1、strong 0..255、対応していなければ false）
- パッド: `Machine.vsync` のあと `Machine.pad_pressed?(0, Machine::PAD_A)`（押した瞬間）・`pad_button?`（押している）・`pad_dir(0)`（[dx, dy]、上が -1）・`pad_stick(0, :left)`（-1.0〜1.0）
- 音: `Sound.note_on(ch, note, vel)` / `note_off(ch)` / `adsr(ch, a, d, s, r)`（各 0〜127、ch は 0〜3）、曲は `Sound.play("x.mid")`（SMF）や `Sound.play("x.sgt")`（SGT）・`Sound.playing?`・`Sound.stop`。ノイズは `Sound.set_mode(ch, Sound::NOISE_MODE)`、パンは `Sound.pan(ch, v)`、PCM は `Sound.pcm(ch, data)` + `Sound.set_mode(ch, Sound::PCM)`。SMF のチャンネル 10 のドラムも鳴る
- 経過時間は `Machine.ms`、日時は `Time.now`、乱数は `rand` / `srand`、待ちは `Machine.vsync` / `sleep`
- ソースは ASCII だけで書く（コメントも英語）
- 実機は遅い（FB 表示中は空ループ 10 万回で約 0.36 秒、`pset` 1 回約 0.09ms、全面の `clear` 1 回 33ms）。画素ごとの処理は 640x480 全面で数十秒〜数分かかることを見込む

## 付録: 確かめに使ったもの

- ホストの実行器 `build_mruby/host_mruby run file.rb`（`scripts/test_mruby.py` が組む。実機と同じ mruby と同じ定義（整数 32 ビット）。FB は環境変数 `RBM_PPM` で画像に書き出せる）
- 試験 `scripts/test_mruby.py`、サンプル `samples/ruby/`（`fs_compat.rb` はファイル操作を CRuby と比べる、`machine.rb` は Machine の全メソッドの確かめ、
  `fileio.rb` はファイル操作、`gems.rb`・`evaltest.rb` は 2026-10-25 に足した gem、`gems2.rb` は 2026-11-02 に足した Data / JSON / Rational / Complex / CMath / Lazy / Chain、`require.rb` は require / load、`system.rb` / `exec.rb` は `system` / `exec`、`mode7.rb` は画面モード 7、`defrag.rb` は S: のデフラグ、`enfrag.rb` は S: をわざと断片化するエンフラグ（どちらも実機だけ）、`tablet.rb` はペンタブレット（実機だけ）、`demo.rb` は約 1 分の描画のデモ、`mandel640.rb`・`hat.rb`、速さの表は `bench.rb`、音は `sound.rb`（SMF）と `sound_sgt.rb`（SGT。どちらも実機だけ））
- 以前の mruby/c 版の仕様は、この文書の 2026-10-11 の版（git の履歴）にある
- 3 つの言語の Machine の突き合わせ: `samples/machine_api/api.rb`・`api.py`・`api.bas`（実機で一致。2026-11-11 に GPIO/PIO2/MIDI を追加）、対応表 `docs/machine_api.md`
