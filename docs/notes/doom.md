# Doom の移植（2026-10-24〜）

ユーザー指示: オープンソースの Doom / Doom2 を sgnano に移す。アセットは Freedoom（0.13.0）。アセットは内蔵ドライブ（S:）に置かず、外部ストレージの
`DoomFiles`（Doom・Ultimate Doom の形）か `Doom2Files`（Doom II の形）に置き、揃っているときだけ起動する。市販版の WAD はあとで足す。

## 形
- エンジンは **doomgeneric**（`third_party/doomgeneric/`、GPL-2.0。id の GPL のソース -> Chocolate Doom -> doomgeneric）。取り込みと手直しは
  `third_party/VERSIONS.md`・`third_party/doomgeneric/SGNANO_PATCHES.md`（`i_system.c` のゾーン、`m_config.c` の設定のフォルダ）
- 移植の層は `src/doom/`:
  - `dg_port.h`: 取り込んだソースの全部に `-include`。stdio・malloc・exit・sscanf・atoi・strtol などを `dg_sys.c` へ向ける（ソースは変えない）。
    newlib の scanf・strtod・malloc を引き込むと SRAM に約 25KB 入ったので、使う分だけ自前にした
  - `dg_sys.c`: malloc（PSRAM の 768KB の置き場、先頭から詰める）、ファイル（rbfs の上。64KB 以下は丸ごと、大きいもの = WAD は好きな位置から読む
    `rbfs_ra_*`）、パス（ドライブ文字の無いものは WAD のフォルダの下。Doom は ".//.savegame/" のようにつなぐので整える）
  - `dg_video.c`（`i_video.c` の代わり）: 画面モード 7 の VRAM（SRAM、320x200x8）に Doom が直に描く。パレットはビットマップ面へ
  - `dg_main.c`: 始め・終わり・タスク・キー・時刻
- **メモリ**: Doom の .data・.bss（292KB）は PSRAM の決めた所（リンカの `.doom_data` / `.doom_bss`、0x11780000 から 512KB、キャッシュの窓。
  PSRAM のアリーナはここを除く）。始めるたびに .data をフラッシュから写し .bss を 0 に。ゾーンは PSRAM の空きの最大から 384KB を残した分（いま約 4.1MB）。
  コードと定数はフラッシュ（`third_party/*` と `src/doom/*.c` はフラッシュに置く並び）。SRAM の増えは約 3KB（静的）+ 走る間 スタック 16KB・WAD の受け場 16KB・
  ビットマップ面 64KB
- **タスク**: M33BEATOS の優先度 9（Ruby と同じ。同時には走らない）。待つ間（DG_SleepMs・ファイルの読み）は眠る。アプリのループ（優先度 8）は回り続ける
- **キー**: USB キーボードは毎回いまの押下を見て、変わったものを知らせる（Ctrl = 撃つ、Space = 使う、Alt = 平行移動、Shift = 走る、`,` `.` = 横歩き、
  矢印・Enter・ESC・Tab・BS・数字・英字・F1〜F12）。UART のキー（`app_key_from_uart`）は押して 4 回の問い合わせのあとに離す（f = 撃つ）
- **始め方**: ファイラーで `DoomFiles/freedoom1.wad` か `Doom2Files/freedoom2.wad` を Enter（`filer.c` の `open_doom`）。S:・exFAT・NTFS・CD は断る（FAT だけ）。
  **終わり**: Doom のメニューの Quit（F10 -> y など。exit -> longjmp）でファイラーへ。設定（`default.cfg`）とセーブ（`.savegame/`）は WAD のフォルダの中
- 実機へ WAD（28.8MB）を入れるのは `scripts/zm.sh put --remote-dir A:/DoomFiles freedoom1.wad`（4MB ずつに分けて送り、実機の JOIN でつなぐ。
  `docs/notes/storage.md` の同じ日の節。1 つ約 7 分 + 結合 1 分）

