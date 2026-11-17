# Ruby の Machine クラスと FrameBuffer（2026-10-11）

Ruby（mruby/c、`SPEC_mruby.md`）から画面モード・FB とテキスト面の表示を変え、FB（RGB555、640x480）に描く。

## API

```ruby
Machine.mode                 # いまの画面モード（Integer）
Machine.mode = 2             # 0（表示なし）/ 1（テキスト）/ 2（テキスト + RGB555 の FB）。ほかは ArgumentError
Machine.fb_visible?          # FB を表示しているか
Machine.fb_visible = false   # FB を隠す・見せる（モード2 にすると見せる）
Machine.text_visible?        # テキスト面を表示しているか
Machine.text_visible = false # テキスト面（Ruby の出力の端末・状態の行）を隠す・見せる
Machine.vsync(n = 1)         # n フレーム待つ（その間に表示・キー・USB が進む）
Machine.rgb(r, g, b)         # 0..255 の各色から画素の値（Integer）。範囲の外は丸める
Machine.fb                   # Machine::FrameBuffer（Machine::FrameBuffer.new と同じ）
Machine.ms                   # 起動からのミリ秒（mruby/c には Time が無いので。2026-10-11）
rand / rand(n) / rand(x)     # 0.0〜1.0 / 0〜n-1 の整数 / 0.0〜x（xorshift32。mruby/c には無いので足した）
srand(n)                     # 種を決める（始めは時刻から）
Machine.pages                # FB のページ数（4）
Machine.display_page = p     # 表示するページ（0〜3。アプリ時間に切り替える = フレームの境目。終わるまで待つ）
Machine.write_page = p       # FrameBuffer が描くページ（0〜3）。終わったら実行前のページへ戻す

fb = Machine.fb
fb.width / fb.height         # 640 / 480
fb.clear(color = 0)
fb.pset(x, y, color)
fb.pget(x, y)                # 画素の値。範囲の外は nil
fb.line(x0, y0, x1, y1, color)
fb.rect(x, y, w, h, color)       # 外枠
fb.fill_rect(x, y, w, h, color)  # 塗りつぶし
# 2026-10-16
fb.triangle(x0, y0, x1, y1, x2, y2, color)       # 三角形の外枠
fb.fill_triangle(x0, y0, x1, y1, x2, y2, color)  # 塗りつぶした三角形（走査線ごとに横線。最後に外枠も描いて、line の辺と画素を揃える）
fb.blit(sx, sy, w, h, dx, dy [, page [, key]])   # page（省けば書き込みページ）の矩形を書き込みページへ。重なってよい（memmove の向き）。key の色は写さない
fb.get_block(x, y, w, h)          # -> String（w*h*2 バイト、1 画素は下位バイトが先。String は 2 バイトに揃っていないのでバイトで扱う）
fb.put_block(x, y, w, h, s [, key])
```

- 座標は Integer か Float（切り捨て）。範囲の外は描かない（線・矩形は切り取る）。w・h が 0 以下なら何も描かない
- 描く先は**いまの書き込みページ**（`app_fb`、ファイラーの F7 で選ぶもの）。表示ページと同じならすぐ見える
- 実行が終わると画面モードと FB の表示は実行前に戻る。描いた中身は FB に残る（ファイラーの Shift+F2 で消せる）

## 作り

- `src/ruby/rbmachine.c`（フラッシュ）: Ruby のクラスと描画。下回りは `src/ruby/rbmach.h` の `rbm_*`
  - 実機: `src/ruby/rbrun.c`。画面モード・表示の切り替えは**アプリ時間に頼んで、片付くまで待つ**（`machine_request`、上限 2 秒）。
    モードを切り替えたフレームは表示経路を作り直すので、ほかに何もしない（積み残しの作法）。テストパターンは描かない（`app_fb_keep`）
  - ホスト試験: `scripts/host_ruby/rbmach_host.c`（FB は配列。環境変数 `RBM_PPM` で PPM に書き出す）
