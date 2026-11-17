# 開発環境（ビルド・書き込み・診断・静的解析・SRAM）

> docs/DEVELOPMENT.md から分けた**経緯と詳細**（2026-10-03）。いまの状態・決まりごと・手順は docs/DEVELOPMENT.md を見ること。
> 各節は日付つきの記録なので、古い記述を新しい節が訂正していることがある（訂正には【訂正】【追記】の注記を付けた）。

## 診断ビルド（切り分け用）
`cmake -DSGNANO_DIAG_NO_VGA=ON`（VGAなし・LED(GP25)点滅+USB-CDCログ）、`-DSGNANO_DIAG_NO_OVERCLOCK=ON`（クロック無変更）、
`-DSGNANO_DIAG_PSRAM=ON`（PSRAM の分周x RXDELAY 掃引・自己検証・帯域測定）、`-DSGNANO_CORE_VOLTAGE=VREG_VOLTAGE_1_20`、`-DSGNANO_FLASH_CLKDIV=<n>` / `-DSGNANO_FLASH_RXDELAY=<n>`（boot2 上書き）、
`-DSGNANO_WATCHDOG_MS=<ms>`（既定500、0で無効）、`-DSGNANO_USB_DEBUG=1|2`（既定1）、
`-DSGNANO_USB_LOG_RAM=ON`（TinyUSB のログを RAM に貯める。`u` キーで吐き出し）。
（CPU描画の負荷テスト `drawtest` は凍結時に削除した。コミット 0fb5501 に残っている。）
別ディレクトリ（`build_*`）で構成すること。picotool の再ビルドを避けるには `-Dpicotool_DIR=$PWD/build/_deps/picotool` を付ける。

## ビルド・書き込み
- `scripts/build.sh [clean]` → `build/sgnano.uf2` / `build/sgnano.elf`（初回は SDK が picotool をビルドするため数分かかる）
- ボードヘッダは `boards/sgnano_rp2350b.h`（SDK の WeAct RP2350B ヘッダの複製。フラッシュ分周を3に変更、UART/I2C/SPI既定ピンを削除）
- **書き込みも実機の操作も、この環境から直接できる**（2026-09-24 から）。ユーザーの手作業は不要。
  - `scripts/flash_swd.sh` で書き込み（OpenOCD + デバッグプローブ、SWD）
  - `scripts/console.sh` でログの読み取りとキー入力（プローブの UART ブリッジ `/dev/ttyACM0`）
  - **実機確認のたびにユーザーへログを頼む必要はない。自分で書き込んで測ること。**
  - 前提: Windows 側で `usbipd attach --busid <B> --wsl` してプローブを渡してあること。
    渡されていなければ `lsusb` に `2e8a:000c Raspberry Pi Debugprobe` が出ないので、ユーザーに依頼する。
- 書き込みの詳細（`scripts/flash_swd.sh`）:
  - **大きな像（ABI 5.0 は約 3.5MB）は `scripts/flash_chunks.sh build/sgnano.elf` が確実**。
    2026-11-11 は `ADAPTER_SPEED=500 RETRIES=8` で通した（1〜2 チャンクの再試行は正常）。
    `ADAPTER_SPEED=100` は 20 分以上かかるので使わない。
  - `scripts/flash_swd.sh` で `build/sgnano.elf` を書き込んでリセット。
    `--attach` で接続したまま（gdb 用、:3333）、`--reset` でリセットのみ。
  - OpenOCD は **RP2350 対応の Raspberry Pi 版**が要る（`tcl/target/rp2350.cfg` を持つもの）。
    既定の場所は `~/Project/openocd/src/openocd` と `~/Project/openocd/tcl`。
    環境変数 `OPENOCD` / `OPENOCD_SCRIPTS` で変えられる。
    （ディストリの openocd 0.11.0 は RP2350 に対応していない。）
  - WSL では Windows 側から PicoProbe を渡す: `usbipd list` → `usbipd bind --busid <B>`（初回のみ）
    → `usbipd attach --busid <B> --wsl`
- 従来の方法も残してある（`scripts/flash.sh`）。プローブが使えないときの予備。
  - (a) BOOTSEL で出た Windows ドライブへ UF2 をコピー（`scripts/flash.sh /mnt/<drive>`）
  - (b) usbipd-win + `picotool load -f build/sgnano.elf`
- **フォント ROM（フラッシュ末尾4MB）は SWD の書き込みでは消えない**（ELF のセクションだけを書くため）。
  `EmbFont16Uni.uf2` を入れ直す必要があるのは、フラッシュ全体を消したときだけ。
- OpenOCD が読み取った実機の素性: **RP2350 rev 2**、フラッシュ **W25Q128FV/JV（id 0x1840ef、16MB）**。

### 【重要】デバッグ中に QSPI が壊れることがある → レスキューリセットで戻す
**症状**: `reset run` してもプログラムが動かない。UART に何も出ない。OpenOCD が
`QSPI Flash id = 0xb8ffef not recognised`（毎回違う値）と言う。halt すると
`pc = 0xEFFFFFFE`（Cortex-M のロックアップ）や ブートROM 内（0x0000xxxx）にいる。
- **原因**: PSRAM を QPI モードで使っている最中に `halt` やリセットが入ると、QSPI バスが
  中途半端な状態で止まり、ブートROM がフラッシュを読めなくなる。
- **対処**: `openocd -f interface/cmsis-dap.cfg -f target/rp2350-rescue.cfg -c init -c exit`
  （レスキューリセット）。これでフラッシュIDが正しく読めるようになる。そのあと普通に書き込める。
  電源の入れ直しでも直る。
- **教訓（2026-09-24 にやらかした）**: この状態を「USB ホストのコードがロックアップさせた」と
  誤診し、無関係な場所を調べた。**`halt` したあとに様子がおかしくなったら、まずレスキューリセット**して
  素の状態に戻してから切り分けること。動作中の観察は `halt` ではなく
  UART のログや `mdw`（実行したままメモリを読む）で行うほうが安全。


### 【重要】QSPI が中途半端な状態で止まる件（再掲・頻発する）
`halt` したあとや `reset run` を繰り返したあと、ブートROM がフラッシュを読めなくなり、
`PC=0x0000655c`（ブートROM 内）から進まなくなることがよくある。`vga_frame_count` を読むと
0 のまま、あるいは SRAM がゴミのまま。
- **対処**: `scripts/flash_swd.sh --rescue`（`target/rp2350-rescue.cfg`）。そのあと普通に書き込める。
- **測定の前には毎回 `--rescue` してから書き込む**こと。そうしないと「動かない」のが
  QSPI のせいなのか調べている対象のせいなのか分からなくなる（実際それで何度も混乱した）。


## SRAM を空ける試行: FB なしビルドの XIP 実行（T7・2026-10-02）
`-DSGNANO_PSRAM_FB=OFF -DSGNANO_XIP=ON` で、プログラム全体を SRAM へ写す（`copy_to_ram`）のをやめ、
**フラッシュから直接実行**する。熱い経路（`__not_in_flash_func` の34関数：ライン割り込み・描画・ローレゾ・テキスト合成）だけが SRAM に残る。
```
cmake -B build_xip -G Ninja -DSGNANO_PSRAM_FB=OFF -DSGNANO_XIP=ON -Dpicotool_DIR=$PWD/build/_deps/picotool
ninja -C build_xip && scripts/flash_swd.sh build_xip/sgnano.elf
```
- **FB ありビルドとは組み合わせられない**（CMake が止める）。PSRAM からの表示用の取得と XIP が QMI を奪い合うため（`copy_to_ram` にした理由そのもの）。

### 回収量
| ビルド | `.text`+`.rodata` の SRAM | SRAM の残り |
|---|---|---|
| FB あり・全体 SRAM（`build/`、既定） | 161 KB | 1,376 B |
| FB なし・全体 SRAM（`build_nofb/`） | 161 KB | 2,928 B |
| **FB なし・XIP（`build_xip/`）** | **0**（SRAM の関数は `.data` の 9KB に含まれる） | **162,672 B** |
FB なし同士で比べて **+159,744 B**。

### 実測（2026-10-02、同じ手順: 起動 -> モード5 12秒 -> モード6 10秒）
| | モード5 `pair_max` | モード6 `pair_max` | モード6 + オブジェクト48 | アプリ時間 |
|---|---|---|---|---|
| FB なし・全体 SRAM | 56/59 µs | 36/35 µs | 49/51 µs | 149〜153 µs |
| FB なし・XIP | 57〜58/63〜64 µs | 37〜42/40〜44 µs | 51/58 µs | 183〜213 µs |
- **`underrun` / `fifo_stall` / `recover` はすべて 0**。12タイミングの巡回と実機自己検証（`0 mismatched`）も通った。
- **アプリ時間が 35〜60µs 延びる**（アプリの処理がフラッシュから動くため）。窓 約1.47ms に対して 200µs 程度で余裕はある。
- **core1 の1ペアが、ときどき（毎秒1回以下）約8µs 長くなる**。仕事量によらず一定（オブジェクトを出しても +7〜8µs）で、
  その瞬間 core0 は `video_wait_render_done()` の中で **TinyUSB（`usbkbd_task`）をフラッシュから実行**していた
  （core0 がいるループの段を core1 が記録する一時計測で確認）。core1 自身はフラッシュを踏んでいない（下記の検査で確認）。
  仕組みは特定できていない（バスの共有部分での待ちと推測）。頻度とタイミングは計測コードを足すたびに変わった。
  予算 127µs に対して最悪 64µs なので実害はない。**消したければ TinyUSB を SRAM に置き直す**ことになるが、回収量が減る。
- **バンクの取り合いではない**: 主 SRAM の前半と後半で別のバンク群になっている（と理解している）ので、
  XIP でデータが前半に寄ったのが原因かと考え、`.bss` の先頭に詰め物を入れて全体 SRAM のビルドと同じ番地へずらしたが、変わらなかった。
- **未確認: CD 再生の `underruns`**（申し送りの完了条件の1つ）。光学ドライブとオーディオ CD が要る。
  PSRAM への先読み書き込みと XIP が QMI を共有するので、転送速度が落ちないかを見ること。

### 配置の検査を広げた（`scripts/check_sram_funcs.py`）
全体を SRAM に写すビルドでは、どこを呼んでも SRAM なので**検査が素通りしていた**。XIP で初めて意味を持つ。
- 直接呼び出し（`bl`）に加えて、**末尾呼び出し（`b` / `b.w` / 条件分岐）**の飛び先も見る。
- SRAM の関数の定数プール（`.word`）に **XIP の窓（0x10000000〜0x14000000）を指す値**があれば失敗にする
  （XIP では `.rodata` もフラッシュに残るので、熱い経路が表や文字列を読むとフラッシュを踏む）。
- 関数ポインタ経由の呼び出し（`blx rN`）は飛び先が分からないので一覧を出す（いまは0件）。
- ベクタテーブルは起動時に SRAM へ写される（`__pre_init_runtime_init_install_ram_vector_table`）ので、割り込みの入口でフラッシュは読まない。

### 【解決・2026-10-03】書き込みの直後に core1 が描かない — 原因は OpenOCD のリセット手順
**症状**: `pair_max=0/0`（または `x/0`）、`underrun` が増え続ける。申し送りの未解決「RGB555 で core1 が描画しない」と同じもので、
**NONE でも起き、画面モードとは関係ない**。SWD で書き込み・リセットした直後にだけ起きる（9回に1回程度）。
- **正体**: core1 は描画を始めたあとに**リセットされてブートROM に戻り**、起動の合図を待って `wfe` で眠り続けていた。
  止まった状態で（`halt` せずに）読んだ値:
  - core1 の PC（`DWT_PCSR` = 0xE000101C、止めずに読める）= **0x000000d8（ブートROM）**
  - core1 の DHCSR = `0x01140001`（S_SLEEP。S_HALT ではない = デバッガに止められているのではない）
  - `pair_abs[1]` がフレーム0のペア197で止まり、`video_core_frame_done[1]=0xffffffff`、`render_timeout[1]=0`
  （`render_step()` が呼ばれていれば遅れたペアを飛ばして進むはずなので、core1 は描画のループにいない）
- **原因**: OpenOCD の `rp2350.cfg` は両コアを SMP として扱い、`reset` で **core0 -> core1 の順に1コアずつ
  SYSRESETREQ を書く**（`ocd_process_reset_inner` の `foreach t $targets { $t arp_reset assert }`）。
  core0 のリセットでファームが動き出して core1 を起動したあとに、core1 へのリセットが遅れて届くと core1 だけが戻される。
  届くのが core1 の起動前なら無害なので、起きたり起きなかったりする。
