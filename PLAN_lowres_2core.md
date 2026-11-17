# sgnano 改修計画：2コア描画パイプラインとローレゾ面

> 【追記 2026-10-18】2026-09-24 の計画として残す。実装は済み、その後の変更（ペアの取り合い・RTOS・取得のパイプライン化）は 仕様メモ（内部） の訂正と `docs/notes/video.md`。

作成日: 2026-09-24
対象仕様: 仕様メモ（内部）（2026-09-24）
前提現況: `docs/DEVELOPMENT.md`

仕様書 §11 の段取り（S1〜S6）に従い、1段ずつ実機確認を挟んで進める。
この計画は各段の「触るファイル・追加する関数・確認手順・リスク」を具体化したもの。

---

## 0. 事前確認（実施済み。推測ではなく実測・実行で確認した事項）

| # | 確認事項 | 結果 |
|---|---|---|
| 1 | `sadd8` / `sel` が使えるか | **使える**。現行ビルドフラグ `-mcpu=cortex-m33 -march=armv8-m.main+fp+dsp` で `__ARM_FEATURE_SIMD32=1` / `__ARM_FEATURE_DSP=1` が既に定義済み。インラインアセンブラで `sadd8`/`sel` がアセンブルされることを objdump で確認済み。**CMake 側の追加フラグは不要**（§12 の `#error` ガードだけ入れる） |
| 2 | 予備 IRQ の確保 | `user_irq_claim_unused(bool required)` が `hardware/irq.h:520` に存在。`NUM_USER_IRQS = 6`、`FIRST_USER_IRQ = NUM_IRQS - 6`。RAM ベクタテーブルは両コア共用なので、ハンドラ登録は1回・有効化は core0 のみで良い |
| 3 | multicore API | `multicore_launch_core1()` / `multicore_reset_core1()` あり。ただし **`pico_multicore` は現在リンクされていない**（第1段階で core0 のみ方針にしたとき外した）。S1 で `CMakeLists.txt` に追加する |
| 4 | core1 のスタック | リンカスクリプト（`memmap_copy_to_ram.ld`）で `__StackOneTop = SCRATCH_X の末尾`。**core1 スタック = SCRATCH_X 4KB、core0 スタック = SCRATCH_Y 4KB**。どちらも 512KB のストライプ領域の外なので、ローレゾ用 SRAM とは競合しない |
| 5 | SRAM 残量 | ストライプ RAM 512KB（0x20000000〜0x20080000）。現状の使用量は `.text` 34.6KB + `.data` 8.4KB + `.bss` 101.4KB + ベクタ0.3KB + heap 2KB ≒ **147KB**。ローレゾ +182KB と新規コード（概算 +12KB）で **約341KB / 512KB**。余裕あり |
| 6 | 絶対ライン番号の意味 | 現行 `vga_abs_line = frame * VGA_V_TOTAL(525) + line`。コピー位置も `pf*525 + py`（py は 0..479）。先行上限 `VGA_RING_LEAD=28` のため、**次フレームのライン0に着手できるのは表示ライン497以降**。S1 で `text_refresh()` を VBLANK（ライン481〜493）に残しても、描画とグリフ面の競合は起きない |
| 7 | 割り込み優先度 | 現行: ライン割り込み `0x00`、コピー `0x40`、USB は SDK 既定 `PICO_DEFAULT_IRQ_PRIORITY = 0x80`。仕様 §4.6 の順（ライン > USB > 描画）にするには**描画の予備 IRQ を 0x80 より大きい値（0xC0）にする**。※現行よりコピー／描画が USB の下になるのは意図的な変更であり、リスクとして R-1 に記載 |

---

## 1. 全体の設計判断（仕様の実装方針として確定させること）

### 1.1 ファイル構成（新規・分割）
```
src/video/vga.c        表示経路のみに縮める（PIO・data/ctrl ch・line_table・ライン割り込み）
src/video/render.c/.h  【新規】ペア描画（render_pair）と両コア共通のスケジューラ、CLUT展開、pair_max 等の計測
src/video/video.c/.h   【新規】フレーム進行（wait_render_done / start_frame / render_active）と core1 の起動・停止
src/video/lowres.c/.h  【新規】ローレゾ面（パターン/マップ/パレット/OAM/制御値、ライン描画、out 変換、重ね）
src/video/lowres_ref.c 【新規】素朴版（実機自己検証の比較対象）
src/video/lrdemo.c/.h  【新規】デモと負荷試験（l / b / o / O / T キー）
scripts/test_lowres.py 【新規】参照モデル vs 実装モデルの突き合わせ
```
`vga.c` を分割するのは、生成側（ペア描画）が両コアから呼ばれる再入可能コードになり、
表示経路（core0 のライン割り込みだけが触る）と寿命・所有者が違うものになるため。