- 描画は書き込みページへキャッシュを通らない窓（0x15...）で直接書く（表示の取得もその窓から読むので、書き戻しは要らない）
- 描画の部品は `src/ruby/rbdraw.h`（mruby 版・mruby/c 版で共通。三角形とブロック転送は mruby 版だけがメソッドにしている）
- **長い描画は行ごとに `rbm_poll()`**（2026-10-16）: 前に譲ってから 14ms たっていればアプリのループへ 1 周譲る。全面の `blit` は 1 回 約 0.28 秒で、
  譲らないとループが止まった（`[wdt] slow loop: 250000 us`、ウォッチドッグは 500ms）。ESC で止めるのは今までどおり区切りの口で
- `get_block` は作った大きさを数えて 256KB ごとに `mrb_full_gc`。mruby の GC は物の数で回るので、6KB の String を 1000 回作ると数が増えないまま
  ヒープ（1MB）が尽きた（`Out of memory`）
  - 【訂正 2026-10-16】mruby の手直し（`tools/mruby/patches/0003`）で、GC が確保したバイト数でも回るようにしたので、`get_block` だけの数え方は外した（`SPEC_mruby.md`）

## FB を表示したまま Ruby を走らせる（2026-10-11 の測定）

FB を表示したまま Ruby を走らせると、Ruby の VM（フラッシュのコード）とヒープ（PSRAM のキャッシュの窓）が QMI を使い、
表示の取得（PSRAM -> リング、DMA）と取り合って表示が乱れた（`MANDEL.RB` 約 4 秒で underrun +52,672・fifo_stall +66,719・作り直し +8）。
FB からラインバッファへの転送は、もとからキャッシュを通らない窓（`fb_base` = 0x1576A000）から読んでいる。

対策（`render_park_on`、Ruby を走らせている間だけ）:
1. **core1 がペアを描く間は core0 を待たせる**（`render.c`）。core1 が doorbell を鳴らし、core0 は SRAM の割り込み（`park_isr`、優先度 0xD0 =
   描画 0xC0 より低い。描画中の core0 は Ruby を走らせていないので止めなくてよい）で取得が終わるまで待つ（上限 0.5ms）。
   どちらのコアも、次のペアの先読みの転送が終わってからペアを終える。core0 の偶数ペアは割り込みの中なので、もとから Ruby は止まっている
2. **実行の前後の大きな PSRAM の操作も含める**（スタックを塗る・キャッシュの書き戻し）
3. **Ruby のスタックを PSP にする**（`call_on_stack`）。割り込みは MSP（SRAM）で動く。以前は MSP ごと PSRAM に移していて、
   ライン割り込みなども PSRAM のスタックで動いていた

| | 対策なし | 1 | 1 + 2 | 1 + 2 + 3 |
|---|---|---|---|---|
| underrun | +52,672 | +2,189 | 0 | **0** |
| fifo_stall | +66,719 | +2,999 | +471 | **+4** |
| 作り直し | +8 | +2 | 0 | **0** |

代わりに、FB を表示している間の Ruby は約 2 倍遅くなる（`MANDEL.RB` 2.7 秒のうち 1.6 秒は待っている。モード1 では待たない）。
CLUT8 / CLUT4 でも測った（対策なしで underrun 0・fifo_stall +3,959 / +1,812）が、RGB555 のままこの対策を採った（ユーザー判断）。

## サンプル（`samples/ruby/`）

- `machine.rb`: 全メソッドを試し、`pget` で画素を確かめて ok / NG を出す（最後に all ok）。最後に小さな絵を描く
- `mandel640.rb`: 640x480 のマンデルブロ集合（上下対称なので上半分を計算して写す。主カージオイドと周期 2 の円は計算しない）
- `hat.rb`: メキシカンハット（z = 100 cos r - 30 cos 3r。手前から描き、列ごとの最も高い所より上だけ描く隠線消去）