## 実機（2026-10-24、USB メモリの FAT32）
- Freedoom: Phase 1 / Phase 2 とも起動。R_Init（テクスチャの用意、WAD を読む）に約 20 秒。タイトル・デモが動き、UART のキーで新しいゲーム（E1M1）・前進・F10 -> y で終わってファイラーへ
- 速さ: ゲーム中 **約 45 フレーム / 秒**（ゲームの進みは 35 tic / 秒）、Phase 2 のデモで約 70 フレーム / 秒。表示は underrun 0・recover 0（fifo_stall は始めと終わりに数個）
- 画面は SWD で VRAM とパレットを止めずに読んで確かめた（ファイラーの Alt+PrintScreen は、Doom が PSRAM を使い切っているので走らない）
- 直したもの: sgnano の `snd_channels()` と Doom の変数がぶつかった（sgnano を `snd_port_count()` に）、ゾーンが PSRAM を使い切り rbfs の一覧の置き場が取れなかった
  （384KB 残す）、`mkdir(".")`・設定のフォルダの区切り、終わったあとビットマップ面（64KB）と WAD の受け場（16KB）が SRAM に残り、ファイラーが一覧を読めなかった

## 音（2026-10-24、`src/doom/dg_sound.c`）
- 音楽: Freedoom は MIDI（MThd）、市販版の MUS は doomgeneric の mus2mid で MIDI に直し、sgnano のシーケンサー（`sndseq_play`）で。ドラムは鳴らない（シーケンサーの決まり）
- 効果音: DMX の 8 ビットの PCM を 8 チャンネル、11025Hz で混ぜ、最後のポートを流し（`audio_stream`、STREAM のモード）で。そのポートは BGM に使わせない
- sgnano の音の口を呼ぶのはアプリのタスクのアプリ時間だけ（`dg_sound_app_time`）。Doom のタスクは頼みを書くだけ。`FEATURE_SOUND` を立て、`i_sound.c` は SDL_mixer を読まない
- 実機: 起動して誤りなし、速さは変わらない。**鳴り方はまだ聞いて確かめていない**（ユーザーに頼んだ）

## これから
- パッド、exFAT・NTFS の WAD、市販版の WAD の名前、ゾーンを FB のページ（2.4MB、モード 7 では使わない）から借りる（【追記】どれも 2026-10-24 に済み。パッドは実機で押していない）

## 2026-10-24 パッド・市販版の名前・ゾーンを広げる
- **パッド**: つながっている最初のパッドをキーとして知らせる（F310 の D モードの並び = Ruby の `Machine::PAD_*`）。十字キー・左スティックで前後と回る、
  A = 撃つ（メニューでは Enter）、B = 使う（メニューでは BS）、X = 走る、Y = 地図、LB / RB = 横歩き、LT = 平行移動、RT = 撃つ、START = メニュー、BACK = Enter。
  実機で押して確かめていない
- **市販版の名前**: DoomFiles は freedoom1 / doom / doomu / doom1.wad、Doom2Files は freedoom2 / doom2 / plutonia / tnt.wad を起動する（ファイラーの `doom1_iwads` / `doom2_iwads`）
- **ゾーンを広げる**: 画面モード 7 では FB を使わないので、FB の 4 ページ（各 600KB）もゾーンに足す（`z_zone.c` の `Z_Init` の sgnano:、`DG_ZoneExtra`）。
  ゾーンの塊は番地の順に並ぶ決まりなので、離れた場所の間を「いつも使っている塊」でつなぐ（ページの間の見張りの語は触らない）。終わったらキャッシュを書き戻して捨て、黒で消す。
  ゾーンは 4.1MB + 2.4MB = 約 6.5MB。実機: Doom2 で IDCLEV29 で飛んで動く、終わったあとのファイラーの FB は黒
- **設定を残す**: doomgeneric は設定のファイルを読み書きしない（`m_config.c` の `#if ORIGCODE`）ので、`SGNANO` のときも有効にした。読む側の `fscanf`（"%79s %99[^\n]\n" だけ）は
  `dg_fscanf`。WAD のフォルダに `default.cfg`（1.4KB）と `doomgenericdoom.cfg`（3KB）。実機: 2 回目の起動で読み、誤りなし
- 気づいたこと: Doom のタスクとアプリのタスクが同時に printf すると、UART のログの字が欠ける（ログだけ。動きには関わらない）
- **exFAT・NTFS の WAD**（2026-10-24）: fs の層に `fs_extents`（ストリームの前に作るエクステントだけを返す。機器の LBA）を足し、`rbfs_ra_open` が FAT と同じく
  `usbfat_raw_read` で読む。MFT の中に入っている小さいファイル・疎のファイルは断る。ホスト試験 `test_fs.py` の X（exFAT・NTFS、区画の先頭ずれも、元の CRC と一致）。
  実機はまだ（いまつないでいるのは USB メモリの FAT32 / FAT16 だけ）
  【追記 2026-10-24】実機で確かめた（HDD の exFAT・NTFS。下の節）