### 1.2 ペア番号の扱い
- **絶対ペア番号** `pabs = f * 240 + k`（f = フレーム、k = 0..239）で統一する
- 240 が偶数なので `pabs & 1 == k & 1` が常に成り立つ。**担当コア = `pabs & 1`** と単純化できる
- ペア k の表示ラインは `y0 = 2k`、`y1 = 2k+1`。絶対表示ライン `abs0 = f * VGA_V_TOTAL + y0`
- 各コアは自分の `pair_next[c]` を 2 ずつ進める。他コアの変数は読まない

### 1.3 スロット完成の公開（`ring_id` の置き換え）
```c
volatile uint32_t slot_ready_abs[VGA_RING_LINES];   // そのスロットに完成しているラインの絶対番号
```
- 現行の `ring_id[32]`（uint16、表示後に 0xFFFF で無効化）を廃止する
- **無効化処理が不要になる**（古い値は前フレームの絶対番号なので、現フレームの番号と一致しない）。
  ライン割り込みが毎ライン行っていた `ring_id[...] = 0xFFFF` を削除でき、最高優先度の割り込みが軽くなる
- 書き手は常に1コア（そのスロットのペアを担当するコア）。書く直前に `__dmb()`

### 1.4 `min_ready` の求め方（O(1) 化）
前方スキャン（最大28回）を最高優先度の割り込みで回すのは避ける。各コアが
```c
volatile uint32_t core_done_abs[2];   // そのコアが最後に完成させたラインの絶対番号
```
を公開し、`min_ready = min(core_done_abs[0], core_done_abs[1]) - 表示中絶対ライン` とする。
2コアは高々1ペアずれるだけなので、実際の余裕より最大2ライン控えめに出る（安全側）。
`underrun` は従来どおり `slot_ready_abs` の厳密な照合で数える。

### 1.5 非整列アクセスの書き方（§5.8.1・§12）
BG の `fine != 0` で `lr_pix` への書き込みが4バイト境界からずれる。C としての未定義動作を避けつつ
単一の `LDR`/`STR` を出させるため、`packed` 型経由に統一する。
```c
typedef struct { uint32_t v; } __attribute__((packed, may_alias)) u32_ua_t;
#define LD32U(p)     (((const u32_ua_t *)(p))->v)
#define ST32U(p, x)  ((((u32_ua_t *)(p))->v) = (x))
```
- **`objdump` で `ldrd` / `ldm` / `stm` / `memcpy` 呼び出しが出ていないことを確認する**（確認をS4の合格条件に含める）
- 初期化時に `SCB->CCR` の `UNALIGN_TRP` が 0 であることを確認し、1なら落とす（既定は0）

### 1.6 SIMD 合成の書き方（§12）
GE フラグは文をまたいで保たれる保証がないので、`sadd8` と 2つの `sel` を**1つの asm 文**にまとめる。
```c
static inline void lr_blend4(uint32_t *dst_pix, uint32_t *dst_pal,
                             uint32_t src, uint32_t palx4) {
    uint32_t d = *dst_pix, pd = *dst_pal, t, o, op;
    __asm volatile (
        "sadd8 %[t],  %[d],  %[z]\n\t"   /* dst の bit7=0（確定済み）のバイトで GE=1 */
        "sel   %[o],  %[d],  %[s]\n\t"   /* GE=1 -> dst を残す、GE=0 -> src を書く */
        "sel   %[op], %[pd], %[px]\n\t"  /* 同じ GE でパレット番号も選ぶ */
        : [t] "=&r" (t), [o] "=&r" (o), [op] "=&r" (op)
        : [d] "r" (d), [z] "r" (0u), [s] "r" (src), [pd] "r" (pd), [px] "r" (palx4)
        : "cc");
    *dst_pix = o; *dst_pal = op;
}
```
`sadd8` は符号付きバイト加算の結果が 0 以上のとき GE=1。`dst + 0 >= 0` は `dst` の bit7=0 と同値で、
仕様 §5.7 の「確定済み」判定と一致する。