ホスト試験 `scripts/test_ruby.py` が 3 つとも走らせる（machine.rb は all ok、FB を PPM に書き出す）。
- `flip.rb`: ダブルバッファ（裏のページに箱 12 個を描いて表示を切り替える、15 秒）。実機で 152 フレーム（約 10 fps）、underrun 0・fifo_stall 0
- `demo.rb`: 約 1 分の描画のデモ（タイトル・放射する線・跳ね返る線の残像・矩形のトンネル・スピログラフ・プラズマ・花火）。実機で 50.5 秒、
  表示は underrun 0・fifo_stall +1

書く人・AI 向けの仕様書は `docs/sgnano_ruby_guide.pdf`（元は `docs/sgnano_ruby_guide.md`。使える・使えないメソッドは実機と同じ処理系で値まで確かめた）。

## テキストの属性と位置（2026-10-16）
- 端末（`src/ruby/rbterm.c`）を、行の UTF-8 の文字列から**テキスト面の上 28 行の写し**（1 セル = 字のコード 16 ビット + 属性 32 ビット、PSRAM に約 13KB）に作り直した。
  カーソル（cx, cy）といまの属性で書き、描くのはアプリ時間に変わった行のセルをそのまま置く（`text_put_raw`、text.c に足した）
- ANSI のエスケープ列: SGR（0・1/22・4/24・5/25・7/27・9/29・53/55・30〜37/39・40〜47/49・90〜97・100〜107）、`H`/`f`・`A`〜`D`・`G`、`J`（0/1/2）、`K`（0/1/2）。
  ANSI の色の並び（黒・赤・緑・黄・青・紫・水・白）は PC-98 の並び（黒・青・赤・紫・緑・水・黄・白）へ写す。`\r` は行の頭へ、`\b` は 1 つ左へ
- 倍角は put_doubled と同じ並びの印をセルに付ける（全角の右側 `TATTR_RIGHT`・横倍角の右半分 `TATTR_DW_RIGHT`・縦倍角の下半分 `TATTR_DH_LOWER`）。
  縦倍角の字のある行は、改行で 2 行進む。いちばん下の行で縦倍角を書くと先に 1 行流す
- `Machine.text_attr` / `text_attr=` / `tattr` / `text_color` / `locate` / `cursor` / `text_put` / `text_attr_at` / `text_get` / `text_clear` / `text_cols` / `text_rows`、定数 `TEXT_*`（`rbmachine_mrb.c`。mruby 版だけ）。
  `text_attr_at(x, y, attr)` はセルの字をそのままに属性だけ書き換え、倍角の印と位置の印は残す（2026-10-29）。
  線の印は渡した値に置き換わるので、残したい線も `attr` に含める
- 空いたセルは `TATTR_CLEAR`（地も透過）。以前と同じく、字の無い所は FB が見える
- ホスト試験: rbterm.c をそのまま組み（テキスト面・アプリ時間の口は `scripts/host_mruby/text_host.c` の代わり、字の幅は U+1100 以上を全角とみなす）、
  ホストの出力も端末へ流す。`samples/ruby/textattr.rb` が `text_get` でセルを確かめる（37 項目。2026-10-29 に `text_attr_at` の試験を足した）
- 実機: 2026-10-27 時点の textattr.rb（29 項目）が all ok（174ms）。見本 textdemo.rb を表示中のテキスト面のセルを SWD で読み、色・反転・横倍角（右半分の印）・縦倍角（下半分の印）・帯の地の色が
  そのとおりに置かれていることを確かめた。65 秒の表示で underrun 0。SRAM +20 B
- 実機（2026-10-29）: 外周罫線と `text_attr_at` を入れた `samples/ruby/textattr.rb`（37 項目）が
  **all ok**（217ms、ヒープ 112,284 B、スタック 6,108 B）。`blit.rb` も all ok（434ms）

## 画面モード 3: CLUT8 の FB とローレゾ（2026-10-17）
- `Machine.mode = 3`（`SCREEN_TEXT_LR_C8`）。FrameBuffer のメソッドは、呼んだときの FB の形式（`rbm_fb_bytes()`: モード 3 は 1）で描く。描画の部品は
  `rbdraw_px.h` を画素の型で 2 回取り込む（16 ビットは名前そのまま、8 ビットは `put8` `hline8` ... `put_block8`）