- **対処（`scripts/flash_swd.sh`）**: リセットを **`cold_reset`**（DP の CDBGRSTREQ でチップ全体を1回だけ）に替えた。
  書き込みは `program $ELF verify` -> `cold_reset` -> **両コアの** C_DEBUGEN を落とす。`--reset` も同じ。
  **直した手順で書き込み・リセット計55回、core1 が止まったのは0回。**
- **外れた案**: core0 だけの構成（`set USE_CORE cm0`）で `reset` すると、**1回おきにファームが起動しなくなった**
  （コアごとの SYSRESETREQ はチップ全体のリセットではなく、周辺回路が前の状態のまま残るため）。
- **【副産物】C_DEBUGEN は両コアとも落とす**。OpenOCD は接続（`init`）するだけで両コアの C_DEBUGEN を立てる
  （実測 `0x01100001`）。以前は core0 にしか書いていなかった。**`mdw` で様子を見たあとも C_DEBUGEN が立ったまま**になるので、
  TinyUSB の assert で CPU が止まる（BKPT）可能性がある。見たあとは `scripts/flash_swd.sh --reset` で戻すか、両コアに書いておくこと。
- **測定の手順**: 測る前に「両コアが描いているか」を確かめる。実行したまま `render_core_next` を 0.3秒あけて2回読み、両方の値が進んでいれば正常。

### 【未解決】ファームそのものが起動しないことがある（直した手順で 55回中1回）
フレーム数も変数もすべて0のまま、両コアとも眠っている。既知の「QSPI が中途半端な状態で止まる」と同じ形。
**仮説（未確認）**: PSRAM の CS は GP0。RP2350 の GPIO はリセット直後にプルダウンが有効なので、基板にプルアップが無ければ
リセット直後に PSRAM が**選択状態**になる。QPI モードのまま残った PSRAM が、ブートROM のフラッシュ読み出しに応答してデータ線を乱す、
というもの（「フラッシュの ID が毎回違う値で読める」症状と合う）。
**次に起きたら読むもの**（止めずに `mdw`）: `0xd0000004`（SIO GPIO_IN の bit0 = GP0 の入力レベル）、
`0x40038004`（PADS_BANK0 GPIO0。PUE/PDE）、両コアの `0xE000101C`（PC）。GP0 が Low なら仮説どおり。
直すなら基板に GP0 のプルアップ（例 10kΩ）を足すのが筋。ソフトでは、ブートROM より前には手が出せない。


## 進捗レポート（PDF）
`docs/sgnano_report_2026-09-26.pdf`。できること・できないこと・資源の使用状況・今後の検討材料をまとめたもの。
- 生成: `python3 scripts/make_report.py [出力先.pdf]`（reportlab が要る: `pip3 install reportlab`）
- フォントは **Noto Sans JP / Noto Sans Mono（SIL OFL 1.1）**。再配布できるものを選んである。
  `scripts/fetch_fonts.sh` が Google Fonts の可変フォントを取得し、`fontTools` で
  wght を固定した静的インスタンスへ変換して `docs/fonts/` に置く（TTF 自体は約11MB なので git に入れない）。
  **Noto Sans CJK の `.ttc` は CFF アウトラインなので reportlab では読めない。** 可変 TrueType からの変換が要る。
- **【重要】`MONO()` に日本語を渡さない。** Noto Sans Mono に日本語グリフが無く、**黙って消える**
  （最初これでコード中の日本語コメントが欠落した）。コード片は ASCII だけにし、説明は本文に書く。

### X に貼る紹介画像
`docs/sgnano_card.png`（1600x900）。`python3 scripts/make_card.py [出力先.png]` で作る。
800x450pt の PDF を PyMuPDF で 144dpi にラスタライズしている（`pip3 install reportlab pymupdf`）。
**「動いている（実機で確認済み）」の欄には、実機で確認していないものを書かないこと。**
音源は最大8音の設計だが実装は2音、オブジェクトは1ラインあたり32個まで、といった条件を落とさない。

## ビルド構成の整理と SRAM の可視化（T1・2026-09-27）
初期の申し送りの T1（2026-09-27。当時の申し送りは 2026-11-05 に削除。記録は git 履歴）。

### `scripts/sram_report.py` — .map を機能別に集計する
`python3 scripts/sram_report.py [build/sgnano.elf.map] [-o out.md] [--quiet]`。
**ビルドのたびに CMake の POST_BUILD が走る**ので、普段は意識しなくてよい
（`build/reports/sram.md` に出力 + 要約1行）。
- **残量は「セクションの足し算」ではなく配置の末端（最大 VMA+size）で見る。**
  足し算では整列のすき間（実測 7KB）が漏れ、実際より空いて見える。
- **種別は出力セクションで決める。** 入力セクション名だけで数えると、
  破棄セクションや配置先の違いで 1〜2 割ずれる（最初これで .text を 8KB 多く数えた）。
- **`copy_to_ram` では `.rodata` も RAM に載る**ので分けて数える（`__in_flash` の候補）。
  実測 **26,388 B**。中身はほとんどがログの文字列リテラル（`*.str1.4`）。
  ただし**フラッシュを読むと XIP が動く**ので、ホットパスから参照されるものは移さないこと。
- 閾値: `-DSGNANO_SRAM_WARN_BYTES`（既定16384、0で無効）/ `-DSGNANO_SRAM_FAIL_BYTES`（既定0）。

### 外せるようにしたもの（実測の回収量）
| オプション | 既定 | 切ったときの残量 | 回収 |
|---|---|---|---|
| （素のまま） | ― | 3,204 B | ― |
| `-DSGNANO_DIAG_AUDIO=OFF` | ON | 27,892 B | **+24,688 B** |
| 上 + `-DSGNANO_USB_LOG_RAM=OFF` | ON | 31,996 B | **+28,792 B** |
| `-DSGNANO_PSRAM_FB=OFF` | ON | 12,948 B | **+9,744 B** |
- `SGNANO_DIAG_AUDIO` … `test_tone_buf` 8KB（`A` キー）+ `cap_buf` 8KB（`C` キー）とその処理。
  切ると呼ばれても「not built in」と言うだけになる。**`audio_stop_test_tone()` は
  通常再生の経路から必ず呼ばれる**ので、空実装を残すこと。
- `SGNANO_PSRAM_FB` … RGB555 / CLUT8 / CLUT4 の経路（取得DMA 2本・CLUT展開・パレット表）。
  **PSRAM 自体は CD の先読みで使い続ける。**外れるのは「表示のための取得」だけ。
  OFF のとき `vga_set_mode()` と `v` キーは NONE 以外を断る（黙って無視しない）。
  **実機で確認済み（2026-09-27）**: `underrun=0 fifo_stall=0 recover=0 pair_max=55/58us`、
  実機自己検証 `0 mismatched pixels of 76800` と、FB ありビルドとまったく同じ。

### 【重要】RGB 出力 PIO の1画素サイクル数（申し送り §3 #1 の答え）
**PIO の分周は 1（PIO クロック = clk_sys）で、ドット周期は遅延スロットで作っている。**
`out pins,16 [11]` + `out pins,16 [10]` + `jmp` = 24clk で 2画素（= 1画素 12 sysclk）。
- したがって **ドットクロックの分周 D は「PIO 分周 k」と「1画素のサイクル数 c」の積**で作れる。
  2画素ループなら 2c = a+b+3（a,b ≤ 31）なので **c は 2〜32 の任意の整数**。
- 申し送りの「÷14 が使えるのは1画素 1・2・7 サイクルのときだけ」という前提は**当たらない**。
  **÷14（c=14）も ÷15（c=15）も ÷28（c=28）も、分周1のまま作れる。**
  ÷35 は c=35 が上限超だが、1画素ループ（`out [31]` + `nop [d]` + `jmp` = 34+d）にすれば
  ÷35〜÷65 まで届く。**÷36・÷48・÷60 も同様に分周1で作れる。**
- **PIO 分周を 1 以外にするのは避けたほうがよい。** HSYNC 用 SM は sysclk を直接数えており、
  IRQ フラグ4 の受け渡しが「c+2 サイクルで最初の画素」という前提に乗っている。
  分周 k にすると受け渡しに最大 k-1 サイクルの揺らぎが乗る。
- **PIO0 の命令メモリは 32 語中 27 語使用（hsync 21 + rgb 6）で、空きは 5 語。**
  周波数ごとに別プログラムを常駐させる余裕はない。**モード切替のたびに読み込み直すこと**
  （表示経路はどのみち作り直すので、そこに載せられる）。

### 【重要】`vga_ring` の先行28ラインの根拠（申し送り §3 #5 の答え）
**28 は実測から決めた値ではなく、リングの上限。** `_Static_assert` が
`VGA_RING_LEAD + 2 <= VGA_RING_LINES`（= 30 以下）を課しており、そこから 2 引いただけ。
- リング本数 32 の根拠は `VGA_V_ACTIVE % VGA_RING_LINES == 0`（480 が 32 で割り切れる）。
  こうするとスロットの対応がフレームをまたいでも変わらない。
- 予約している 2 本は表示側（データch が持つ1ライン分の先行 + 表示中のライン）。
- **実際に使っている余裕は `min_ready` = 25 で、負荷によらず一定**（CLUT4 でも RGB555 でも 25）。
  つまり 28 本すべてが要るわけではない。
- **浅くできるかは `scripts/test_pairs.py` で先に確かめられる**（C と同じ式でスケジューラを再現し、
  遅れを注入して underrun を数える）。ローレゾ専用経路は PSRAM 取得が無いので、
  遅延の源が1つ減る。**実機の前にホストで確かめること。**
- なお **モード6（320幅）ではスロットが 640B で足りる**ので、本数を変えなくても 20KB 戻る。

### 申し送り §3 の未決事項の決着（2026-09-27、ユーザー決定）
| # | 項目 | 決定 |
|---|---|---|
| 1 | RGB 出力 PIO の1画素サイクル数 | **調査で解決**。分周1 + 遅延スロットなので ÷14 も ÷15 も可（上記） |
| 2 | 24kHz の同期極性 | **H・V とも負論理**（31kHz と同じ） |
| 3 | 31kHz の 256 幅 | **512幅 + 左右64画素の余白**。ドットクロックは 25.2MHz のまま変えない |
| 4 | 31kHz の 320x200 | **縦2倍で400、上下40ライン余白**（60Hz を維持し、320x240 とテンポを揃える） |
| 5 | `vga_ring` の先行28ライン | **調査で解決**。リングの上限であって実測根拠ではない（上記） |
| 6 | 起動時の周波数選択 | 当面 31kHz 固定。必要になってから |
| ― | SRAM 警告の閾値 | **16KB**（`SGNANO_SRAM_WARN_BYTES` の既定のまま） |

## 静的解析と文書の基盤（T2・2026-09-27）
`ninja reports` で `build/reports/` に docx を揃える（`scripts/make_docs.sh`）。
**道具が無いものは飛ばして先へ進み、最後に「飛ばしたもの」を並べる**（止めない）。

### 道具立て — **`sudo` が使えないので、すべて user-local に入れた**
この環境の `sudo` はパスワードを求めるため apt が使えない。入れたものと入れ方:
| 道具 | 入れ方 | 版 |
|---|---|---|
| pandoc | GitHub の静的バイナリを `~/.local/bin` へ | 3.5 |
| doxygen | 公式のビルド済み Linux バイナリを同上 | 1.12.0 |
| lizard / sarif-tools | `pip3 install lizard sarif-tools` | 1.24.0 |
| cppcheck | ソースから `-DCMAKE_INSTALL_PREFIX=$HOME/.local` でビルド | 2.18.0 |

**まだ入っていない（`sudo` が要る）**:
- **LibreOffice** … Doxygen の RTF を docx にするのに要る。無い間は HTML と RTF まで。
  `sudo apt install libreoffice-writer`
- **graphviz** … Doxygen の呼び出し図。無くても文書は出る。`sudo apt install graphviz`
- 自前のレポート（SRAM・スタック・複雑度）は **pandoc で直接 docx にできる**ので影響なし。
  SARIF も **sarif-tools が python-docx で直接 docx を書く**ので LibreOffice は不要。

### 【重要】GCC が 10.3.1 なので `-fanalyzer` の SARIF は使えない
`-fdiagnostics-format=sarif-file` は **GCC 13 以降**。この SDK のツールチェーンは 10.3.1。
`-fanalyzer` 自体は 10 にもあるが、C の解析はまだ粗く、SARIF に載せられない。
**新しいツールチェーンを入れるまで保留**とし、静的解析は cppcheck で行う。
【追記】GCC 14.2.1 を入れて `-fanalyzer` を実施した（「GCC 14 への差し替え」の節。自前のコードの指摘は0件）。