## 2026-10-24 HDD の exFAT・NTFS で
- HDD の exFAT（C:）・NTFS（D:）の `DoomFiles/freedoom1.wad`（28.8MB、どちらもエクステント 1 つ）で起動、デモが正しく動く（約 34 フレーム / 秒。画面は SWD で確かめた）。
  終わるときに設定の 2 つを書いて戻る。FAT（USB メモリの A:）も同じ版で確かめ直した
- 直したもの:
  - **ゾーンの最低を 3MB -> 1MB**（`DOOM_ZONE_MIN`）: exFAT・NTFS のボリュームのキャッシュが PSRAM を使うので、空きが 2.0MB しかなく断っていた（断った訳をファイラーのログにも出す）。
    ゾーンは 2.0MB + FB の 2.4MB = 約 4.4MB
  - **終わるときの設定の書き込みが SRAM の作業場を取れなかった**: exFAT は約 19KB、NTFS は約 43KB を SRAM のアリーナから取る。書く前に開いている WAD の受け場（16KB）を一時返し
    （`rbfs_ra_release`、次に読むとき取り直す）、**Doom の間はテキスト面（約 50KB）を閉じる**（戻るとき開き直す。中身は空で、ファイラーが全体を描き直す）
- 運ぶ手順: `scripts/zm.sh put --remote-dir C:/DoomFiles freedoom1.wad`（分けて送り、実機で結合）。exFAT・NTFS のボリュームを開いていると、ZMODEM の受け場（ファイルを丸ごと PSRAM に持つ）が
  4MB の続いた空きを取れないので、`zm.py` が分ける大きさを 2MB にした（4MB を越えるファイルだけ分けるのは同じ）。分割・結合は exFAT・NTFS でもできるようにした（`fsplit.c`。
  並びは `fs_extents`、出来上がりは `fs_write`、元は機器のセクタを直に読む）。14 個の結合に約 73 秒（約 390 KB/s）
- 遠隔コマンド **`COPY 元<TAB>先`**（`sgremote_work.c`、ファイラーのコピー `fcopy.c` で。元は FAT だけ）も足したが、**USB メモリ（A:、FAT32）-> HDD の exFAT（C:）の 28MB は、元の読み出しが「the drive did not answer in 10 s」で失敗した**
  （3KB は通る。NTFS へは 900 秒返らなかった）。exFAT の書き込みと USB メモリの裏読みの取り合いと見ているが、未調査。WAD は ZMODEM で直に送った
- 気づいたこと: NTFS の部分を消す途中で 5 回 `Input/output error`（もう一度消すと通った）、`LIST` が一度「No such drive」（数秒で戻った）


## 2026-10-24 USB の機器を差し替えると終わる・読み込み中の知らせ
- **ユーザー報告**: 使っていない USB メモリをパッドに差し替えたら Doom が終わった。**原因**: 機器が減って 5 秒たつと見張り（`usbwatch_drop_check`）が USB ホストを作り直し、
  WAD のドライブも外れて `W_ReadLump: only read 0 of 552` -> `exit(-1)`。見張りの最大の数（`mounted_peak`）を SWD で 20 に書いて、同じ形を実機で出した
- **直したもの**:
  - Doom の間は「機器が減った」で作り直さない（`usbwatch_hold_drop`、減った数をそのまま受け入れる）。ほかの作り直し（制御転送の詰まりなど）はそのまま。
    実機: 同じ書き換えで作り直しが起きず、Doom が続く
  - それでも作り直しが起きたときのため、WAD を読めなかったらパスから開き直して読む（200ms ごと、15 秒まで。`dg_sys.c` の `ra_reopen_read`）。
    実機: 抑えを SWD で下ろして作り直しを起こしても Doom は続いた（ただしその間に WAD を読まなかったので、開き直しの道そのものはまだ通っていない）
  - **読み込み中の知らせ**: 始めたらまずテキスト面に「読み込んでいます」（倍角）・WAD の名前・「しばらくお待ちください（20 秒ほど）」を出し、最初の絵が出たら消してテキスト面を閉じる
    （閉じるのは前と同じく、終わるときの設定の書き込みに SRAM を空けるため）。実機: 読み込み中のテキスト面の中身を SWD で読み、絵が出たあと閉じたのを確かめた