### 1.7 待ちの上限（§12）
すべての待ちにループ回数の上限を設け、超えたら `vga_sw_timeout` を増やして処理を打ち切る。
対象: copy ch の完了待ち、core1 の停止確認、`video_wait_render_done()`、DMA abort 完了待ち（既存）。

---

## 2. S1：2コア化のみ（ローレゾなし）

### 2.1 作業項目
1. **`CMakeLists.txt`**: `pico_multicore` を `target_link_libraries` に追加。`src/video/render.c` / `video.c` を追加
2. **`vga.c` から生成側を切り出す**
   - `expand_clut8()` / `expand_clut4()` → `render.c`（そのまま。static な作業領域を持たないので既に再入可能）
   - `copy_try_start()` / `vga_copy_isr()` → 廃止し、`render_pair()` / `render_step()` に置き換え
   - `copy_pf` / `copy_py` / `copy_pabs` / `copy_active` / `copy_line` / `copy_t0` を廃止
3. **copy ch を2本にする**: `dma_copy[2]`。`vga_init()` で2本 claim。DMA 完了割り込み（DMA_IRQ_1）は**使わない**（`dma_channel_set_irq1_enabled` を外し、`irq_set_enabled(DMA_IRQ_1,false)`）
4. **`slot_ready_abs[32]` / `core_done_abs[2]` を導入**し、`ring_id[]` とライン割り込み中の無効化処理を削除
5. **`render_pair(c, pabs)` の実装**（仕様 §4.3 の手順1〜6をそのまま）
   ```c
   static void __not_in_flash_func(render_pair)(unsigned c, uint32_t pabs);
   ```
   - 手順1/3/5 の copy 起動と完了待ち（上限つきポーリング）
   - 手順4/6 で CLUT 展開 →（S4以降）ローレゾ重ね → `text_overlay_line()` → `__dmb()` → `slot_ready_abs[y%32] = abs` → `core_done_abs[c] = abs`
   - 先頭で `timer_hw->timerawl` を取り、末尾で `pair_max[c]` を更新
6. **スケジューラ `render_step(c)`**（1ペアだけ進め、着手できなければ false を返す）
   ```c
   static bool __not_in_flash_func(render_step)(unsigned c);
   ```
   - 着手条件（§4.4）: (a) S2 以降はフレーム開始済み、(b) `(int32_t)(abs1 - 32 - d) < 0` すなわち書き込み先スロットの表示が終わっている
   - 遅れ（`(int32_t)(abs0 - (d + 2)) < 0`）なら、そのペアを飛ばして `pair_next[c] += 2`、`underrun` に2加算
7. **core0 側の駆動**: `user_irq_claim_unused(true)` で確保した IRQ にハンドラを登録、優先度 **0xC0**。
   ハンドラは `while (render_step(0)) ;` で戻る。ライン割り込みの末尾で `irq_set_pending(render_irq)`
   （現行の `nvic_hw->ispr[DMA_IRQ_1/32] = ...` を置き換え）
8. **core1 側の駆動**
   ```c
   static void __not_in_flash_func(core1_main)(void) {
       __asm volatile ("cpsid i");                 // core1 では割り込みを使わない
       irq_set_enabled(SIO_IRQ_FIFO, false);
       while (true) {
           if (core1_stop_req) { core1_stopped = true; __dmb(); __wfe(); continue; }
           core1_stopped = false;
           if (!render_step(1)) __wfe();
       }
   }
   ```
   - ライン割り込みが毎ライン `__sev()` を出して起こす（SEV は全コアのイベントレジスタを立てるので取りこぼさない）
   - 「条件確認 → WFE → 再確認」のループ形なので、確認と WFE の間に SEV が来ても失われない
9. **停止と作り直し（§4.7）**
   - `display_stop()`: `core1_stop_req = true` → `__sev()` → `core1_stopped` を**上限つき**で待つ → 描画 IRQ を無効化 → 従来どおり errata E5 手順で DMA 停止
   - `display_start()`: 表示経路を作り直す → `pair_next[]`・`slot_ready_abs[]`・`core_done_abs[]` を初期化 → 描画 IRQ 有効化 → `core1_stop_req = false` → `__sev()`（このとき**ライン割り込みがまだ動いていないので明示的な SEV が必要**）
   - `vga_recover()` は上記2つを呼ぶだけ（現行どおり）