### 成果物
| ファイル | 中身 |
|---|---|
| `sram.md` / `.docx` | 機能別の `.text`/`.rodata`/`.data`/`.bss`、大きい確保、`__in_flash` の候補 |
| `stack.md` / `.docx` | 関数ごとのスタック使用量（`-fstack-usage`）。**最大 560 B / core1 は 2KB** |
| `lizard.md` / `.docx` | 循環的複雑度。**CCN 15 超が 31 関数、最大は `handle_key` の 111** |
| `cppcheck.sarif` / `.docx` | 静的解析 |
| `doxygen/html/` | API 文書。`sram.html` / `isr.html` / `core1.html` が台帳 |

### `@sram` / `@isr` / `@core1` の台帳（申し送り 2.7）
`__not_in_flash_func` の **31関数すべて**に Doxygen のタグを付けた。Doxygen が一覧ページを作る。
- `@isr` … ライン割り込み（優先度0）か描画IRQ の文脈で動く（6件）
- `@core1` … core1 でも動く（描画は両コアが同じ関数を通る。23件）

### 【重要】台帳は `scripts/check_sram_funcs.py` が機械的に裏づける
**これまで objdump を目で見て確認していたものを、毎ビルド自動で確かめるようにした。**
ソースから `__not_in_flash_func(名前)` を集め、ELF のシンボル表と逆アセンブルを突き合わせて
(1) その関数が SRAM にいる (2) `bl` の飛び先がすべて SRAM、を確かめる。
- 実測（2026-09-27）: **対象31関数、うち16件はインライン化されてシンボルが残らない**
  （呼び出し元が SRAM にいれば問題ない）。残り15件は**すべて SRAM、飛び先も SRAM**。
- CMake の POST_BUILD に入れてあるので、**フラッシュ上の関数を呼ぶコードを書いた時点で気づける**。

### 整理の的（lizard の結果）
| 関数 | CCN | 行数 |
|---|---:|---:|
| `handle_key`（main.c） | **111** | 335 |
| `ufi_finish`（usbufi.c） | **96** | 294 |
| `main`（main.c） | **65** | 297 |
| `parse_pad`（usbpad.c） | 48 | 102 |
| `parse_mouse_report`（usbmouse.c） | 42 | 78 |
`handle_key` は画面モード体系（申し送り 2.2）を入れるときに必ず触る場所なので、
**T3 の前に表引きへ直すのが順当**。

### 静的解析の初回結果と、直したもの（2026-09-27）
cppcheck 2.18.0 を自前コードだけに当てた初回:
| 指摘 | 場所 | 対応 |
|---|---|---|
| `Condition 'k<4' is always true` | `main.c` の USB メモリ表示 | `USBMSC_MAX` が 4 なので冗長。上限を1つの定数にまとめた |
| `Variable 'n' is assigned a value that is never used` x2 | 同上 | `n +=` の結果を使っていなかった。**ついでに本当の不具合も直した**: `snprintf` は切り詰めても「書けたはずの長さ」を返すので、`buf + n` が範囲外になり得た。丸めを入れた |
| `%u requires 'unsigned int' but the argument is 'signed int'` | `audio.c` の `v < 4 ? 1 : 2` | `1u : 2u` にした |
| `unusedStructMember` x2 | `font.c` の `font_block_entry_t` | **意図的**（ROM の並びを表す）。理由を書いて `cppcheck-suppress-begin/end` で抑止 |
| `#error "sadd8/sel が使えない"` x2 | `lowres.c` | 解析側の設定漏れ。`-D__ARM_FEATURE_SIMD32=1` を渡して解決 |
**結果: error 0 / warning 0**（残りは「分岐が多くて全部は追っていない」という note のみ）。
- **`--output-format=sarif` は cppcheck 2.16 以降**。Ubuntu の apt 版では古いことがある。
- **抑止コメントは実際の宣言に合わせること。** `typedef struct {` を狙って書いたが実物は
  `typedef struct __attribute__((packed)) {` で、当たらずに素通りしていた。

### 【重要】ツールチェーンは SDK と別個に差し替えられる（2026-09-27）
**pico-sdk はツールチェーンを同梱していない。** `cmake/pico_pre_load_toolchain.cmake` が
`PICO_TOOLCHAIN_PATH` か PATH から `arm-none-eabi-gcc` を探すだけで、
**GCC の版数チェックも無い**（SDK 2.2.0 を `grep` して確認）。
したがって SDK 付属の 10.3.1 を残したまま、新しいものを併用できる。
- 取得: `scripts/fetch_toolchain.sh [14.2.rel1]` が Arm 公式のものを `~/toolchains/` へ入れる（**sudo 不要**）。
- 使用: `cmake -DPICO_TOOLCHAIN_PATH=~/toolchains/arm-gnu-toolchain-14.2.rel1-.../bin ...`
- **必ず別のビルドディレクトリで構成すること**（`build_*`）。`build/` を混ぜると
  「どちらのコンパイラで作った成果物か」が分からなくなる。
- `-Dpicotool_DIR=$PWD/build/_deps/picotool` を付ければ picotool の再ビルドは要らない
  （picotool はホスト用なので、ターゲットのツールチェーンとは無関係）。

#### `-fanalyzer` の構成
`-DSGNANO_ANALYZE=ON` で自前のソースにだけ `-fanalyzer -fdiagnostics-format=sarif-file` を付ける
（SDK と TinyUSB は別ターゲットなので元から対象外）。**GCC 13 未満ならテキスト診断に落とす**。
まとめて走らせるのは `scripts/analyze_gcc.sh`（翻訳単位ごとの SARIF を1つに束ねて docx にする）。

### GCC 14 への差し替え — **実測でサイズ中立**（2026-09-27）
`scripts/fetch_toolchain.sh` で Arm GNU Toolchain **14.2.Rel1（GCC 14.2.1）**を入れ、
`build_gcc14/` で構成して比べた。**SDK 側の変更は一切不要**だった。

| | SDK 付属 GCC 10.3.1 | GCC 14.2.1 | 差 |
|---|---|---|---|
| RAM（配置の末端） | 521,084 B | **521,096 B** | **+12 B** |
| 残り | 3,204 B | **3,192 B** | -12 B |
| ELF `.text` | 123,260 | 122,996 | -264 |
| ELF `.data` | 33,304 | 33,496 | +192 |
| ELF `.bss` | 355,196 | 355,208 | +12 |
**残り 3KB しかない状況でも、差し替えで溢れることはない。**
- **展開に時間がかかる**（720MB、数分）。`cc1` が出るまでコンパイラは使えないので、
  `arm-none-eabi-gcc --version` が通っても早合点しないこと
  （`cannot execute 'cc1'` で構成に失敗した）。

#### `-fanalyzer` の結果（GCC 14、`scripts/analyze_gcc.sh`）
**自前のコードの指摘は 0 件。** 出た7件はすべて SDK / TinyUSB のもので、
`mutex.c` の buffer overflow、`usbh.c` の null 参照、`hid_host.c` の未初期化値など。
- **SDK のヘッダは自前の翻訳単位へインライン展開されるので、対象を自前ソースに絞っても
  SDK 由来の指摘が混ざる。** 束ねるときに URI で落とし、重複も一意化している
  （`KEEP_SDK=1` で残せる）。
- GCC は翻訳単位ごとに `.sarif` を吐くので、1つにまとめてから docx にする。

### 【重要・2026-09-27】`.map` のサイズを素直に足してはいけない
`sram_report.py` が GCC 14 のビルドで `.rodata` を **50,079 B** と報告したが、
ELF の `.data` は 33,496 B しかなかった。**約2倍に数えていた。**
- 原因は **マージされる文字列セクション**（`.rodata.<関数名>.str1.4`）。
  `.map` には**マージ前の大きさ**が載り、実際には重なって配置される。
  見分ける目印は、連続する2件が**同じアドレス**に載っていることと、
  `(size before relaxing)` の行。
- → **次のエントリまでのアドレス差で実寸を出す**ようにした（`effective_sizes()`）。
  直後に ELF のセクションサイズと突き合わせて、整列のすき間ぶんの差に収まることを確認する。
- **GCC 10 でも同じ誤りは起きていた**（26,388 → 正しくは 26,221）。桁が小さくて気づけなかった。
  **新しい環境で桁が変わって初めて露見した。**

### 指摘の増加を見張る（`sarif diff`）
`docs/baseline/cppcheck.sarif` を基準に、`ninja reports` のたび `sarif --check warning diff` で比べる。
**増えていればスクリプトが異常終了する**（`build/reports/cppcheck_diff.txt` に差分）。
増やしてよいと判断したときだけ `bash scripts/make_docs.sh --baseline` で基準を更新する。

### Doxygen の docx 化は問題なし（2026-09-27、`libreoffice-writer` 導入後）
【訂正 2026-10-25】ソースにシフト JIS に無い字が増えて RTF が崩れ、docx はやめた（この文書の末尾の同じ日の節）。
申し送り 2.7 の「**要確認**: 日本語 RTF の文字化けの有無」は **問題なし**。
`refman.docx`（9.6MB）に日本語 20,550 文字が残り、`@sram` 台帳の見出し
「SRAMに置く関数」もそのまま出る。HTML 経由の代替案は不要だった。
`graphviz` も入ったので `HAVE_DOT` / `CALL_GRAPH` / `CALLER_GRAPH` を有効にし、**呼び出し図 863 枚**。


### 【重要・2026-09-27】2のべき乗の整列は、手前が数バイト増えるだけで数KB持っていく
printf を1行足しただけで **SRAM が 5,108 バイト足りなくなった**。
原因は `stream_buf` が **8192 バイト整列**（DMA のリングの要求）で `.bss` の先頭に置かれること。
`.data`/`.rodata` が少し増えると `.bss` の開始がずれ、リンカが整列に合わせて**最大 8KB の詰め物**を入れる。
- **これが「SRAM の残りが 3,204 バイトから動かない」ように見えていた正体。**
  詰め物が増減を吸収していたので、変更しても残量が変わらなかった。
- **対処1**: `AUDIO_STREAM_FRAMES` を 2048 -> **1024**（4KB、約23ms）。
  バッファ 4KB と詰め物の最悪値 4KB を取り戻した。CD の経路は PSRAM に40秒ぶん貯めてから
  1セクタ（588フレーム）ずつ渡すので 23ms で足りる。
- **対処2**: `scripts/sram_report.py` が**出力セクションの境目の詰め物を出す**ようにした。
  実測で `.bss の手前に 4,088 B` と出る。`. = ALIGN()` は `.map` に明示のエントリを残さないので、
  セクションの先頭と前の終端の差で見るしかない。
- **読み方**: 詰め物が 4,088 B あるということは、**`.data`/`.rodata` はあと 4KB ほど
  増やしても `.bss` の位置が動かない**（その先で一気に効く）。



### SRAM の 4KB の崖をもう一度踏んだ（2026-10-03）
`usbkbd.c` の分割（+0.6KB）と `ufi_finish` の書き直し（+0.9KB）で `.data` の終わりが 0x2002A000 を 636 B 越え、
`.bss` の先頭の `stream_buf`（4KB 整列）が 0x2002B000 へ押し出されて **2,720 B 溢れた**。
- **対処**: 熱い経路から読まない定数をフラッシュに置いた（`__in_flash`）。タイミング表 `table`（576 B）、
  キーボードの文字の表 `us_tbl`（256 B）・`jis_diff`（51 B）。`check_sram_funcs.py` が「フラッシュを指す定数を熱い経路が持っていない」ことを確かめる。
- **【落とし穴】無名の構造体の配列では、属性を型の後ろに書くと型にかかって効かない**（`-Wattributes` の警告だけが出る）。
  変数名の後ろに書くこと: `static const struct {...} jis_diff[] __in_flash("kbd") = {...}`。
- 結果: 残り 1,376 B、**詰め物 764 B**（次に溢れるまでの余裕）。