- CLUT8 のパレット: `Machine.fb_palette`（`vga_set_palette`、1 語を書くだけなので表示中でもよい）。モード 3 に入ったとき既定の 256 色（6x6x6 の立方体 + 灰色 40 段）
- `Machine.lowres`（`Machine::LowRes`）: パレット・パターン・マップは SRAM の表（`lr_palette` `lr_pattern` `lr_map`）へ直接書く。
  オブジェクト（OAM）とスクロール・表示の切り替えは影（実行の状態、PSRAM）に書き、アプリ時間（`rb_app_time` -> `lr_apply`）に `lr_oam` / `lr_ctrl` へ写す
- ローレゾ面は、空きが LAN の受け場（約 10KB）で 35KB と 55KB に分かれることがある。Ruby がモード 3〜6 に入るとき、
  パターン 128 -> 96 -> 64 -> 32KB、各段でパレット 64 -> 32 -> 16 -> 8 -> 5 本を試し、入る組み合わせで先に開く
  （2026-10-30。実機の LAN ありでは **32KB・32 パレット = 512 タイル**。テスト用アプリ・jumps・raster は 5〜13 本しか使わない）。
  終わるとき（ファイラーへ戻る）に、Ruby が開いたなら OAM を消して閉じる（SRAM を返す）
- 負荷（実機、1 ペアの予算 127µs）: Ruby が vsync だけ回すとき、全部の層を出して 80/79µs、BG1 を消して 71、オブジェクトも消して 61。動かすと、
  BG 2 面をスクロール + 同じラインにオブジェクト 4 個で約 84µs、6〜8 個では 100〜162µs で予算を越え、`fifo_stall` が増える。Ruby の計算そのもの（玉の物理）は効かない
- 一度、予算を越える場面（オブジェクト 6〜8 個）を続けて走らせたあと、見本をキーで止めたときに underrun 182・表示経路の作り直し 1 回を見た。続けて 2 回、同じ手順では 0
- ホスト試験: `samples/ruby/mode3.rb`（CLUT8 の描画を pget で、ローレゾを map_get・obj_get で、既定のパレットも）。ホストはローレゾを絵にしない（FB は CLUT8 をパレットで PPM に）

## 機械の状態とテスト用アプリの Ruby 版（2026-10-17）
- `Machine.video_info` / `sys_info` / `mouse` / `pad(i)` / `storage(i)`（Hash を返す、読むだけ）。下回りは `rbm_video_info` などで、SRAM の変数を読むだけ
- `samples/ruby/testapp/mode0.rb`〜`mode6.rb`: テスト用アプリ（ステータス行・ローレゾのデモ・試験模様・キー t l b f F o O S）から音を抜いたもの。
  画面モードは頭で 1 回決めるだけ。mruby に require が無いので、`scripts/make_testapp_rb.py` が共通の部分を写して作る（ローレゾの 8x8 の字形は font128 から 1 ビットで埋め込む）
- 実機（2026-10-17）: 7 つとも最後まで走った。準備の間はローレゾ面を隠す（8,192 ますを書く間に表示が重いと Ruby が進まない）。
  モード 3 は BG0 だけ・オブジェクトなしで始める: 全部出すと C のテスト用アプリでも 1 ペア約 150µs・fifo_stall 毎秒 1,000 以上で、Ruby は core0 が描画の手伝いと
  FB の待ちで埋まって進まず、ウォッチドッグが働いた（PC を読むと core0 の時間のほとんどが `expand_clut8`・`lr_draw_bg`・`park_isr`）
- **tick を実時間で数える**（`rbtick.c`）: tick の割り込み（優先度 0xE0）は core0 が描画の手伝い・FB の待ちで埋まると入れず、1 回に 1 つ数えるだけだったので
  Ruby の時間の区切り（10ms）が実時間で約 230ms になり、ループへ譲る間隔が延びた。前回からの実時間の分をまとめて数える（上限 50）