10. **計測**: `copy_max` → `pair_max[2]` に置き換え。`[run]` ログを `pair_max=NN/NNus` 形式に
11. **起動時のリング先詰め**: 現行 `display_start()` は同期的に数ライン分コピーしてから PIO を走らせている。
    2コア化後は core1 が動いている前提になるので、**core0 単独で先頭数ペアを `render_pair()` で作ってから**
    表示を開始する（core1 の待機解除は表示開始後でよい）

### 2.2 合格条件（仕様 §11 S1）
- RGB555 / CLUT8 / CLUT4 の各モードで、`T`（全面テキスト）状態にして `underrun=0` `fifo_stall=0`
- `min_ready` と `pair_max` が現状以上（現状 `copy_max` は RGB555+テキストで最悪33µs）
- `v`（モード巡回）と `V`（復帰）が正常に動く

### 2.3 この段で見るべき数値
- `pair_max[0]` / `pair_max[1]` の差（USB 割り込みを受ける core0 だけ大きくなるはず → R-1 の検証）
- RGB555 での copy 完了待ち時間。2本の copy ch が同時に PSRAM を読むため、1本あたりの所要は最大2倍になる
  （総帯域は変わらないが、ペア内の「転送を裏に隠す」前提が崩れていないかを確認する）

---

## 3. S2：フレームの進め方（§3）

### 3.1 作業項目
1. **`video.c` の状態**
   ```c
   static volatile uint32_t start_seq;            // 開始を出したフレーム数
   static volatile uint32_t core_frame_done[2];   // 各コアが描き終えたフレーム番号
   static volatile uint32_t render_frame;         // いま描いているフレーム番号
   ```
   - 描画終了 = `core_frame_done[0] == core_frame_done[1] == render_frame`
   - 各コアは、自分の `pair_next[c]` がフレーム f の範囲（240ペア）を越えた時点で `core_frame_done[c] = f` を書く。
     **遅れて飛ばしたペアがあっても越えれば終了扱いにする**（そうしないと描画終了が来ない）
2. **API**（`video.h`）
   - `video_wait_render_done()`: 描画終了までポーリング（上限つき。超過は `sw_timeout`）
   - `video_start_frame()`: `text_refresh(TEXT_REFRESH_MAX_CELLS)` → `__dmb()` → `start_seq++` → `start_line` を記録 → `irq_set_pending(render_irq)` と `__sev()`
   - `video_render_active()`: `start_seq > 完了フレーム数` の間 true
   - `video_frame_count()`
3. **着手条件に (1) を追加**: `render_step()` の先頭で `pabs / 240 < start_seq` を確認
4. **期限判定（ライン割り込み、ライン500）**
   - `VIDEO_START_DEADLINE_LINE[VGA_MODE_COUNT]`（初期値 全モード 500）
   - 描画終了済みで未開始 → 強制開始（ライン割り込みからは `text_refresh()` を呼ばず、`start_seq++` のみ）、`late_start++`
   - 描画未終了 → `late_render++`。開始は出さない（最後に終えたコアが `render_step()` の中で自動的に次フレームへ進めるよう、
     「期限を過ぎている & 描画終了」で自動開始するフラグ `auto_start_pending` を立てる）
5. **`text_refresh()` の移動**（§3.4）
   - `main.c` の VBLANK 監視ループから外し、`video_start_frame()` の中へ
   - 展開中に `video_render_active()` が true になったら中断（強制開始との競合）
   - `TEXT_REFRESH_MAX_CELLS` を `text.h` に定義（初期値は現行の 24 から実測で調整）
6. **`main.c` のアプリループを §3.3 の形に書き換える**（デモの手本になる形にする）
   ```c
   while (true) {
       video_wait_render_done();
       /* 表示資源の書き換え（ローレゾ・テキスト・CLUT・PSRAM） */
       video_start_frame();
       /* 次フレーム用の計算（アプリ自身の変数のみ） */
   }
   ```
7. **カウンタ追加**: `late_start` / `late_render` / `done_line`（最小・最大）/ `start_line`（最大）