### T7 の残り: XIP ビルドで CD 再生（2026-10-03）— **完了条件をすべて満たした**
光学ドライブ `1132:4511` + オーディオ CD。`'` でトラック1を30秒（先に 2250 セクタを PSRAM へ貯めてから鳴らす）。
| | XIP（FB なし） | 既定（FB あり・全体 SRAM） |
|---|---|---|
| 先読みの速さ 平均/最大 | 60 / 73 KB/s | 60 / 73 KB/s |
| 再生 | 30秒最後まで、75 sectors/s、44100 frames/s | 同じ |
| CD の underruns | **0** | **0** |
| 映像 underrun / fifo_stall / recover | 0 / 0 / 0 | 0 / 0 / 0 |
- 先読みの速さは USB のバルク転送の上限で決まっていて、XIP でも落ちない。
- XIP の先読み中の `pair_max`（モード5）は 56〜58/58〜64µs で、CD を使わないときの XIP（57/63µs）と同じ。
- **測定中にユーザーが USB キーボードで操作していた**（`f`、`v`）。`[kbd] key` の行で分かる。
  【追記】**画面をモード0（表示なし）にするための操作**だった（ユーザーの説明）。CD 再生の結果には影響しない。
  画面モードが変わると `pair_max` が大きく動くので、比べるときは `[scr]` と `[kbd] key` の行も確かめること。
- この測定の1回目の書き込みで、また**ファームが起動しない**症状が出た（積み残しの3番）。そのときは GP0 を読んでいなかった。
  判定の道具（一時ファイル）は、起動していないと分かったら GP0 の入力レベル・パッド・IO の状態と両コアの PC も読むようにした。

### 表示用メモリのアリーナ（vmem、2026-10-03）— SPEC_vram_alloc.md の P1〜P4
**狙い**: SRAM の残りが 1,376 B、4KB の崖まで 764 B しかなかった。表示用のバッファを、使うときに・使う大きさで置けるようにする。
申し送り 2.6 の「アリーナは採らない」は、最大の消費をモード5 が決めるという点ではいまも正しい。狙いは「大きさを選べる」と「崖を消す」。

#### つくり（`src/mem/vmem.c`）
- 範囲は `__end__`（`.bss` の終わり）〜 `__HeapLimit`（SRAM の末尾 0x20080000）。リンカのヒープ領域をそのまま使う。
  スタックは SCRATCH_X / SCRATCH_Y にあり、この範囲には何も無いことを確かめた。`malloc` を呼ぶ関数も無い（`_malloc_r` も）。
  念のため `--wrap=_sbrk` で sbrk を常に失敗させる。
- **固定**は上から積み下げる（末尾は 64KB 境界なので、4KB 整列の `stream_buf` が詰め物なしで末尾に載る）。
  **面**は下から先頭適合で取り、返したら隣の空きと結合する。管理表は静的な32件。
- 見張りの語: 面はブロックの後ろ、固定はブロックの**下**に置く（後ろに置くと、4096 B のブロックが 4100 B になって
  4KB 境界から1つ下がり、4KB 近く無駄にした。ホスト試験で見つけた）。2つ目以降の固定は 整列-4 B まで余りが出る。
- 実機の配置（既定）: 固定 = audio stream（0x2007F000、4KB 整列）・precomp・wave、面 = テキスト 50KB・ローレゾ 4ブロック。

#### 確かめ方
- `scripts/test_vmem.py`: 乱数で確保・解放を 20,000 回。区画が隙間なく覆う・重ならない・整列・中身・見張り・全解放後に1区画。
- `scripts/test_all.sh`: ホスト試験をまとめて回す（C7 で `test_timing` / `test_pio_gen` を回し忘れ、壊れていたのに気づかなかったため）。
- `check_sram_funcs.py`: 熱い経路から `vmem_*` を呼ばないことも見る（copy_to_ram では番地で見分けられないので名前で）。

#### P1 単独ではリンクできない
P1 のコミットだけでは SRAM が 3,508 B 溢れる。アロケータのコードぶんで 4KB の崖を越え、それを消すのが P2 だから。
P1 と P2 は一緒に作って確かめた。**bisect のときは P1 を飛ばすこと。**

#### 切り分けで外れたもの（アロケータを入れてから再起動が出た件）
アロケータを入れたビルドで、起動直後に光学ドライブを認識したところでウォッチドッグの再起動が続いた。
音源のバッファの置き場所（音源を外しても出る）、malloc（呼び出し元なし）、アリーナとスタックの重なり（無い）を順に潰したが、
**変更前のビルドでも同じ手順で再起動した**（2回目で2回）。アロケータとは無関係の、元からの USB の問題（usb.md）。

### 【観察】ブートROM で止まった回の GP0（2026-10-03）
上の再起動のあとブートROM でロックアップした回に、止めずに読んだ値: `SIO GPIO_IN` の bit0（GP0）= **0（Low）**、
`PADS_BANK0 GPIO0` = `0x116`（**PDE=1、プルダウン有効**）、`IO_BANK0 GPIO0_CTRL` = `0x1F`（機能なし）。
リセット直後の GP0（PSRAM の CS）がプルダウンで Low になり、ブートROM のフラッシュ読み出しの最中に PSRAM が選ばれたまま、
という仮説と合う。**基板に GP0 のプルアップ（例 10kΩ）を足せば直る見込み。**

### PSRAM のアリーナ（2026-10-04、SPEC_vram_alloc.md の P6）
`vmem.c` を「アリーナ1つぶんの構造体（`arena_t`）」で動くように書き換え、SRAM 用（`vmem_*`、従来どおり）と
PSRAM 用（`pmem_*`）の2つを持つ。PSRAM 側は見張りの語を書かない（PSRAM への CPU の書き込みには時間帯の決まりがある）。
- 起動時に `psram_init()` が通れば `pmem_init_default()`（PSRAM 全体 8MB、非キャッシュ窓）。
- 決め打ちだった3か所を置き換えた: **FB**（600KB、固定、上から。0x1576a000）、**CD の先読み**（7,056,000 B、再生のあいだだけ）、
  **アプリ時間の書き込み試験**（256KB、試験のあいだだけ）。
- 実機: FB の表示（モード2）`underrun=0 fifo_stall=0`、書き込み試験 61.1 MB/s（従来どおり）、CD 再生で 7MB を取り、止めると返る。
  Ctrl-A で `[pmem]` 一覧も出る。ホスト試験 `test_vmem.py` に PSRAM 側の確認を足した。
- SRAM の実行時の空きは **2,760 B**（2026-10-04、モード5）。2台目のドライブの状態・PSRAM の管理表・この数日のコードのぶん減った。

### ログの文字列をフラッシュに残す（2026-10-04、`SGNANO_STR_IN_FLASH`、既定 ON）
SRAM の実行時の空きが 2,760 B まで減ったので、RAM に載っていた `.rodata`（約33KB）のほとんどを占める
**ログの文字列（`*.str1.*`）をフラッシュに残す**ようにした。`copy_to_ram` のリンカスクリプトは `.rodata` を丸ごと RAM へ写すが、
構成のときに SDK のスクリプトを読み、フラッシュに残す `.rodata` の節に1行足した写し（`build/memmap_sgnano.ld`）を作る
（リンカは最初に当てはまった節に置く。SDK のスクリプトが変われば構成で止まる）。どのファイル・関数をフラッシュへ置くかは
`ld/placement.cmake` にまとめてある（2026-10-29 に CMakeLists.txt から移した）。
- **映像まわり（`src/video/`）と画面のステータス（`status.c`）の文字列は RAM に残す**（`EXCLUDE_FILE`）。
  毎フレームの表示や画面モードの切り替えで読まれるため。
- 熱い経路（割り込み・描画）が文字列を読まないことは `check_sram_funcs.py`（フラッシュを指す定数）が見張る。
- 実測（FB を表示するモード2、詳細ログを大量に出す試験。1回目 / 2回目 / 3回目の fifo_stall の累計）:

  | 置き方 | SRAM の使用 | 切り替え時 | 大量のログ |
  |---|---|---|---|
  | 全部 RAM（従来） | 257,420 B | 0 | 0 / 0 / 0 |
  | 全部フラッシュ | 227,308 B | 8 | +13, +2, +2 |
  | **映像・ステータスを除いてフラッシュ** | **234,508 B** | 2 | +12, 0, 0 |
  | さらに `src/app/` も除く | 237,612 B | 3 | +14, 0, 0（効果なし） |
- 結論: **普段（毎秒のログだけ）は FB 表示中でも30秒間 0**。FB を表示しているときに USB の診断（`U` など）を
  **初めて**出すと十数ライン乱れる（2回目以降はキャッシュに載るので0）。NONE のモード（既定のモード5 など）では出ない。
  切り替えのときの数回は、グリフの展開がフォント ROM（フラッシュ）を読んでキャッシュから文字列を追い出すためと見ている。
- 実行時の空き（モード5）: **2,760 B → 26,056 B**。全部 RAM に戻すなら `-DSGNANO_STR_IN_FLASH=OFF`。

### 【2026-10-04】アプリの作業領域（`app_alloc`、`SPEC_vram_alloc.md` の項目7）
- `src/mem/appmem.c` / `appmem.h`。アリーナから**面と同じ寿命**（返すまで持つ）でアプリに配る口。
  - `app_alloc` / `app_free` は SRAM のアリーナ（`vmem_*`）、`app_alloc_psram` / `app_free_psram` は PSRAM のアリーナ（`pmem_*`）
  - アプリが取ったもの（最大16個）を記録し、`app_free_all()` でまとめて返せる（アプリを切り替えるとき・返し忘れの掃除）。
    取った側と違う関数で返そうとしたら断る（SRAM のものを `app_free_psram` で返すなど）
  - 失敗は NULL。黙って小さくしない
- 呼ぶのは core0 の冷たい経路だけ。`check_sram_funcs.py` の見張りを `vmem_*` から `pmem_*`・`app_alloc*`・`app_free*` まで広げた
- PSRAM の領域へ CPU が書くのは、FB を表示しているときはアプリ時間だけ（既存の決まりのまま）
- 試験: ホスト（`test_vmem.py` に確保・整列・取り違え・まとめて返す・上限を追加）と実機の **Ctrl-W**
  （SRAM 8KB と PSRAM 64KB を取り、書いて読み返し、一覧を出して全部返す。モード5 で `0 mismatches`、返したあとアリーナの空きが元に戻る）。
  Ctrl-A の一覧の末尾にもアプリが取ったものを出す

### 【2026-10-04】「ファームが起動しない」（積み残し）を `W` で再現した
- `W`（わざと止めてウォッチドッグで再起動）を繰り返すと、数回に1回、**両コアがロックアップ**（DHCSR の S_LOCKUP、PC=0xFFFFFFFE）
  したまま戻らない。UART には何も出ない。そのとき **GP0（PSRAM の CS）は Low、パッドはリセット直後の既定値（プルダウン、`PADS0=0x116`）**。
  仮説（CS が Low だと PSRAM がブートROM のフラッシュ読み出しに応答する。PSRAM は QPI モードのまま残っている）どおりの値
- **ソフトでは防げなかった**: GP0 をプルアップにし、ウォッチドッグの再起動でパッドをリセットしないよう `PSM_WDSEL` から RESETS を外し
  `RESETS_WDSEL` で「パッド以外」を指定したが、再起動のあとはパッドも `RESETS_WDSEL` も既定値に戻っていた（チップ全体のリセットか
  ブートROM がリセットしている）。この変更は取り除いた。**基板で GP0 にプルアップ（10kΩ 程度）を足すのが筋**
- 観測の注意: OpenOCD は接続するだけで C_DEBUGEN を立て、TinyUSB の assert が BKPT で core0 を止める（PC が 0xFFFFFFFF ばかりになる）。
  止めずに PC を読むときは、接続直後に `poll off` してから両コアの DHCSR に `0xA05F0000` を書く
- `scripts/flash_swd.sh` は書き込み・リセットの前に `` ` `` を送って CD の再生を止める（`docs/notes/storage.md`）

### 【2026-10-04】キー・診断・FAT のコードをフラッシュに残す（アリーナ +24KB）
- モード5 のアリーナの空きが約 8KB まで減っていた（PNG の表示などでコードと変数が増えた）。もう少し増えると起動時にモード5 の面が開けなくなる
- **キーや USB メモリのマウントのときにしか動かないコードを、ファイルごとフラッシュに残す**（当時 `CMakeLists.txt`、2026-10-29 から `ld/placement.cmake`）:
  `usbmsc.c` `usbfat.c` `usbdiag.c` `usbiso.c` `keys.c` `keys_usb.c` `app/diag.c` `testpattern.c`（`.text` 約 22KB）。
  毎フレーム・毎回の USB の処理・CD の再生中・パッドのレポートごとに動くもの（usbufi / usbhw / usbpad / audio / lrdemo / 映像 / status）は RAM のまま
- 【注意】リンカの書き方: ファイルごとに `(.text*)` を付ける。`a.o b.o(.text*)` と並べると a.o は全部の区画（.bss・.data まで）がフラッシュ側に
  入る（最初の版でそうなり、.bss が 3.5KB 減った。書き換える変数がフラッシュに置かれる）
- PNG の解読の状態（パレット・ハフマンの表、約 2.3KB）を .bss から解読のときだけ取る作業用メモリへ移した
- 結果: アリーナ 271,508 -> 295,736 B（+24.2KB）、**モード5 の実行時の空き 7.9KB -> 32.0KB**
- FB の表示中（モード2）にこれらのキーを押したときの fifo_stall: 変更前 29 回 / 変更後 31 回（`U` `Ctrl-A` `#` `(` `Ctrl-B` x2 `%`）。
  乱れの元はもともとフラッシュにあるログの文字列で、コードを移したことによる増え方はほとんど無い。どちらも初回だけ（キャッシュに乗ると出ない）