## 2026-10-24 物のちらつき・読み込みの進み具合・Doom の間に止めるもの
- **ユーザー報告**: ゲーム画面の背景は安定しているが、物（敵・アイテム・武器）の表示がちらつく。**原因**: Doom が表示中の VRAM に直に描いていた。
  壁・床を描いてから物を重ねる途中が表示に出る（壁は毎フレーム同じ所に同じ色を描くので目立たない）
- **2 枚の面**: Doom は後ろの面（SRAM 64KB、`dg_back`）に描き、`I_FinishUpdate` で待つ。アプリ時間（描画が止まっている間）にアプリが表示の面へ写して
  （SRAM から SRAM へ 64KB）起こす（`dg_main.c` の `present`）。フレームはアプリ時間の間隔に揃うので、デモで 50〜60 -> 約 30 フレーム / 秒（ユーザー了承済み:
  「FPS を落としてでも」）。後ろの面が取れなければ前のとおり直に描く（ログに `1 buffer`）
- **SRAM の並び**: 下から 表示の面（bm8）・後ろの面・Doom のスタックの順に取る。テキスト面は Doom の間は開かない（`screen_no_text` を立てて
  `screen_set_mode`、戻るとき開き直す）。テキスト面を下に残すと、閉じたあとの穴（52KB）に 64KB が入らなかった。最初の絵のときの SRAM の空き 30KB
  （WAD の受け場 16KB を返すと末尾に約 46KB。NTFS の書き込みの作業場は 43KB）
- **読み込みの画面**: テキスト面を使わず、表示の面（320x200）にフォント ROM の字で「読み込んでいます」（2 倍）・WAD の名前・進み具合の棒・百分率を描く
  （アプリ時間に、変わったときだけ）。「20 秒ほど」は消した（媒体で変わる）。進み具合は `d_main.c`・`r_data.c` に足した `DG_Load(段, i, n)` から。
  USB メモリの FAT32 で段の時間を測った: W_Init 0.27 秒・パッチの名前 0.08 秒・テクスチャの定義 0.01 秒・**テクスチャの見本作り（`R_GenerateLookup`、全部のパッチを読む）19.7 秒**・
  **スプライトの大きさ（スプライトを読む）2.8 秒**・ほか 0.4 秒（合わせて 23.3 秒）。千分率はこの割合で割り振った（見本作り 840、スプライト 120）
- **Doom の間に止めるもの**（ユーザー指示: 裏で PSRAM を使うもの）: 遠隔コマンドは PING のほか `ERR 16 busy: Doom is running` で断る（ZMODEM の ZPUT / ZGET も）、
  LAN の処理（lwIP のヒープが PSRAM）を回さない、始めるとき CD の再生を止める。画面モード 7 の表示は SRAM だけを読む（PSRAM の FB の取得は無い）
- **書き換える操作の間は SRAM を空ける**: NTFS のボリュームも SRAM を使うので、2 枚の面のままでは空きが 19KB（FAT は 30KB）しかなく、NTFS の書き込みの作業場（43KB）・
  exFAT・NTFS の流し読みの受け場（32KB、`fscore.c`。小さくして続ける手は無い）が取れなかった（設定が読めない・書けない、セーブのフォルダが作れない）。
  ファイルを書く・読む（小さいファイルを丸ごと）・フォルダを作る・消す・名前を変える間は、WAD の受け場と**後ろの面を返す**（`dg_sys.c` の `room_begin` / `room_end`）。
  Doom のタスクの中で描いていない間なので、表示は最後に写したフレームのまま。戻した後ろの面は別の番地になりうるので、最後のフレームを写してから
  `I_VideoBuffer` を付け替え、`V_RestoreBuffer()` と `setsizeneeded`（行の先頭の表を作り直す）。アリーナはアプリのタスクも触るので usb_lock の中で。
  実機（HDD の NTFS）: 設定を読む・書く、ゲームの途中で保存（`temp.dsg` に書いて `doomsav0.dsg` へ名前を変える、61KB）、読み込み（保存した所から続く）
- **分割・結合**: exFAT・NTFS のときの受け場を 32KB -> 8KB（`fsplit.c` の `SJ_CHUNK_FS`）。NTFS の結合で作業場に 520 バイト足りなかった
- 遠隔コマンド `MEM`（SRAM・PSRAM のアリーナの一覧をログへ。切り分け用）を足した