### 3.2 §3.5 の実測（この段の主目的のひとつ）
「アプリ時間中は取得 DMA が1本も動いていないので、表示期間中でも PSRAM に書けるはず」を確認する。
- 試験用キーを1つ用意し、アプリ時間に PSRAM へ 16KB / 32KB / 64KB を書いて `fifo_stall` と `underrun` の増分を見る
- 書き始めの表示ラインもログに出す（450〜479 の表示期間中に書けているかを確認するため）
- 結果を `docs/DEVELOPMENT.md` に記録し、§3.3 の決まりを更新する

### 3.3 合格条件
- 開始を意図的に遅らせる試験で `late_start` が数えられ、表示が破綻しない
- §3.5 の実測結果が記録されている

---

## 4. S3：`VGA_MODE_NONE`

### 4.1 作業項目
1. `vga_mode_t` に `VGA_MODE_NONE` を追加、`v` の巡回に加える。`vga_mode_stride()` / `copy_words` の扱いを分岐
2. `vga_set_backdrop(uint16_t rgb)`。内部に倍幅値 `backdrop2 = rgb | (rgb << 16)` を持つ
3. `render_pair()`: NONE では手順1・3・5（copy）を行わない。ローレゾ未実装の段階では
   スロット全体（320ワード）を `backdrop2` で埋めてからテキスト合成する
4. `[run]` ログのモード名に `NONE` を追加

### 4.2 合格条件
- 背景色が表示され、テキストが重なる
- 表示期間中に PSRAM へ書いて `fifo_stall = 0`（表示用 DMA が PSRAM に触れないため）

---

## 5. S4：ローレゾ BG1 のみ

### 5.1 作業項目
1. **データ定義（`lowres.h` / `lowres.c`）**
   ```c
   uint8_t   lr_pattern[128 * 1024] __attribute__((aligned(4)));
   uint32_t  lr_map[2][64 * 64];
   uint16_t  lr_palette[64][128];
   lr_obj_t  lr_oam[128];
   lr_ctrl_t lr_ctrl;
   ```
2. **コアごとの作業領域**（§5.8。static な作業領域を関数内に持たない）
   ```c
   typedef struct {
       uint8_t  pix[512] __attribute__((aligned(4)));
       uint8_t  pal[512] __attribute__((aligned(4)));
       uint64_t cov;
       uint32_t out[320];
   } lr_work_t;
   static lr_work_t lr_work[2];      // [コア番号]
   ```
3. **関数**
   ```c
   void lr_render_line(unsigned L, lr_work_t *w);   // pix/pal/cov を作る
   void lr_to_out(lr_work_t *w);                    // out[320] に変換（§5.8.2）
   void lr_overlay(uint16_t *slot, const uint32_t *out, vga_mode_t mode, uint32_t backdrop2);
   ```
   すべて `__not_in_flash_func`。`lr_pix` の初期化は 0x80808080 で 128ワード分（`cov = 0`）
4. **BG 描画（まずは BG1、パレット1本・スクロールなし → スクロールあり）**
   - §5.8.1 の手順どおり。タイル1行8バイトを 2ワードで書く（`fine != 0` では非整列 → `ST32U`）
   - 最初のレイヤなので `sel` による合成は不要（全画素が未確定）。ただし**透過画素を潰さないため
     合成経路を通す実装に最初からしておく**（S5/S6 で経路が変わらないようにする）
5. **`render_pair()` に組み込む**: 手順2でローレゾライン `L = k` を描画、手順4/6 の CLUT 展開後に `lr_overlay()`
6. **計測**: `lr_max`（描画＋変換の最大時間）
7. **`scripts/test_lowres.py`**（§10.1）: 参照モデル（奥→手前、1画素ずつ）と実装モデル（手前→奥、飛ばしあり）を
   Python で両方書き、乱数場面で全240ライン×320画素の `pix` と `pal` の一致を確認。この段では BG1 の範囲だけ

### 5.2 合格条件
- `test_lowres.py` の BG1 範囲が一致（スクロール端の折り返しを含む）
- CLUT8 / CLUT4 / NONE で表示される
- `objdump` で BG 描画に `ldrd` / `ldm` / `stm` / `memcpy` が出ていないこと

---

## 6. S5：BG0、パレット64本、反転