## 【2026-10-05】ファイラーのためのコードの置き場所と SRAM
- **決まり**: FB を表示したまま**アプリ時間の外で動くもの**（USB の完了コールバック・開始後の長い仕事）は SRAM。**アプリ時間にだけ**動くもの、
  **テスト用アプリ（FB を表示しないモード）でだけ**動くものはフラッシュでよい（アプリ時間は描画が PSRAM から取り出していない）
- **SRAM が足りなくなった**: `usbfat`（29KB）・`usbmsc`（10KB）・`png.c`（9KB）・ファイラーの SRAM 側を SRAM に置いたら、アリーナが 297KB -> 225KB に
  縮み、テスト用アプリのローレゾ面（182KB）が開けなくなった。次の3つで 265KB まで戻した（テスト用アプリでの空きは約 1.8KB）
  1. **`fputs` をやめる**: ログを出すのに `fputs(buf, stdout)` を使ったら、newlib の stdio 一式（`fvwrite` `findfp` `fflush` `makebuf` …）と
     `malloc` / `realloc` / `free` が引き込まれ、約 8KB が SRAM に入った。pico の `printf("%s")` で出す
  2. **関数ごとにフラッシュへ**: `USBFAT_COLD` / `USBMSC_COLD`（`__attribute__((section(".text.flashcold.*"), noinline))`）を付け、リンカの並びに
     `*(.text.flashcold*)` を足した（`noinline` が無いと SRAM の呼び出し元に取り込まれる）。`usbfat` で約16KB、`usbmsc` で約6KB
  3. **テスト用アプリ専用のファイル**（`lrdemo.c`・`audiotest.c`）を `.rodata` ごとフラッシュへ（約10KB）
- **完了コールバックから呼ばれうる関数に印を付けない**: `vbr_done`（USB の完了）から呼ぶ `write_begin` に付けたら、一覧を読むたびに表示が乱れた
- **確かめ方**: 逆アセンブルで、RAM にある veneer（`__xxx_veneer`、フラッシュへ飛ぶ中継）と、それを呼ぶ RAM の関数を並べる。
  ```
  arm-none-eabi-objdump -d build/sgnano.elf > dis.txt
  # 行頭の <関数>: で今の関数を覚え、bl / b.w の飛び先が "__*_veneer" なら（呼び出し元, 飛び先）を出す
  ```
  呼び出し元がアプリ時間か、テスト用アプリでだけ動くかを1つずつ確かめる

## 2026-10-10 リファクタリング（TCP を載せる前）: SRAM・フラッシュの点検

- 依頼（ユーザー）: TCP を載せるため、一度リファクタリング。フラッシュの使用量・SRAM の構成も点検
- フラッシュ: 書き込む像 512KB（使える 8MB の 6.1%）。余裕は十分。制約は SRAM（テスト用アプリの空きが 860 B だった）
- 静的な SRAM を減らした（257,020 -> 246,752 B、lwIP を足して 247,336 B）:
  | 何を | 減った量 | どうした |
  |---|---:|---|
  | ファイラーの状態（ドライブの一覧・パス・選び直す名前・打った名前・開くパス・TOC） | 2.1KB | PSRAM の構造体（`filer.c` の `PS`、マクロで名前はそのまま） |
  | 試験模様の 1 ライン分のバッファとパレット | 1.8KB | FB へ 32bit ずつ直接書く・パレットは描く間だけ PSRAM から |
  | 区画の表（`usbpart.c` の `D`） | 1.6KB | PSRAM（初めての usbpart_poll で取る） |
  | libc の `qsort` | 1.4KB | 自前のシェルソート（`fio.c`） |
  | ゲームパッドのキー・診断からしか呼ばない関数 8 個 | 1.0KB | `USBPAD_COLD`（フラッシュ） |
  | 光学・FDD の受け場 2 台分 | 2.4KB | 1 つを共有（`ufi_shared`）。塞がっていれば 2ms 後へ回す |
- 【踏んだもの】ファイラーの状態を PSRAM に移したら、PNG を開いたフレームのアプリ時間が 1,933µs になり underrun が出た（初回だけ）。
  主因は `fpng_open` がアプリ時間の中で出していた長いログ（約 1.6ms）。もともと窓ぎりぎりだったところへ PSRAM の読み出しが足された -> `fio_log` に溜めて開始後に出す
- 試験模様の見た目（モード 2〜4）は、モードを一巡して落ちないことまでしか確かめていない（画面はユーザーに見てもらう）
- 光学・FDD の受け場の共有は、光学ドライブも FDD もつながっていない日だったので、実機の確認が残っている

## 2026-10-17 SRAM の残りの最適化とリファクタリング
**SRAM**: テスト用アプリでの実行時の空きが 1,820 B まで減っていた（ローレゾ面 182KB を開いた状態）。
- `scripts/find_sram_movable.py`: 逆アセンブルから、SRAM の関数のうち「直接の呼び手（bl・b.w・条件つきの分岐・cbz も）がすべてフラッシュの関数か、同じく移せる関数」で、
  「読み込まれるセクションに番地 | 1 の語が無い（関数ポインタ・割り込みの表に無い）」ものを、変わらなくなるまで広げて出す。根は `main`（crt0 が番地で呼ぶ）と `app_time`、
  ずっと回る `app_loop`・`loop_once`・`app_yield`、`__not_in_flash_func` の台帳のものは移さない
  - 初めは 0 個だった: `main` が `boot` と戻らない繰り返し（`app_loop`）を取り込んでいた（`app_loop` を `noinline` にして分けた）、`main` が「番地を取られている」になっていた、
    デバッグ情報のセクションまで番地を探していた、条件つきの分岐（strstr -> two_way_long_needle）を読んでいなかった
- 移したもの（`ld/placement.cmake` の `SGNANO_COLD_FUNCS`、関数の名前でフラッシュへ）: 起動時だけ（`main` `vga_init` `text_init` 時計・電圧・UART・PSRAM・アリーナ・フォントの初期化など）、
  アプリ時間だけ（`app_time` `video_start_frame` `text_refresh_until`）、手で確かめたもの（起動直後のバナー `app_banner` と、そこからだけ・テスト用アプリのキーからだけ呼ぶ
  `vga_print_info` `vga_timing_print_table` `vga_timing_print` `render_print_info` `app_report_start`）と、それらの文字列
- 結果: 静的な SRAM 256,056 -> 245,688 B（-10,368 B）、テスト用アプリの空き 1,820 -> 12,188 B。アプリ時間の最大 297 -> 285µs（遅くならない）。F10 の行き来 8 回で underrun 0
- 外せなかったもの: printf の浮動小数の書式（`_ftoa` `_etoa` と倍精度の足し算、約 3KB）は毎秒の `[run]` 行などで使う。USB の機器をつないだときの関数（`usbpad_mount` 2.9KB・
  `usbmouse_mount`・TinyUSB の列挙）は、つないだときに FB を表示したままフラッシュを走らせることになる（ライン が乱れる）ので、移すならユーザーと決める
- 一度だけ、Ruby の入力にキーが続けて入った順番のあと、テスト用アプリから戻るときに underrun 352・作り直し 2 回を見た。同じ順番・F10 の行き来を繰り返しても 0（積み残しの仲間と見ている）

**リファクタリング**（判定の順と振る舞いは変えない）:
- `filer_key`（CCN 134）を段ごとに: `modal_key`（確かめ・途中の窓）-> `view_key`（一覧の代わりの画面）-> `overlay_key`（重ねる窓・共通のキー）-> `list_key`（一覧）。
  F2 / F3 / F6 / F7 の共通の扱いは `screen_key`、重ねる窓は `show_only` にまとめた。キーの一覧表（`make_keysheet.py`）は目印のコメントの範囲を読むようにし、キーの並びが前と同じことを確かめた
- `filer_app_time`（72）を段ごとに（CD・EP の一覧・長い仕事の結果・画面の受け持ち・一覧の取り込み・描き直し）。コピーと ZMODEM の結果の知らせは `job_done` にまとめた
- ZMODEM（`zm_receive` 60・`zm_send` 62）: 受け手は見出しの種類ごとの関数（状態は `rx_t`）、送り手は起こす・ファイルの頭・流す・終わりの関数（状態は `tx_t`）に。
  取り消しの扱い（`tx_stopped`）と送り直しの位置の扱い（`tx_rewind`）は 1 つずつに。ホスト試験 11 通りで中身が同じ。最大 CCN 21
- 静的解析: cppcheck は誤り 0、警告は基準（`docs/baseline/`）より多い（基準を作ったあとに足した exFAT・NTFS・Ruby などの指摘。今回のリファクタリングで増えたものではない）

## 2026-10-17 静的解析の指摘を片付けた・tick の分周が 0 のまま動く件
- cppcheck の警告を 72 -> 0（基準 `docs/baseline/` と同じ）。主なもの:
  - `src/fs/ntfs.c` の未定義の動作（壊れた・細工された NTFS で起こり得る）: クラスタの大きさの値 0x81..0xE0 で `1u << (256 - 値)` が
    32 以上ずらす、MFT・索引のレコードの大きさの負の値が -32 以下で同じ、データの範囲の位置の差分が 8 バイトのとき `1 << 64` と
    符号つきの左シフトのあふれ、長さが大きいと `len << clus_shift` が 64 ビットで回り込み「2TB を越える」の確かめをすり抜ける。
    どれも先に範囲を確かめて断る形にした。`ntfs_w.inc` の `FS_SEC << clus_shift` は 64 ビットで。順番号・USN の 0 を飛ばす書き方を素直に
  - `scripts/test_fs.py` を UBSan（`-fsanitize=undefined`、見つけたら止める）で組むようにし、壊れた NTFS を 6 通り開く試しを足した
    （直す前のコードでは 5 通りで UBSan が止める）
  - 使っていないメンバー・読まない代入・const を付けられるポインタ（`fclock.c`・`fzm.c`・`fedit.c`・`rbfh.c`・`src/fs/` など）。
    `rbmachine_mrb.c` の範囲外の指摘（`mrb_raise` が戻らないのを解析の道具が知らない）は `& 1` で、`text_get` の未初期化は 0 で埋めて
  - `make_docs.sh`: `third_party`・`build_mruby`（取り込んだもの）と `constParameterCallback`（mruby のメソッドなど、関数ポインタに渡すので型を変えられない）は見ない。
    `rbrun.c` のアセンブラの関数は `cppcheck-suppress-begin`
- **tick の分周が 0**: リセットのあと core0 が `tusb_time_delay_ms_api` から戻らず、UART も止まった。TICKS（0x40108000）の CYCLES が
  6 つとも 0（CTRL は 3）で、0 は 512 として働くので 1µs の tick が 12MHz / 512 = 23kHz（TIMERAWL が約 1/43 の速さ）。
  `configured_freq[clk_ref]` は 12MHz で正しく、SDK の `runtime_init_clocks` は 12 を書くはずなので、0 になった仕組みは未特定
  （続けて `--reset` した 1 回目も 0、その後 7 回は 12）。ウォッチドッグの tick も同じく遅くなるので再起動もしない。
  `main` の始め（`ticks_check`、`clocks_setup` の `sleep_ms` より前）で確かめ、違えば `tick_start` で直してログに出す
- 開始後の経路からフラッシュの関数を呼んでいた所: `filer_work` が毎周 `fzm_work`（ZMODEM、フラッシュ）を呼んでいた。SRAM の印 `fzm_want` を見てから呼ぶ。
  ほかに呼び出しの図で見つかったのは、めったに通らない `ctrl_abort_now`（制御転送の打ち切り）・`usbata_bot_reset`、FAT の書き込みの `w_data_step`、
  `app_yield` から呼ぶ `app_time`（アプリ時間の中なのでよい）