## 2026-10-24 撃てない・起動時にキーボードが載らない
- **ユーザー報告**: パッドで遊べるが武器が撃てない。**原因**: 設定（`default.cfg`）の読み込み（`m_config.c`）がキーの値を 128 未満しか受けず、ほかは 0 にしていた。
  doomgeneric の決まったキー（撃つ 0xa3・使う 0xa2・横歩き 0xa0 / 0xa1）は 128 以上で、書き出しはそのままの値なので、2 回目の起動から撃つ・使う・横歩きが効かなかった
  （動いている Doom の `key_fire` などを SWD で読んで 0 だった。パッドのボタン自体は届いていた）。`SGNANO` のとき 128〜255 はそのまま受ける。
  実機: 読み込んだあと 0xa3 / 0xa2 / 0xa0 / 0xa1、f で撃って弾が 50 -> 46
- **ユーザー報告**: キーボードが効かない。**原因**: 起動のとき、ハブの先のキーボード・パッドの列挙が TinyUSB の assert（`process_enumeration 1496` = 構成記述子の長さが 256 を越える。
  9 バイトの答えが前の中身のまま。大容量記憶の読み書きとの重なりと見ている）で打ち切られ、そのまま列挙されなかった（「一度マウントされた入力機器が戻らない」の見張りは
  一度も載らなかった機器には働かない）。**対処**: 打ち切りのあと接続の処理と大容量記憶の読み書きが 5 秒止んだらホストを作り直す（`usbwatch_abort_check`、1 回の起動で 2 回まで、
  Doom の間は待つ）。実機: 起動のとき 3 回打ち切られ、2 回目の作り直しでキーボード・パッドとも載った。重なりそのものは未調査
- **E1M1 を始めたら再起動した**（ユーザー報告、ウォッチドッグらしい）: UART のキー・パッドで遊んだ 15 分では再現しない。止まった場所の印はまだ取れていない

## 2026-10-24 音量・パッドだけで終わる
- ユーザー確認: パッドの操作（撃つ・使うを含む）は OK。「音量が少し低い」
- **音楽**: Doom の音楽の音量は 0〜127（メニューの 0〜15 の 8 倍、既定 8 = 64）で、そのまま `snd_master`（0〜127）に渡していたので既定で半分だった。2 倍にして既定で最大に
- **効果音**: 8 ビットの PCM を 14 ビットに広げて混ぜていた（既定の音量で全体の約 1/16）。16 ビットに広げて 4 倍に（重なってあふれた分は切る）
- **パッドだけで終わる**: 確かめの問い（「y を押すと終わります」など、m_menu.c の `messageToPrint && messageNeedsInput`）が出ている間は A = y・B = n。
  終わり方は START（メニュー）-> Quit Game -> A。押したときに知らせたキーを覚えておき、離すときも同じキーを知らせる

## 2026-10-24 遊んでいる間の再起動の正体（積み残し）
- ユーザー確認: パッドだけで Quit Game から抜けられる、音量は OK
- 2 回目の再起動で、止まったときの記録（`app/crash.c`）が取れた: **panic「ep 80 was already available」、core 1 の USB のタスク、`hcd_edpt_xfer` の中**（起動から約 14 分）。
  SDK の HCD は、制御転送の次の段（EP0 の IN）を出すとき、前の転送がまだ epx を使っていると思っていた
- **見立て**: epx の裏読み・その場の読み出し（`usbhw.c`）は「SETUP を出してから 200ms」だけ借りるのを控えていた。M33BEATOS では USB のタスクが遅れて、SETUP の完了を処理して
  次の段を出すのが 200ms より後になることがある（Doom が WAD を読み続けている間は特に）。その間に裏読みが epx を借り、制御転送の完了の印を消すと、HCD は epx が使用中のままと思う
- **対処**: 制御転送の最中（SETUP を出してから状態の段 = 長さ 0 の転送の完了まで。失敗・機器が外れた・打ち切り・作り直しでも下ろす）を `usbfix_ctrl_busy` で数え、
  最中は epx を借りない（3 秒たっても終わらなければ最中と見なさない）。`hcd_event_handler` を常に包む（以前は `SGNANO_USB_EVTRACE` のときだけ）。
  実機: 読み込みの時間は変わらず（23.6 秒）、E1M1 を始めて終わるまで。再起動が起きなくなったかは、遊んで確かめてもらう