### 6.1 作業項目
1. BG0 を追加し、**手前から奥（BG0 → BG1）**の順で `lr_blend4()` により合成する
2. パレット番号をマップエントリから取り出し、`palx4`（4バイト複製）で `lr_pal` に書く
3. 横反転（8バイトを左右逆順）・縦反転（`7 - row`）を実装
4. **実機自己検証**（§10.2）: `lowres_ref.c` に素朴版（奥→手前、1画素ずつ、SIMD なし）を置き、
   キー操作で固定場面を両方で描画して240ライン分を比較、一致・不一致をログに出す
5. `test_lowres.py` を BG0 + パレット + 反転の全組み合わせに拡張

### 6.2 合格条件
- `test_lowres.py` 該当範囲が一致、実機自己検証で一致
- CLUT8 / CLUT4 / NONE で表示、`underrun=0` `fifo_stall=0`

---

## 7. S6：オブジェクト

### 7.1 作業項目（3つに分けて、それぞれ動かしてから次へ）
1. **(a) 幅・高さ・反転**: OAM 走査、行の選択、`lr_pattern` からの読み出し、`pattern*64 + H*W > 128KB` の
   範囲確認（`lr_obj_range_err`）、`obj_line_max` の計測
2. **(b) 優先度リスト**: 1ラインにつき OAM を1回走査して優先度別の3リスト（OAM 番号昇順）を作り、
   §5.7 の順（OBJ2 → BG0 → OBJ1 → BG1 → OBJ0）で合成
3. **(c) 確定済みの飛ばし（3段階）**: 4画素単位の `(dst & 0x80808080) == 0` 判定、
   8画素単位の `uint64_t cov`（64ブロック）、ライン単位（ブロック8〜47 が全確定なら残りを処理しない）
4. **デモと負荷試験**（§10.3）: `l` / `b` / `o` / `O` / `T` キー。デモは §3.3 の決まりどおりに書く

### 7.2 合格条件
- `test_lowres.py` 全項目一致（境界条件を含む）
- 実機自己検証で一致
- `O`（幅64×高さ64を128個重ねる）の負荷試験で `underrun=0`

---

## 8. リスクと対策

| # | リスク | 対策・確認方法 |
|---|---|---|
| **R-1** | **描画 IRQ が USB より低優先度になる**（現行のコピー 0x40 → 描画 0xC0）。USB-CDC の printf 処理が長いと core0 のペア処理が遅れ、`pair_max[0]` だけ悪化しうる | S1 で `pair_max[0]` と `pair_max[1]` を比較して確認する。悪化するなら (a) 毎秒ログの文字数を減らす、(b) USB 割り込みの優先度を 0x40 に上げて描画を 0x80 にする、のいずれかを検討（仕様 §4.6 からの逸脱になるので、実測値を添えて相談する） |
| **R-2** | **copy ch 2本の同時実行で PSRAM の待ちが増える**。RGB555 は元々1ライン23µs（ライン周期の73%）で、2本同時なら1本あたり最大46µs | 総帯域は変わらないのでフレーム全体としては収まるが、§4.3 の「転送を裏に隠す」前提が RGB555 では成立しない。S1 で RGB555 の `pair_max` を実測。必要なら RGB555 だけ copy ch を1本に戻す（RGB555 ではローレゾを描かないので裏に隠す相手がいない） |
| **R-3** | `display_stop()` 中に core1 が copy 完了待ちで回っている | 完了待ちに上限を設ける（§1.7）。停止要求は `core1_stop_req` で出し、core1 は**ペアを終えてから**待機に入る。確認待ちにも上限を設け、超えたら `sw_timeout` を増やして強制的に進む |
| **R-4** | **`display_start()` 時に core1 を起こす SEV が無い**（ライン割り込みがまだ動いていない） | `display_start()` の末尾で明示的に `__sev()` を出す |
| **R-5** | `text_refresh()`（フォント ROM = フラッシュ XIP 読み出し）が PSRAM 取得と QMI を奪い合う | S2 で `video_start_frame()` 内に移し、`video_render_active()` が true になったら中断する（§3.4）。S1 の間は現行どおり VBLANK（ライン481〜493）に置く。事前確認のとおり、この区間に次フレームの描画は始まらない |
| **R-6** | `glyph[]` を書く `text_refresh()` と読む `text_overlay_line()` が両コアで競合 | 書き換えはアプリ時間（描画が止まっている間）のみ。S2 で `video_render_active()` による中断を必ず入れる |
| **R-7** | 非整列アクセスで GCC が `ldrd` / `ldm` / `memcpy` を出す | `packed` 型経由（§1.5）＋ `objdump` での確認を S4 の合格条件にする。`SCB->CCR.UNALIGN_TRP` が0であることも起動時に確認 |
| **R-8** | GE フラグが `sadd8` と `sel` の間で失われる | 1つの asm 文にまとめる（§1.6）。実機自己検証（素朴版との比較）で最終確認 |
| **R-9** | 両コアが同じ `volatile` 変数を書いて壊す | 書き手を1つに限る設計にする（`slot_ready_abs[s]` はそのスロットの担当コアのみ、`core_done_abs[c]` / `pair_max[c]` / `pair_next[c]` はコアごと）。`underrun` など両コアが増やすカウンタは**コアごとの配列に持ち、ログ出力時に合算する** |
| **R-10** | ローレゾ 182KB を `.bss` に置くことで起動時のゼロクリアが伸びる | 起動時間の問題のみ。実害があれば `.uninitialized_data` セクションの利用を検討 |
| **R-11** | 両コアの命令フェッチが同じストライプ RAM に集中 | RP2350 のストライプ RAM はバンク間インタリーブなので衝突は限定的。スタックは SCRATCH_X / SCRATCH_Y（非ストライプ、コア別）に分かれている（事前確認）。`pair_max` で実測して判断する |
| **R-12** | 仕様 §4.3 手順5 で「次の担当ペアの先頭ラインの取得を先行起動」するが、そのスロットがまだ表示中の場合がある | 起動条件を §4.4 の条件2 と同じ式で確認してから起動する。条件を満たさなければ起動せず、次のペアの手順1で起動する |