## 2026-10-17 core1 の RTOS 化で見つけたこと
- **pico-sdk 2.2.0 の `multicore_doorbell_claim_unused` は core1 だけで取ると同じ番号を返す**（`multicore_doorbell_claim_under_lock` が core1 の印を
  `doorbell_num + 1` のビットで見ている）。2 つ取ったら両方 7 になった。両コアの分（マスク 3）で取れば別の番号になる（`render.c`）
- **HDD（JMS578）をつないでいると、`flash_swd.sh` の直後の数秒はプローブから読めない**（`check_cores.sh` が `?->?`、`Target not examined yet`）。起動しないのではない。
  5 秒おいてから確かめれば 4/4 で ok。前のファームでも同じ
- **アプリのタスクのスタック**は SCRATCH_X（以前の core1 のスタック、4KB）。core1 の割り込みは 1KB の別のスタック（`core1_msp`）。最高水位は `stack_high_water` が SCRATCH_X で見る
- 静的な SRAM: RTOS を入れ、テスト用アプリをビルドから外して 247,360 B（RTOS の前は 245,688 B）

## 2026-10-23 切り分けの道具（プロファイル・全経過の USB のログ・前の版との比べ）
- **プロファイル** `scripts/mbprof.py [elf] [-n 周期の数]`: M33BEATOS の数える役が 1 秒ごとに残す各タスクの数（走り出した回数・自分で数えた回数・走った割合・状態）を、
  SWD で止めずに読んで表にする（`SPEC_m33beatos.md`）。デッドロック・飢えはこれで見える（USB 99.5%・アプリ 0% で、`tuh_task` が抜けないのが分かった）
- **全経過の USB のログ**: `cmake -B build_usbdiag -DSGNANO_USB_DEBUG=2 -DSGNANO_USB_LOG_BYTES=16384`。RAM のログ（`usblog_keep`、16KB）を SWD で止めずに読み出す
  （作業用の `ulogread.py`）。全経過の段は量が多く、起動から 3 秒で一周する。見張りの生存確認が毎秒ログを埋めるので、列挙を見るなら起動から 3〜10 秒の間に何度か読む
- **ウォッチドッグを切った診断用のビルド**: `-DSGNANO_WATCHDOG_MS=0`（`build_nowdt/`）。止まったまま待たせて、両コアの PC・タスクの状態・ロックの持ち主を読む
- **前の版との比べ**: `git worktree add` で前の版を別のフォルダに組み（`build_mruby` は記号のリンクで共有）、交互に書き込んで同じつなぎ方で起動して比べる。
  条件を 1 つずつ動かす（ソフトの問題か、機器の状態か: 今日は固まった USB メモリ・ドックの LAN の石・タブレットの状態が、それぞれ別の日の版でも同じ形で出た）
- **書き込みの道具が UART の口を開いたまま固まる**ことがある: 機器をつなぎ直したときにプローブも USB の上でつながり直し、`stty` が `usb_kill_urb` の中で止まって殺せない。
  Windows 側で `usbipd detach` / `attach` し直す
- ホストの試しに gcc の引数を足す: `SGNANO_HOST_CFLAGS`（`test_msc2048.py`・`test_fs.py`・`test_part.py`・`test_fat_write.py`）
- `pkill -f` / `pgrep -f` のパターンは、自分のシェルのコマンドの文字列にも合うので、自分ごと止めることがある。番号で止める

## 2026-10-24 止まったときの記録（src/app/crash.c）
- Doom の E1M1 で再起動した（ユーザー報告）。前の起動の終わり方は SRAM の `boot_reason`・`boot_crumb`（`report.c`）を SWD で読めて、ウォッチドッグ（reason 0x1）・
  アプリのループは段階 2（描画の終わりの待ち・usb_lock の取り直し）・USB のタスクは `tuh_task` の中・TinyUSB の包み 0x66（`hcd_edpt_xfer`）の中だった。
  中の待ち（`usbhw_epx_bulk_in`）はウォッチドッグを撫でるので、SDK の HCD の panic か HardFault で止まったと見ている。UART のログを記録していないと panic の文は消える
- **記録を残す**: panic（SDK の `panic()`、CMake の `PICO_PANIC_FUNCTION=sgnano_panic`）・HardFault（両コア、`isr_hardfault` を置き換え。積まれた枠から PC・LR）・
  M33BEATOS の誤り（`mb_port_panic` / `mb_port_fault`）のとき、種類・コア・走っていたタスク・文・PC・LR・CFSR・HFSR・MMFAR・BFAR を
  `__uninitialized_ram` の `crash_keep` に書いて止まる（ウォッチドッグが再起動する）。次の起動で `[boot] ** the previous boot stopped: ...` と出し、
  `crash_last` に写す（SWD で読める）。遠隔コマンド `PANICTEST` で試せる（わざと panic、実機で記録が出るのを確かめた）

## 2026-10-25: Doxygen の docx をやめ、HTML だけに

- **起きたこと**: `refman.docx` が作られなくなった（LibreOffice が「source file could not be loaded」）。`refman.rtf` の括弧が 13 個閉じていなかった。
- **わけ**: Doxygen 1.12 の RTF は言語ごとのコード頁で書く（日本語は 932 = シフト JIS）。シフト JIS に無い字（`µ`・ハングル・アクセントつきの字など。src の 41 ファイル、`µ` が 70 か所）の
  ある行は、行まるごと UTF-8 のバイトを 2 つずつ組にして `\'XX` で書き、組の相手になった ASCII（RTF の閉じ括弧 `}` も）まで字にしてしまう。
- **設定では直らない**: `INPUT_ENCODING = UTF-8` はもとから。`OUTPUT_LANGUAGE` を全部試すと、UTF-8（65001）で書くのは Hindi だけ（見出しがヒンディー語になる）、
  English は 1252 で日本語がすべて化ける。`UTF-8` は言語の値として断られる。
- 崩れた並びを字に戻して書き直す後処理で括弧は閉じ、LibreOffice も読めたが、変換が 50 分を越えても終わらなかった。
- **ユーザー判断で docx をやめた**（`GENERATE_RTF = NO`、`make_docs.sh` の LibreOffice の手順を外した）。API 文書は `build/reports/doxygen/html/index.html`（UTF-8 で字化けなし・呼び出しの図・検索）。
  Doxygen の実行は約 37 分。ほかの報告（SRAM・スタック・複雑度・cppcheck）の docx はそのまま

## 2026-10-31: FFT のアセンブラ化と、QEMU でのアセンブラの試し

- **FFT**（`src/dsp/fft_f32.S`・`fft_f32.c`・`fft_tab.c`、SGX の ABI 1.7・MicroPython の `fft`・CD のスペクトログラムが使う）:
  radix-2²（2 段を 1 回の読み書きに、複素数の掛け算は 3 回 = w2²·x1・w2·x2・w2³·x3）、点は 64 ビットで読み書き、FPU の `VFMA`。
  入力はビット反転の位置へ写しながら（`RBIT`）、作業場は SRAM（`fft_work_get`、取れなければ PSRAM）。回転子は sin(2πk/4096) の 1/4 周期の表（フラッシュ 4KB）を
  呼ぶたびに n/4+1 個だけ作業場の後ろへ間引いて写し、象限は条件付き実行で折り返す。以前の C は毎回 `cosf`/`sinf` で回転子を作っていた。
- 実測（MicroPython の `fft.fft`、1 回あたり µs）: FB を表示した画面で 64 点 373 -> 216、256 点 1,172 -> 505、1,024 点 6,376 -> 2,881、4,096 点 111,903 -> 15,427。
  FB なし（モード 1）で 40 / 124 / 688 / 4,490。4,096 点の内訳（FB なし）は取り込み 1.36ms・段 1.55ms・書き出し 1.41ms（配列が PSRAM なので、取り込み・書き出しは PSRAM の待ちで決まる）。
  FB を表示している間は Python の core1 が表示の取得のたびに待たされるのが主（`render_park_on`）。
- **表の置き場の教訓**: 1 周期の表（16KB）をフラッシュから段の計算で直に読むと、キャッシュの外れで段が 2.5ms（SRAM なら 1.4ms）。SRAM に常駐させると
  ローレゾ面の SRAM が足りず `mode5.sgx` が開けなかった。1/4 周期を作業場へ写す形で段 1.55ms、常駐の SRAM は 0。
- **`scripts/test_dsp_asm.py`**（`test_all.sh` に足した）: QEMU mps2-an505（Cortex-M33）でアセンブラを走らせる（`scripts/qemu_dsp/`）。FFT は numpy と、ローレゾは C の版と比べる。
  セミホスティングの出力は stderr に出ることがあるので合わせて読む。わざと壊した版で NG になることを確かめてある
- GCC 10 には `__builtin_arm_rbit` も `__rbit`（arm_acle.h）の実体も無い。インラインアセンブラで

## 2026-11-01: 全体の静的解析（cppcheck・GCC 14 の -fanalyzer・lizard）

ユーザー指示。SG BASIC（2026-11-01 にファームへ組み込み）が初めて対象に入った。

- **cppcheck**: 警告 204 -> **0**（基準 `docs/baseline/cppcheck.sarif` を作り直した。note は「分岐を数え切れない」の 87 件だけ）。
  - bison / flex の出力（`build/sgbasic_gen`、`#line` で指す `parser.y`・`lexer.l`）は `make_docs.sh` で見ない
  - **`vm_error` / `vm_error_at` に noreturn**（longjmp で戻らない）。誤検知の多く（負の添字・NULL・確保の失敗）がこれで消え、コンパイラにも伝わる
  - 本物: ファームの strtod の代わり（`fw/sgb_fw.c`）が極端な指数で表 `p10[23]` の外を読む、使われない構造体の項目・代入、ほか BASIC の const 113 か所（`-Werror=discarded-qualifiers` で組んで確かめた）。BASIC の外は `render.c` の MPU の属性の書き方・`MB_SIG_IGN` の値の書き方・`stress.c` の変数の置き場
- **GCC 14 の `-fanalyzer`**（`scripts/analyze_gcc.sh`）: 組み立てが止まっていた所が 2 つ（GCC 14 は宣言の無い関数の呼び出しを誤りにする）:
  - **bison の `parser.c` が `sgb_malloc` を宣言なしで呼んでいた**（`malloc` の読み替え。GCC 10 の警告は `-w` で消えていた）-> `fw/sgb_fw.h` に宣言
  - **Doom の `dg_sound.c` が `M_snprintf`・`M_StringCopy` を宣言なしで**（`m_misc.h` を読む）
  - 本物の指摘: **NTFS の書き込みで、索引の根が読めない壊れたレコードだと NULL を読む**（`ntfs_w.inc`、誤りで返す）。ほかの解析器の指摘（`fstr.c`・`ime.c`・`usbkbd.c` の switch の表・`sgx.c` の `S`）は道筋を見て誤検知（`room_begin` には念のため守りを 1 行）。`-Wformat-truncation` 13 件は画面の欄に収めるためにわざと切っている所
  - GCC 14 で組むと、`isofs.c` の `begin` が確保の関数を直接呼ぶ形になり SRAM の配置の検査が 2 件落ちる（インライン展開の違い。本番の GCC 10 では通る）。解析の組み立て（`build_analyze`）は最後のリンクで止まるが、SARIF は全部出る
- **lizard**: 組み立てた物（`*/build/*`）を数えないようにした。上位は振り分けの大きな switch（`exec_op` 284・`machine_dispatch` 175 など）
- 確かめ: BASIC のホストの試験・R02 との命令の照合（57 本）・ASan、`test_fs.py`、実機で Machine の 3 言語の照合 62 行一致・mode5 / mode7

## 2026-11-01 書き込みが消す段で時間切れになる

`flash_swd.sh` が「timed out while waiting for target halted / Failed to call ROM function batch / failed erasing sectors」で 5 回続けて失敗した
（`--rescue` してからでも）。`ADAPTER_SPEED=1000`（既定 5000）にしたら 1 回で通った。続くときはまず速さを下げる

## 2026-11-03 静的解析（cppcheck の指摘を片付けた）

- cppcheck: `ninja reports` の `sarif diff` が警告 0（基準 `docs/baseline/cppcheck.sarif` と同じ）。直した主なもの:
  - `sh_cmds.c` の連続代入（`a = *p, b = *p`）・`sh_edit.c` の const / 変数の範囲 / `c` の影・`sh_lang.c` の常に真の条件・
    `sh_child.c` の const 引数・`sh_mem.c` / `sh_main.c` / `sh_edit.c` の const ポインタ・`sh_term.c` の重複条件と `rep` の範囲・
    `apps/more` の `'\r'`（`SGX_KEY_ENTER` と同じ）・`rbrun.c` の `av` の初期化・`sysdisk.c` の const ポインタ
  - `sys_dir[260]` をやめて `rbfh_cwd()` に（SRAM も 260 B 減った）