- 【追記】Freedoom2 で、ゲームを始めてすぐまた同じ panic（core 1、USB のタスク、`hcd_edpt_xfer` の中）。制御転送の最中の印だけでは足りなかった。
  SDK の panic の出どころは `rp2040_usb.c` の `_hw_endpoint_buffer_control_update`: **epx の AVAILABLE（ハードのレジスタ）が立ったまま**次の段を出そうとした。
  HCD が EP0 の次の段を頼むのは前の段が終わったあとなので、立っているのは裏読み・その場の読み出し・打ち切りの残りと見ている（UART のキーで 2 分遊んでも再現せず）
- **守り**: EP0 の転送を HCD に渡す前に AVAILABLE が残っていたら、止めてから下ろす（`usbfix_epx_stale` に数える）
- **USB の出来事の記録**（`usbfix.c` の `usbtrace`、再起動をまたいで残る 64 件）: SETUP を出した・預けた・転送を頼まれた（どの道を通ったか）・完了・外れた・打ち切り、
  そのときの印（裏読み・制御転送の最中・SETUP を預かっている）。次の起動で `usbtrace_prev` に写す。**`python3 scripts/usbtrace.py`**（前の起動の分、`--now` でいま）で読む。SRAM は約 1.5KB
- 【追記】3 回目の再起動: panic「ep 02 was already available」（Doom のタスク）。USB の出来事の記録で、手前に USB メモリ（addr 1）への GET_STATUS（EP）2 回・
  Bulk-Only Mass Storage Reset（21 FF）・CLEAR_FEATURE 2 回（大容量記憶のリセットの立て直し、`usbata.c`）があり、そのあとの CBW（ep 02、31 バイト）を HCD に渡したところで panic。
  その前に EP0 の前の守り（0x16）も 1 回働いていた（残っていたのは 64 バイト・LAST・DATA1・AVAILABLE = こちらの読み出しの残りらしい）。
  立て直しの取り下げ（`tuh_edpt_abort_xfer`）は RP2350 の HCD が実装していないので、割り込みの枠（bulk もここ）の AVAILABLE がハードに残る
- **守り**: EP0 以外の転送も、HCD に渡す前にその EP の割り込みの枠に AVAILABLE が残っていたら下ろす（`usbhw_int_slot_clear_stale`、`usbfix_slot_stale`、記録 0x17）。
  立て直しに入った元（読み出しが止まった訳）は未調査

## 2026-10-24 外部実行ファイル DOOM.SGX に移した（ファームから外した）
- ユーザー指示: Doom のプログラムを外部実行ファイルとして切り離し、外部実行ファイルを支える ABI を揃える（mruby の Machine が持つものは全部、ほかにも要りそうなもの）。
  使い方のマークダウンも。そのあと「再配置可能に。複数タスクの協調動作もある」
- ABI と SDK: `docs/sgx_abi.md`（`sdk/sgx/`、ファームの側は `src/sgx/sgx.c`）。つなぎ（`apps/doom/`）は `src/doom/` から移して API の上に書き直した:
  ファイルは `stat`・`read_file`・`ra_*`・`write_file` など（書き換える操作の間の SRAM の空けはファームの側へ移した。後ろの面の番地が変わったら `dg_video_back_moved` が描き先を直す）、
  画面は `set_mode(7 | NO_TEXT)`・`bm_back` / `bm_present`、音楽は `seq_*`、効果音は `pcm_*`（混ぜるのはファームの側）、キーは `key_down`（USB）と `key`（`SGX_KEY_UART` の付いた UART の分）、
  パッドは `pad`、ゾーンは `psram_alloc` + `fb_borrow`、読み込みの画面は Doom のタスクが表示の面に直に描く（`font_glyph`）
- ファームから外したもの: `SGNANO_DOOM`、Doom の .data・.bss を PSRAM に置くリンカの手直し、`VIEW_DOOM`、PSRAM の末尾の 512KB の取り置き。ファイラーは WAD の Enter で `DOOM.SGX` を走らせる
- 実機（USB メモリの FAT32、`A:/DOOM.SGX` を親のフォルダに）: 像 537KB（.bss も）を 0x1110b5e0 に置いて起動、デモが正しく、約 40 フレーム / 秒（SWD でフレームの数を読んで）。
  F10 -> y で設定を書いて終わり、ファイラーへ戻る。ゾーンは 3.7MB + FB 2.4MB