---

## 9. SRAM 見積もり

| 項目 | 現状 | S6 完了時 |
|---|---|---|
| `.text`（`copy_to_ram`） | 34.6KB | 約47KB（新規コード +12KB 概算） |
| `.data` | 8.4KB | 8.4KB |
| `.bss` | 101.4KB | 約283KB（+ローレゾ 182KB） |
| ベクタ・heap | 2.3KB | 2.3KB |
| **ストライプ RAM 計** | **約147KB / 512KB** | **約341KB / 512KB** |
| core0 スタック | SCRATCH_Y 4KB（別領域） | 同左 |
| core1 スタック | ― | SCRATCH_X 4KB（別領域） |

---

## 10. 検証の進め方

1. **Python で先に確かめる**（PT8211 の教訓）。`scripts/test_lowres.py` は S4 の実装より先に、
   参照モデルと実装モデルの両方を書いて一致させてから C に移す
2. **実機自己検証**（SIMD 版 vs 素朴版）を S5 から入れる。合成順・飛ばしの最適化を入れる前に
   「正しい絵」の基準を作っておく
3. **各段でタグを打つ**（`stage5-2core`、`stage6-lowres` など）
4. **各段の実測値を `docs/DEVELOPMENT.md` に記録する**（特に §3.5 の PSRAM 書き込み可能時間帯、`pair_max`、`lr_max`）
5. ログは ASCII のみ（既存の決まり）

---

## 11. 仕様に対する確認事項（実装前に合意したい点）

1. **R-1**: 描画 IRQ を USB より下に置くと、core0 のペア処理が USB 割り込みで押し出される。
   仕様 §4.6 の優先度順で進めるが、S1 の実測で `pair_max[0]` が悪化した場合は優先度の入れ替えを提案する
2. **R-2**: RGB555 では copy ch 2本同時が帯域的に厳しい。§13 で「RGB555 でのローレゾ表示」が後回しになっているので、
   RGB555 だけ copy ch 1本（従来方式）にする選択肢を残しておきたい
3. **§4.3 手順5 の先行起動**は、スロット空き条件を満たさないときは行わない（R-12）
4. **`underrun` の数え方**: ペアを飛ばしたときは2ライン分として数える（現行はライン単位の表示時照合なので、
   飛ばしたペアは表示時にも2回数えられる。**二重計上を避けるため、飛ばしたときは計上せず、表示時の照合のみで数える**方針とする）
5. **描画終了の定義**: 遅れて飛ばしたペアがあってもフレーム範囲を越えれば終了扱いとする（§3.1 の2）