- **全体の GC の間はウォッチドッグを撫でる**（`tools/mruby/patches/0004`、`sgnano_gc_begin/end`）: GC は途中で譲れず、待たされるモードでは 0.5 秒近くかかる

## 画面モード 4・5・6（2026-10-17）
- `Machine.mode = 4 / 5 / 6`（`SCREEN_TEXT_LR_C4` / `SCREEN_TEXT_LR` / `SCREEN_LR`）。ローレゾ面はモード 3 と同じく、パターンとパレットを落としながら開く
- **CLUT4**（モード 4）: 1 行 320 バイト、上位ニブルが左（`render.c` の `expand_clut4` と同じ）。`rbm_fb_bits()`（16・8・4）で形式を見分ける。
  描画は `rbdraw.h` に点・横線（端のニブル + 間は memset）・縦線・転送（偶数の位置と幅は行ごとに memmove、ほかは 1 画素ずつ）・get_block / put_block（1 画素 1 バイト）を書き、
  線・三角形・塗りは `rbdraw_px.h` の雛形を `RBDRAW_OWN_MEM` で取り込む（`put4` `hline4` `vline4` を使う）。
  既定のパレットは PC-98 の 16 色（`text_get_palette`）
- モード 5・6 の FB の方法は RGB555 のページに描く（モード 1 と同じ）。モード 6 はテキスト面を出さない（`text_enable(false)`）
- **取得の間 core0 を待たせる仕組みを、CLUT4 では「ペアの 2 ラインの取得をまとめて行う間だけ」に縮めた**（`render.c` の `park_short`）。
  以前はペアを描き終えるまで止めていて、ローレゾを合成するぶんペアが長く、**core0 が 9 割近く止まり**（lowres.rb を CLUT4 で 12 秒走らせて 87%）、
  モード 4 のデモでウォッチドッグの再起動が起きた。縮めたあとは約 1 割（12 秒で 1.0〜1.4 秒）。待たせないと、core0 の PSRAM の読み書きが取得の DMA を詰まらせて
  表示の DMA まで止まった（CLUT8・CLUT4 とも fifo_stall 毎秒約 200・作り直し 3 回）。代わりに先読み（手順 5）をせず取得を並べて行うので、ペアが長くなる:
  lowres.rb でモード 4 は約 81µs（ピーク 97µs）。CLUT8 にも当てるとモード 3 が 82 -> 104µs（ピーク 112 -> 122µs）と予算に近づくので、**CLUT8 は前の形に戻した**
  （ユーザー判断）。前の形のモード 3 は 82µs で、core0 は 87% 待たされ、lowres.rb の 12 秒で fifo_stall +394（underrun 0・作り直し 0）
- RGB555（モード 2）は以前の形のまま（ペアの終わりまで待たせる）: 短い形にすると、フレームの終わり近く（ライン 444・452）で毎フレーム 2 回 fifo_stall が出た
  （mandel640.rb で 40 秒に +5,600）。前の形では mandel640.rb（117 秒）で fifo_stall +0
- 実機（2026-10-17）: mode456.rb が all ok（underrun 0・fifo_stall +0）。lowres.rb の 12 秒で underrun 0・作り直し 0、fifo_stall はモード 3 で +394（前の形）、モード 4 で +3〜9、モード 5・6 で 0
- ホスト試験: `samples/ruby/mode456.rb`（CLUT4 の描画の端・奇数の位置の転送・透明色・重なり、モード 5・6 のローレゾ、戻ったときの形式）

## 2026-10-18 いまの形（RTOS とパイプライン化のあと）
上の「取得の間 core0 を待たせる」の節は、Ruby が core0 で走っていたときのもの。いまは:
- Ruby はアプリのタスクとして **core1**（M33BEATOS）で走る。core0 はベアメタルで描画と FB の取得の処理だけ（`SPEC_m33beatos.md`）
- FB の取得は core0 の取得の処理が DMA 1 本で表示の順に行う（パイプライン化、`SPEC_lowres_2core.md` §4 の訂正）。Ruby が FB を使う間（`render_park_on`）は、
  **空いたラインが 8 本たまってから core1 を待たせ（doorbell、止まった返事を待つ）、8 本までまとめて取って解く**（`render_fe_burst`）。形式（RGB555・CLUT8・CLUT4）によらず同じ