- GCC 14 の `-fanalyzer`（`scripts/analyze_gcc.sh`）: 組み立ては既知の `check_sram_funcs.py` 2 件（`isofs.c` の `begin`）で止まるが SARIF は出る。
  自前コードの新しい指摘は無し。残る 27 件は既知の誤検知（`fstr.c`・`ime.c`・`sgx.c` の `S`）と、画面の欄に収めるための `-Wformat-truncation`
  （意図的な切り詰め）と SDK / third_party のもの。

## 2026-11-06 アリーナ（vmem / pmem）の排他

- 精査で、`vmem_*` / `pmem_*` に排他が無いのを見つけた。入口（`AR_API` の各関数・動かせるブロックの登録の口・コンパクションの本体）を、1 つの
  再入できるミューテックス `vmem`（M33BEATOS の、優先度を貸す）で囲む（`src/mem/vmem.c` の `ar_lock`）
- 囲むのは core1 のタスクから呼んだときだけ。core0・割り込みの中・PRIMASK で止めた中・RTOS が始まる前は素通し（`mb_self()` は core1 のいまのタスクを返すので、
  core0 から使うと別のタスクを持ち主にしてしまう）。BASEPRI で止めた中では `mb_mutex_lock` が `MB_ERR_ISR` で戻るので囲まない
- **割り込みを止めた中からアリーナを呼ばない**（素通しになる）。`sgx.c` の `a_mem_info` はこのために `mb_lock` をやめた
- コンパクションは、ほかのタスクが安全点で止まるのを待つ間（最大 300ms）だけロックを外す（持ったまま待つと、確保の途中のタスクが安全点に来られず打ち切りになる）。
  動いた知らせ（ファイラーの `list_buf_moved` -> `app_move`）は待たないので、ロックの中で呼んでよい
- SRAM は +24 B（ミューテックス）。`scripts/test_vmem.py` は通る（ホストでは囲まない）
- アプリの作業領域の記録の表（`appmem.c` の `app_blk`）も同じロックで囲む（`vmem_lock_take` / `vmem_lock_give`）。空きの欄を探してから確保して書くまでの間に、別のタスクが同じ欄を使うことがあった

## 2026-11-07: SRAM の洗い出しと移設（アリーナ +29KB、ファイラーの「一覧のためのメモリが足りません」）

ファイラーで「一覧のためのメモリが足りません」が出た。アリーナの一覧（遠隔コマンド `MEM`）では、空きは 50.7KB あるのに
`msc512 bounce`（4KB）が真ん中に挟まって 35.8KB と 14.9KB に割れ、ボリュームの置き場（`fs volume`・`fs record`・`fs bounce`・`fs name`、
1 つ 10.7KB）が奥にあった。コンパクションが動かせるのはファイラーの一覧の 3 つ（`vmem_move_register` しているもの）だけで、
ほかは abort になる。ユーザー判断で次の 5 つを入れた。

| 変更 | 中身 | 効き目 |
|---|---|---|
| `msc512 bounce` を上の端から | `msc512.c` の `app_alloc` -> `app_alloc_high` | 空きの割れが消えた（ファイラーの一覧を持ったまま 1 つながり 60,960 B） |
| fs の `rec`・`name` を PSRAM へ | `fscore.c`。`fs_io_cb`（USB の完了の受け口）が書くのは `fsvol_t` の印だけ。`rec`・`name` はアプリ時間の `fs_poll` と、関所の中の rbfs が CPU で触るだけ。書き込みで USB に渡しても msc512 が SRAM の受け場で区切って写す | 1 ボリューム 4.8KB（exFAT を開いたままで SRAM の空き 1 つながり 55,096 B。前は 14.9KB が最大） |
| `fja.c` の訳の表 4 つを `__in_flash` | 窓に出すとき（アプリ時間）だけ引く。文字列はもとからフラッシュ。`make_locale.py` の読み取りも合わせた | .rodata 2KB |
| シーケンサー `sndseq.c` をフラッシュへ | `SGNANO_FLASH_FILES`。FB を出したままアプリ時間の外で鳴るのは関所（`render_park_on`）の中だけで、曲のデータはもとから PSRAM | .text 20KB |
| PNG の解読 `png.c` と `fpng.c` の `rd`・`on_row`・`put_row` をフラッシュへ | 関所の中だけで呼ばれる。`fpng.c` の読み出しの受け口 `s_start`・`s_data`・`s_end` と、関所を立てる前に走る `fpng_work`・`setup` は SRAM のまま。名前がありふれているので `*fpng.c.o(.text.rd ...)` と .o を限って書いた | .text 9KB |

組み立てのアリーナ 161,440 -> 190,652 B（+29.2KB）。

- **`check_sram_funcs.py` は関数を名前で探す**。`png.c` の static な `feed` を移したら、`uartcon.c` の `__not_in_flash_func(feed)`
  （インライン化されて記号が無い）と取り違えて「SRAM にいない」と落ちた。`png.c` の側を `inflate_feed` に改名した。
- 実機の測り比べ（同じ 1,661,158 バイトの PNG、1344x896 -> 640x427、FB を出したまま）: PNG を SRAM に置くと 9.33 / 9.35 秒、
  フラッシュに置くと 10.56 / 10.53 秒（+13%）。ユーザー判断でフラッシュのまま。
- シーケンサーの起きる遅れ（`seq_lag_max_us` / `seq_lag_over2ms` / `seq_lag_count`、止めずに `mdw` で読む。`sndseq.c` に足した）:
  `S:/testapp/mode2.rb`（FB を出したまま `WTF4CH.mid`）30 秒で、SRAM の版は最大 10µs、フラッシュの版は最大 387µs。
  どちらも 2ms を超えたのは 0 回（約 500 回中）、音の `fifo_stall` 0、ユーザーも聴いて良好。
- ホスト試験: test_png・test_fs・test_sound・test_sysdisk・test_msc2048・test_part・test_fat_write・test_vmem が OK
  （`scripts/host_part/main.c` に `app_alloc_high` のスタブを足した）。
- 残りの候補（今回は見送り）: SRAM の区画の表を 64 個に分ける（2.5KB）、`audio wave` を 4 ボイスぶんに（0.5KB）、
  `usbpad_mount`（2.9KB）、`fcdviz_tables`（1KB）、`audio streams` 16KB を開いたときだけ取る（4KB 整列が取れない恐れ）。

## 2026-11-10: オーディオの環の遅延確保と、冷たい `.text` のフラッシュ移設

mplay の OGG でテキスト面とスペクトログラムを両立させるため、SRAM を空けた。

- **オーディオの環**: これまで 4 ボイス分 32KB を `audio_init` で固定確保していた。voice 0 だけ先に 8KB を取り、
  ほかのボイスは `audio_stream_start_voice` が使うときに 8KB ずつ取る（`VMEM_FIXED`、8KB 整列）。
  mplay は voice 0 だけなので、実行時の空きが **+24,576 B**。CD や SGX が複数ボイスを使うときは、使う分だけ取る
  （取れなければそのボイスは鳴らない。従来は 4 本まとめて取れなければ音全体が無効だった）。
- **`.text`**: 199,334 -> **185,194 B（-14,140 B）**。`.rodata` も 23,333 -> 22,377 B（-956 B）。
  静的なアリーナの空きは 140,492 -> **155,852 B（+15,360 B）**。移したもの:
  | 何を | 大きさ | なぜよいか |
  |---|---:|---|
  | `filer/fvgm.c` 全体 | 3,660 B | VGM の再生中は FB を隠す（`vga_set_fb_visible(false)`）。読み込みタスクも同じ |
  | `filer/fdel.c` 全体 | 2,596 B | ファイラー（テキスト面）のアプリ時間だけ。USB 完了の受け口は `__not_in_flash_func` で SRAM のまま |
  | `filer/frender.c` 全体 | 2,300 B | WAV 書き出しの窓。ファイラーのアプリ時間だけ |
  | `filer/kbdcfg.c` 全体 | 252 B | 起動時・設定のときだけ |
  | VGA のモード切替・診断（`load_pio_programs` `vga_set_timing` `vga_set_mode` `vga_set_blank` `vga_recover` `vga_print_state` `vga_stop` `vga_start`） | 2,128 B | 表示を止めてから走る。`display_start_c0` / `display_stop_c0` は `vga_core0_service`（SRAM）から呼ぶので残す |
  | `video/vga_pio_gen.c` 全体 | 1,032 B | モード切替のときだけ |
  | `video/timing.c` の冷たい 4 関数（`check_pio` `find` `check_render` `freq_name`） | 944 B | モード切替・診断だけ。`vga_timing_current` は熱いので残す |
  | `video_reset` `video_print_state` | 456 B | モード切替・診断だけ。`refresh_stop` は毎フレーム呼ぶので残す |
  | `bm8_open` `bm8_close` `bm8_palette_default` `bm8_set_palette` `bm8_get_palette` `bm8_enable` | 772 B | モード切替・色の設定だけ。`bm8_line` / `bm8_flush` / `bm8_wrap_set` は SRAM |
- 残りの `.text` 候補は USB のマウント・セットアップ（`usbmsc` の `inquiry_done` 1.6KB、`usbfat` の MBR/GPT/VBR 1.5KB、
  `usbufi` の TOC/INQUIRY 約 4KB）。ただし、FB を出したまま機器を挿したときにフラッシュを走らせることになるので、
  ユーザーと決めてから。USB キーボード・マウス・ゲームパッド（`usbhost.c` / `usbmouse.c` / `usbpad.c`）は 2026-11-03 の
  ユーザー指示どおり SRAM のまま。
- **テキスト面（2026-11-10、続き）**: mplay 用の小さい面（25 行・グリフ 19 行）を足した。`ch`/`at` は PSRAM、
  表示用の `rat`（下位 13bit）とグリフだけ SRAM。小さい面は約 28.8KB（前は 53.1KB、-24KB）、大きい面（30 行）も
  `ch`/`at` を PSRAM へ置いて約 43.7KB（-9.4KB）。`.text` は text.c の変更で +380 B ほど（185,182 -> 185,562 B）、
  `.rodata` +260 B。mplay 実行中の空きは計算上 **約 68.8KB**、64KB ビットマップを引いて約 4.7KB の余裕。
  ビットマップはテキスト面を開いた直後（ファイルの読み出し・FFT より前）に取るので、64KB の連続した空きがある。
  実機（ABI 4.12）の `MEM`: アリーナ 156,864 B、text plane small 28,794 B、bitmap 64,028 B、
  file read chunk 16,388 B、sgx sram 3,592 B、msc512 bounce 4,100 B、audio stream 8,192 B、vga ring 20,480 B、
  free 4,734 B（largest 4,720 B）。`[mplay] bitmap ... (SRAM)` を確認。
  ホスト試験は `test_text_attr.py` と `test_edit.py` が通る。

## 2026-11-13: SRAM 不足 — ストレージの作業場の先取りと、VGM の合成のオーバーレイ

- 症状: 標準の負荷試験 `stress_sgx.sh` が「could not set mode 3 (not enough memory for the text plane)」で FAIL（11/05 の PASS のあと、
  MIDI・GPIO・ADC・音楽の口で SRAM が増えた）。ほかにも、エディタが開かない（読み込みの環 32KB のあとの FAT の名前の作業場 2.2KB が
  取れず黙って失敗。色分けの日に直した）、testapp の mode3〜5 が開けない、が出ていた。
- **ユーザー指示**: 負荷試験の目的は「CPU 負荷が高い状態で USB MSC の操作が正しく行われるか・遅くなる要因が無いか・ほかへ影響を
  出さないか」。**限界までストレージ以外がメモリを確保した状態でストレージが使えることが目標。削るより、ストレージのメモリの
  使い方を変える方向で**。途中で「一度リファクタリングしてみましょうか」→ 的は「VGM の合成を必要時だけ SRAM へ」（ユーザーが選んだ）。
- (1) 機能を削らない移設: mbedTLS の AES の表を定数に（`MBEDTLS_AES_ROM_TABLES`、.bss 8.7KB）、YM2608 のリズムの ROM 8KB をフラッシュへ
  （読む関数は SRAM のまま）、アリーナの区画の表を SRAM 128 / PSRAM 192 に分けた（APPMEM_MAX 96 が SRAM で埋まっても足りる。2.5KB）。