- HDD の NTFS（D:）の `DoomFiles`（WAD と DOOM.SGX を同じフォルダに）でも起動・新しいゲームで保存（`doomsav0.dsg`）・設定を書いて終わり。
  はじめは後ろの面（64KB）が取れなかった: タスクの記録（SRAM 約 300 バイト）がテキスト面を開いたまま取られて、テキスト面を閉じた跡（52KB）とその上の空きを区切っていた。
  小さく長く持つもの（タスクの記録・同期のもの）はアリーナの空きの上の端から取る（`vmem` の `VMEM_PLANE_HIGH`、試しは `test_vmem.py`）
- 協調の試し `apps/multi`（タスク 2 つがミューテックスで 2000 まで数える・待ち行列・自分を子として spawn して share と終わりの値 7 を受け取る）: 実機で all ok。
  同じ像を 2 つ（親 0x1100bd80 と子）に置いて走った
- 【追記】ユーザー報告「DOOM.SGX、起動しないですね」: `DOOM.SGX` を直に Enter すると引数が無く、自分のフォルダの `freedoom1.wad` を探して（Doom2Files には無い）
  誤りで終わり、終わったらすぐファイラーへ戻るので何も出ないように見えた。直したもの: 引数が無ければ自分のフォルダから知っている名前の IWAD を探す（無ければ端末に知らせて 2 で終わる）・
  外部実行ファイルが 0 でない値で終わったら、テキストの画面にして端末を見せて何かキーを待つ（`rbrun.c` の `show_term`）・Doom の stderr（I_Error）を端末にも。
  実機: Doom2Files の DOOM.SGX を直に Enter して freedoom2.wad で起動、A:/ の DOOM.SGX（IWAD が無い）は知らせが出て待つ
- 【2026-10-29 修正】`A:/DOOM.SGX` のように WAD と別のフォルダに置いた `DOOM.SGX` を直に Enter しても、プログラムのフォルダのほか、
  その下の `DoomFiles` / `Doom2Files`、親の `DoomFiles` / `Doom2Files` も IWAD を探すようにした（`apps/doom/doom_app.c`）。
  実機: `A:/DOOM.SGX` から `A:/DoomFiles/freedoom1.wad` を見つけて起動（`R_Init` まで確認）。WAD の Enter からの起動も従来どおり

## 2026-10-25 設定をシステムのドライブ S: へ（ユーザー指示）
- 設定（`default.cfg`・`doomgenericdoom.cfg`）は `S:/SystemSettings/DoomSettings/`、Doom II の形の IWAD（freedoom2・doom2・plutonia・tnt）は `Doom2Settings/`。
  `doom_app.c` の `set_config_dir` がフォルダを作り、その置き場に無く前の置き場（WAD のフォルダ）にだけあれば写す（元は残す。64KB まで）。`m_config.c` の `GetDefaultConfigDir` が `dg_config_dir()` を返す
- セーブは S: が 4MB なので WAD のフォルダの `.savegame/` のまま（`M_GetSaveGameDir` を SGNANO のとき "./" の下に）
- 実機: freedoom1 で A:/DoomFiles の 2 つを写して起動、終わりに `S:/SystemSettings/DoomSettings/default.cfg`（1463 バイト）と `doomgenericdoom.cfg`（3019）を書いた。freedoom2 は `Doom2Settings` に同じく

## 2026-10-29 Doom II CD と Doom 1.666 の WAD
- Doom II: CD の `DOOM2CD/DOOM2.WAD` 14,612,688 バイト（1994 年の初期版。1.666 とみられる）を `A:/Doom2Files` に置いた。
  ホストの控えは `~/Project/doom2/DOOM2.WAD`、md5 `ea74a47a791fdef2e9f2ea8b8a9da13b`
- Doom 1: `DOOM1666.1` + `.2` を連結した LHa 自己解凍アーカイブから `DOOM1.WAD` 4,234,124 バイト
  （1.666 シェアウェア）を取り出して `A:/DoomFiles` に置いた。md5 `c428ea394dc52835f2580d5bfd50d76f`
- どちらもファイラーで WAD を選んで Enter で起動し、E1M1 まで確認。