- 速さ（`samples/ruby/bench.rb`、`docs/sgnano_ruby_guide.md` §10）: 空ループ 10 万回がモード 1 で 0.17 秒、モード 2 で 0.54 秒、モード 4 で 0.27 秒。
  `mandel640.rb` 95.9 秒（前の形 107 秒）、全面の `clear` 40ms（前 51ms）。`pset` 1 万回は 0.73 -> 0.99 秒、`hat.rb` は 20.5 -> 24.1 秒と遅くなった
  （1 点ずつ PSRAM に書くものは、まとめて取る間の待ちに当たりやすいと見ている。未確かめ）
- CLUT8・CLUT4 の Ruby の `fifo_stall` は 0（以前は 4 秒に 300〜500）
- 2026-10-29: 全面 clear の間だけ FB を隠して表示の取得を止め、32 ビットで埋める（`rbm_fb_clear`）。実機 `clear` 100 回が 3672 -> 3369ms
  （36.7 -> 33.7ms/回、モード2、underrun 0）。DMA で埋める試しは 44.9ms で underrun が大量に出たため不採用。モード4 は 5ms のまま

## 画面モード 7: テキスト + 320x200x8 のビットマップ（2026-10-23）
VGA のモード 13h と同じ形（1 画素 1 バイト、256 色のパレットの番号）。Doom / Doom2 を移す下ごしらえ（ユーザー指示）。下回りは `src/video/bitmap8.c`。
- **VRAM（64,000 バイト）とパレット（256 色）は SRAM**（アリーナ、ローレゾ面と同じに開く・閉じる）。Ruby が `Machine.mode = 7` で開き、終わると閉じて返す。
  SRAM なので、いつ書いてもすぐ出る（アプリ時間を待たない。描いている途中のフレームには、その時の中身が出る）
- 表示は縦横 2 倍の 640x400。31kHz（480 ライン）は上下 40 ラインずつ空け（背景色）、24kHz（400 ライン）はちょうど。15kHz は断る
- テキスト面は同じ 400 ラインに **25 行**で重なる（ビットマップは不透明、テキストの透過の所から見える）。Ruby の端末も 25 行になり（`Machine.text_rows` = 25）、
  状態の行（29 行目）は出ない。マウスカーソルは画面の座標のまま
- 既定のパレット: 0〜15 = テキストと同じ PC-98 の 16 色、16〜231 = 6x6x6、232〜255 = 灰色 24 段

| メソッド | 中身 |
|---|---|
| `Machine.bitmap` | `Machine::Bitmap`。`ready?`（モード 7 を選んだことがある）・`width` 320・`height` 200 |
| `clear(c = 0)` `pset(x, y, c)` `pget(x, y)` | 色の番号は 0〜255 に丸める。外は描かない、`pget` は nil |
| `line(x0, y0, x1, y1, c)` `rect(x, y, w, h, c)` `fill_rect(x, y, w, h, c)` | はみ出た所は描かない |
| `palette(i)` -> `[r, g, b]`、`palette(i, r, g, b)` | 0〜255（画素は各 5 ビット）。範囲の外は ArgumentError。すぐ効く |
| `write(offset, s)` / `read(offset, n)` | VRAM の `offset`（= y * 320 + x）からバイトをそのまま。書いた数を返す、はみ出た分は切る |

- 実機（2026-10-23、`samples/ruby/mode7.rb`）: 確かめ（大きさ・25 行・描く・はみ出し・write / read・パレット）が all ok、パレットを毎フレーム 216 色書き換えて
  underrun 0・recover 0、1 ペア 37µs（予算 127µs）。ファイラーの Alt+PrintScreen で写した画面で、表示の位置と重なりを見た