- (2) ストレージの作業場: SRAM でなければならないもの（USB の完了の受け口が触る・フラッシュを書く間に読む）は起動時に上の端から取って
  返さない: FAT の名前・一覧（`usbfat_reserve`、4KB。`nw_t` と `list_work_t` が入ることを `_Static_assert`）、CD・フロッピーの受け場
  （`usbufi_reserve`、4KB）、区画の走査（`usbpart_reserve`、512 B）、S: の書き溜め（`sysdisk_reserve`、4KB）。msc512 の 4KB は 11/09 から。
  速さのためのものは SRAM が無ければ PSRAM: ビュアー・エディタの読み込みの環（`fload.c`、受け口からは `render_qmi_copy`）、コピーの受け場
  （`fcopy.c`、下の msc512 / usbufi が SRAM の受け場で区切る）。コピーの段取りの一覧は取れなければファイラーの一覧の置き場を返してもらう。
- (3) **VGM の合成のオーバーレイ**: `ld/placement.cmake` が SDK の memmap_copy_to_ram.ld の `.text` / `.data` の `*(.text*)` /
  `*(.rodata*)` から 7 つのファイル（third_party/ymfm/src と vgm_engine / extra / extra2 / pcm / rf5c / wav / ymfm.cpp）を外し、`.bss` の後ろに
  `.music_ovl`（`> RAM AT> FLASH`、起動時には写さない）を置く。冷たい半分（開く・書く・閉じる…）は前から `_music_cold_pats` でフラッシュ。
  アリーナは `__music_ovl_start__` から始め、その範囲を **貸せる区画**（`vmem_lend_setup`）にする: ふだんは使用中の区画
  `music engine (idle, lendable)`、ほかの確保が空き不足で失敗したときだけ空きに戻して貸す（`lend_borrow`、`[mem] lending ...` を出す）。
  借り手が返して範囲がまるごと空いたら貸せる区画へ戻す。music.c は VGM を開く前と WAV の書き出しの前に `vmem_lend_claim` で取り戻して
  フラッシュから写し（52.6KB、DSB / ISB）、片づけの最後に `vmem_lend_release`。取り戻せなければ `no SRAM for the VGM engine`。
  外から入る所は `scripts/check_music_ovl.py`（bl / b.w と長い分岐の中継、データの表の関数ポインタ）で洗い出し、ビルドのたびに走らせる。
  初めの洗い出しで、起動時の `music_cfg_init` と書き出しのあとの `music_render_error` がオーバーレイの関数（`vgm_*_pct`・`vgm_wav_error`）を
  呼んでいたので、フラッシュへ移した。`scripts/sram_report.py` はオーバーレイと .heap をアリーナに数える（188,606 B、うち 52,302 B）。
- 結果（実機）: アリーナ 115,896 -> 188,576 B。モード 3 が開く（mode3_mp3 で確かめた）。mode1_vgm・mode2_vgm はオーバーレイを取り戻して鳴る。
  遠隔コマンド `SRAMHOG ON`（アリーナの空きを全部取る。プログラムが走っていても受ける）を負荷試験の 4 秒目に掛け、**SRAM の空き 60 B
  （最大 24 B）で PASS**（往復 77 回・9,856KB・誤り 0。取らないときも 77 回 = 遅くならない。FAT の書き込みのクラスタの並びは PSRAM へ逃げた）。
- 残り: モード 3〜5 と VGM を同時に使うもの（mode3_vgm・mode5_vgm）は、ローレゾ面が区画を借りるので VGM を鳴らせない（テキスト 43.7 +
  ローレゾ約 45 + VGM 52.6 + ストレージ 17 + 固定 34.6 = 約 193KB、アリーナ 188.6KB）。エラーで返り、落ちない。
- ホスト試験: `test_vmem.py` に貸せる区画（idle・取り戻し・満杯で貸す・返したら戻る・入らなければ貸さない）。
- **【追記・同じ日】OPL 系を別の区画に分けた**（ユーザー判断: 残り約 5KB を埋める）。OPL 系の熱い関数は 10.7KB。リンカの台本は節の名前では
  除けない（ファイルでしか除けない）ので、OPL のつなぎを `vgm_ymfm.cpp` から `vgm_ymfm_opl.cpp` へ分け、`ymfm_opl.cpp` と合わせて
  `.music_ovl_opl`（本体のすぐ後ろ。本体の区画の末尾に見張りの語の 32 B を空ける）に置いた。アリーナは貸せる区画を 2 つ持ち（0 本体・1 OPL）、
  貸すときは OPL から 1 つずつ（`lend_borrow`）。music.c は曲の頭（.vgz は tinfl で頭 256 B だけ展開）に YM3812 / YM3526 / YMF262 の
  周波数があるときだけ OPL の区画を取り戻す（`vgm_head_has_opl`、エンジンの chips_open と同じ欄と頭の終わり。読めなければ念のため写す）。
  WAV の書き出しはファイルの頭 4KB を読んで決める。
- テキスト面を上の端から取る（`text.c`、`VMEM_PLANE_HIGH`）: アリーナの下の端に 2 つの区画があるので、テキスト面が下に居ると OPL の区画の
  隣はテキスト面になり、借りても空きと繋がらない。上に置くと OPL の区画がファイラーの一覧の跡（SGX のときの空き）と隣り合う。
  あわせて音の受け場（`audio.c` の stream / wave）を固定（`VMEM_FIXED`）から上の端（`VMEM_PLANE_HIGH`）へ: 固定の確保は固定の区画の
  すぐ下が空いていないと取れず、テキスト面を上に置いた最初の版は音が出なくなった（"the sound ports are busy"）。
- 結果（実機）: ローレゾ面は貸せる区画を借りずに開く（16KB のパターン・5 本のパレット、残り 2.8KB）。**mode3_vgm・mode5_vgm・mode6_vgm で
  VGM が鳴る**（本体の区画を取り戻し、OPL の区画は貸せるまま）。OPL2 の曲では本体と OPL の両方、OPM の曲では本体だけを取り戻す。
  負荷試験 PASS（往復 76 回・誤り 0）。ホスト試験 `test_vmem.py` は 2 つの区画（後ろから貸す・両方貸す・返したら戻る）。
- 【訂正 2026-11-13】上の「mode3_vgm・mode5_vgm・mode6_vgm で VGM が鳴る」は、ローレゾ面がパターン 16KB（256 タイル）・パレット 5 本の
  最小の形で開いたためだった（3b769ea の「借りずに入る形を先に全部試す」）。テスト用アプリ（4 言語とも、フォントにタイル 0〜255、オブジェクトの
  円の絵にタイル 256〜340）は 32KB を前提にしていて、範囲の外の絵は書き込まれず、**モード 3〜6 のオブジェクトが出なかった**（ユーザー報告。
  こちらの確かめは音とメモリの記録だけで、画面を見ていなかった）。ユーザー判断で、1 周目（借りない）はパターン 32KB・パレット 16 本以上だけを試し、
  入らなければ 2 周目で VGM の区画を借りる（16KB は 2 周目の最後の手段のまま）。必要な大きさは 32KB + マップ 16KB + 作業場 約 10KB + パレット
  16KB ≒ 74KB、SGX のときの普通の空きは約 40KB なので、テキスト面のあるモード 3〜6 で VGM を同時に鳴らすことはできない（エラーで返る）。
  実機での確かめは、他のエージェントの転送が終わってから（ユーザー指示で、この時点では実機に触らない）。
- 【追記 2026-11-13】32KB を最低にしたら jumps_vgm（モード 5、16KB で足りる。背景のタイルは入るだけ置く）が VGM を鳴らせなくなった（ユーザー報告）。
  どちらが要るかはプログラムにしか分からないので、ユーザー判断で「16KB でよい」と言える口を足した: SGX の `set_mode` の印 `SGX_MODE_LR_SMALL`
  （0x800、ABI 5.4。表は同じ）、Ruby `Machine.lowres_small=`、Python `machine.lowres_small`、BASIC `Machine.LowresSmall 1`。どれも
  `screen_lowres_allow_small`（screen.c）か `R.rq_arg` の印で、`rbrun.c` / `screen.c` の 1 周目に 16KB も試す。言語は始めに下ろす（rbrun.c・pyrun.c）。
  jumps.c と jumps_vgm.rb はこれを立てる。既定は 32KB のまま（テスト用アプリなどはそのまま）。

### 2026-11-13（続き）リファクタリング: テキスト面のグリフを行ごとに、ラスタの表を使うときだけ

- ユーザー: 「もう 16KB SRAM が使えれば全部乗るんですよね？リファクタリングをしてみませんか？」。見積もり: 32KB のローレゾ面（パターン 32 + マップ 16 +
  パレット 4 + 作業場 7.4 ≒ 60.7KB）と VGM（本体 41.9KB）を、テキスト面のあるモード 3〜5 で同時に載せるには約 6KB（OPL の曲まで約 17KB）足りない。
  候補 A〜D からユーザーが A（ラスタの表）と B（テキストのグリフ）を選んだ。
- A: `vga_raster` を .bss の配列（6.7KB）から、使い始めたとき（`vga_raster_ensure`）に SRAM のアリーナの上の端から取るポインタに。描画は
  `vga_raster_at` が NULL なら「指定なし」（前から NULL を扱えた）。プログラムの `raster_clear` は中身を 0 に（`vga_raster_reset`）、プログラムの
  始め・終わりの `vga_raster_clear` で返す。ユーザーは PSRAM でよさそうと言ったが、描画の手伝い（core1、QMI に触らない印）は表示の取得の間も走り、
  PSRAM を読むと関所の MPU で止まるので SRAM にした。
- B: グリフのプール（30 行 x 1,280 B = 38.4KB、面を開くときにまとめて取る）をやめ、字のある行だけが展開のとき（アプリ時間、`video_start_frame`）
  上の端から 1,280 B ずつ取る（`glyph_take`）。字の無い行は `text_trim` で返す（ローレゾ面を開く前の rbrun.c / screen.c、`app_sram_reclaim`）。
  描画の熱い経路（`text_overlay_line` が `glyph[row]` を読む）は変えていない。取る・返すのはアプリ時間だけ。取る前に空きの最大を見て、貸せる区画
  （VGM）は借りない。
- 実機で出たこと: (1) ローレゾ面がパレット 64 本まで取り、テキストの下の行が出なかった -> 借りない 1 周目の上の 2 段にテキストの行の分 16KB
  （`RB_LOWRES_TEXT_KEEP`、のちに 20KB = 15 行）も残し、パレットは 16 本まで（screen.c も同じ考え）。(2) 行が取れないたびにセルごとに `text_trim`（30 x 80 を PSRAM から読む）をやり直し、
  アプリ時間を 2 秒はみ出して（`[wdt] slow loop: 2254464 us`）USB のタスクが回れず、負荷試験の書き込みが 60 秒で打ち切られ FAIL ->
  取れなかったら空きの合計が増えるか、テキストを消す（`text_clear` / `text_clear_row`）まで取りに行かない（`glyph_starve`）。(3) VGM の
  スタック 8KB とチップの状態が先に SRAM を取り、テキストの行が 8 行しか取れなかった -> 音楽は SRAM に 24KB 残るときだけ SRAM（`MUSIC_SRAM_KEEP`。16KB では mode5_vgm のテキストが 9 行しか取れなかった）。
- 結果（実機）: アリーナ 188.6KB -> 194.7KB。ファイラーは 30 行とも字が出る（画面の写しで確かめた）。mode3_vgm・mode5_vgm でパターン 32KB・
  16 本のローレゾ面とオブジェクトの絵（タイル 256 の真ん中 0x7F）と VGM が同時に。jumps_vgm も 32KB で開いて VGM が鳴る。負荷試験 PASS x 2（往復 76・75 回）。
- 【追記】実機の調整: (4) 借りない 1 周目でテキスト面のあるモードは、パレットを 16 本まで（段 0〜3 とも。起動の状態で空きが数 KB 揺れ、32・64 本で
  開いてテキストの行が欠けた）、段 3（テキストの分も残さない）を足した。(5) グリフの行は 1 回の展開に 1 度だけ取りに行く（`glyph_pass_fail`）、
  取れなかったら空きの合計が 1 行ぶん増えるまで取りに行かない（負荷試験の読み書きのタスクが確保・解放を繰り返し、空きの合計が小刻みに増えるたび
  に取り直して、また slow loop 2.27 秒で FAIL した）。(6) 音楽の SRAM の余裕は 24KB。
- 最終（実機）: テスト用アプリの mode4/5_vgm・mode5 はローレゾ面 32KB・16 本、テキストの行 15、VGM / MIDI が鳴る（VGM 版は 16 行目が 1 行ぶん
  足りないことがある: 終わりの空き 2.5KB が割れている）。jumps_vgm も 32KB で VGM。負荷試験 PASS x 2（往復 76 回ずつ、fps 59.6、slow loop なし）。