## 2026-11-13 BGM を OPL2（YM3812）で（ユーザー指示）

- 形: Doom の側（`apps/doom/dg_opl.c`、GPL の側に閉じる）が、曲の MIDI（Freedoom は MThd、市販版は mus2mid で直したもの）を WAD の **GENMIDI**
  （DMX の OPL2 の音色表、175 音色 x 36 バイト）で YM3812 のレジスタ書き込みに直し、44.1kHz の待ちを挟んだ **メモリの VGM** にする。ファームは
  SGX ABI 5.5 の `music_play_mem`（メモリの VGM を鳴らす）を足しただけで、合成は VGM の合成のオーバーレイ（本体 + OPL、ymfm）がそのまま受け持つ。
- 直し方（DMX / Chocolate Doom の i_oplmusic.c に倣う。コードは自前）: 声 9。空きが無ければ離した声のいちばん古いもの、それも無ければいちばん古い声。
  2 声の音色（flags の 4）は 2 つ目の声が空いていれば。音程は 1/32 半音で、2 声目は fine_tuning / 2 - 64 ずらす、ピッチベンドは ±2 半音、F ナンバーと
  ブロックは周波数から計算。音量は DMX の音量の表でベロシティ x チャンネルの音量（CC7）x エクスプレッション（CC11）をキャリアの減衰にし、加算の音色は
  モジュレータも。打楽器（チャンネル 10）は GENMIDI の 128 + (鍵盤 - 35)。CC120 / 123 で全部離す。同じ値の書き込みは省く。ループする曲は
  データの頭へのループの点を付ける。
- 置き場: Doom はゾーンで PSRAM をほとんど使う。初めは受け場を倍々に広げ、作った VGM を曲ごとに持ち、ファームも写していたので、2 曲目で PSRAM が尽きて
  シーケンサーへ落ちた。いまは 1 周目で大きさを数えて 2 周目にちょうど取り、**写さずに鳴らす**（`SGX_MUSIC_NOCOPY`。止めるまで Doom が持つ。
  キャッシュの窓で書いた分はファームが書き戻してから読む）。ファームの VGM のスタックは SRAM が無ければ PSRAM の 8KB（以前は MP3 用の 64KB を取っていた）、
  チップの状態は PSRAM が無ければ SRAM。Doom の `DOOM_PSRAM_SPARE` は 384KB -> 512KB。
- 直せない・鳴らせないとき（GENMIDI が無い、区画が取れない、古いファーム）は今までのシーケンサー。`[doom] music: ...` を UART に出す。
- 試し: ホスト `scripts/test_doomopl.py`（合成の GENMIDI と MIDI を直して vgmhost で鳴らし、A4 = 440Hz・2 声の音色・ループの点）。
  実機: Freedoom Phase 1 でタイトルとデモの曲の切り替えでも OPL2（`[music] (memory): format 4`、区画は本体と OPL を取り戻す）。ユーザーが FM の音を聞いて確かめた。
  A: の DoomFiles・Doom2Files・直下の DOOM.SGX を入れ替えた。

## 2026-11-17 別のリポジトリに分けた

- ユーザーが https://github.com/antarcticlion/sgnano_doomgeneric に分けた（doomgeneric（GPL-2.0）・つなぎ `apps/doom`・SDK の写し・CI）。このリポジトリの `apps/doom` と `third_party/doomgeneric` は消した。
- 組み立て: このリポジトリの隣に `sgnano_doomgeneric` を置くと、`apps/CMakeLists.txt` の ExternalProject がそちらの手順（そちらのツールチェーンファイル）のまま組み、`build/sgx/doom.sgx` に写す。単体で組んだものとバイト単位で同じ（2026-11-17 に sha256 で確かめた）。
- ホスト試験 `scripts/test_doomopl.py` はそちらの `apps/doom/dg_opl.c` を使う（無ければ SKIP で失敗）。Freedoom の WAD（`third_party/freedoom-0.13.0`、git には入っていなかった手元のもの）は、ユーザー指示で sgnano_doomgeneric の `wads/freedoom-0.13.0/` へ移した（そちらでも git には入れない、`.gitignore`）。
- SDK の写し: SDK はこのリポジトリと 2 つの別のリポジトリにそれぞれ持つ（ユーザー決定: それぞれが単体で組めること）。こちらを直したら写しにも合わせる。

