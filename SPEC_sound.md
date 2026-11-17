# サウンド（発音マネージャ・シーケンサー・Ruby の Sound）

2026-10-18。方向性はユーザーの指示（`C:\Temp\sgnano_sound.txt`）による。
2026-10-29 に 4 チャンネル目のドラム用としてノイズ（RNG の波形・WT と同じ音程と EG）を足した。
同じ日に、シーケンサーが SGT（SGNO TRACKER の曲）も再生できるようにした（ABI 1.5）。

## 分担

| 層 | どこで | ファイル | 役目 |
|---|---|---|---|
| 発音マネージャ | **core0**（タイマーの割り込み 2kHz、優先度 0x80） | `src/audio/sndmgr.c` `sndmgr.h` `sndenv.h` `sndtabs.h` | I2S のポート（PT8211 のボイス）ごとのモードとエンベロープ。ノートオン・オフ、音量、ADSR を受けてポートを操作する |
| シーケンサー | **core1 の独立したタスク**（M33BEATOS、優先度 4） | `src/audio/sndseq.c` `sndseq.h` | 曲データ（SMF のフォーマット 0・1、SGT のバージョン 1・2）を時刻に合わせて読み、マネージャへ送る。BGM 1 本と効果音のフレーズ 2 本 |
| Ruby の口 | core1 のアプリのタスク | `src/ruby/mrb/rbsound_mrb.c` | `Sound` モジュール |
| 下回り | | `src/audio/audio.c` | いままでの音源（波形・音量の段・PIO の分周・ストリーム） |

口（`snd_*`）は core1 から呼び、命令は待ち行列で core0 へ渡す。core1 の側で MIDI の値を「音量の段（Q8）」「Hz」「エンベロープの増分（Q16）」に直す
（浮動小数点と表はここ）。core0 の割り込みは整数だけでエンベロープを進め、音量の段を切り替える（`audio_set_voice`）。

## ポートのモード

| モード | 中身 |
|---|---|
| `SND_MODE_WT` | ウェーブテーブル（いままでの音源そのもの） |
| `SND_MODE_PCM` | Amiga の Paula のように PCM を流しながら PIO の分周で音程を作る（2026-10-30）。符号付き 8 ビットの 32 サンプルをループし、音程・音量・EG・パンは WT と同じ経路 |
| `SND_MODE_STREAM` | CD のように決まったレートで流し続ける（中身は `audio_stream_*`。マネージャはそのボイスに触らない） |
| `SND_MODE_NOISE` | RNG から作った白色ノイズの波形（`AUDIO_WAVE_NOISE`）を、WT と同じ音程・音量・EG で鳴らす（2026-10-29。4ch 目のドラム用） |

ポートの数は `snd_channels()`（いまは 4。`SGNANO_DDC_PIO2` で PIO2 を DDC に使っているため）。

### ノイズ（2026-10-29）

- `audio_init()` で **RNG（RP2350 の TRNG、`get_rand_32()`）から 32 サンプルの波形を 1 回だけ作る**（`audio_wave_noise`、振幅 ±30000）。
  再生中に乱数を引き続けるのではなく、WT と同じ 32 サンプルのリングを音程に合わせて回すので、ピッチのあるノイズ（周期的なざらつき）になる
- 音程は `audio_set_freq()`（WT と同じ PIO の分周）、音量・ADSR・ベロシティは `sndmgr` の WT と同じ経路。波形だけをノイズに差し替える
- `snd_set_mode(ch, SND_MODE_NOISE)` で入る。ノイズモードの間は `snd_wave()` の値ではなく常に `AUDIO_WAVE_NOISE` を使う。
  `snd_set_mode(ch, SND_MODE_WT)` で戻ると、それまでの `snd_wave()` の波形に戻る
- どのポートでも使える（トラッカーはノイズ音色を使うトラックだけこのモードにする）。プリセット表（`precomp`）が 1 波形ぶん増えるので SRAM は約 4KB 増

## エンベロープ（SID に合わせる）

- アタックは直線で 0 -> 255、ディケイ・リリースは SID の近似の指数カーブ（レベル 93・54・26・14・6 を下回るたびに 1 段の時間が 2・4・8・16・30 倍）、
  サステインはレベルの割合
- 時間は SID の表（アタック 2ms〜8s、ディケイ・リリース 6ms〜24s の 16 段）。**パラメタは MIDI の解像度（0〜127）**で受け、16 段の間を対数で補間する
  （0 = SID の 0 段、127 = 15 段）。128 段ぶんの時間は前もって表にしてある（`sndtabs.h`）
- 音量は、ベロシティ・CC7 ボリューム・CC11 エクスプレッションを GM の推奨（40log10(x/127) dB）で足し、エンベロープのレベル（20log10）と合わせて段に直す

## シーケンサー

- SMF のフォーマット 0・1（トラック 16 本まで）。曲データは PSRAM に写して持つ（Ruby の GC と関係なく）
- **SGT（SGNO TRACKER の曲、v1 / v2）も BGM として再生する**（2026-10-29、ABI 1.5）。4 トラックを 4 ポートへ直接割り当て、
  トラッカーの音色 0〜8（WT 8 種類 + NOISE）と効果 A/C/D/F/H/P/Q を扱う。BPM / スピードは SGT の値を tick ごとに進める
- SGT は 4 ポートを使うため、SGT の BGM 中は `Sound.sfx`（効果音）を受けない。SMF の効果音は従来どおり
- BGM は 16 の MIDI チャンネルを空いているポートへ割り当てる（同じチャンネルが前に使ったポートを優先、無ければいちばん古い音を止めて使う）
- 効果音のフレーズは指定のポートを占有する（BGM はそのポートを使わない。終わったら返す）。`reserve` でポートを BGM から外せる。
  `reserve(ch, true)` は、そのポートで BGM が鳴っていれば、いま止めて返す（効果音がすぐ使える）。`reserve(ch, false)` で BGM に戻す。
  返すときはそのポートを WT モードに戻し、BGM の次の音で波形・ADSR を送り直す（ノイズの効果音の音色が残らない）。
  起動時から固定で予約すると 4 チャンネルの BGM が 3 声になるので、効果音の間だけ借りる使い方ができる（2026-10-29、jumps の修正）
- 音色は GM のプログラムチェンジを、こちらの波形と ADSR に置き換える（`seq_gm_patch` の表）。**チャンネル 10（ドラム）はノイズの短い一発**として鳴らす
  （2026-10-29。`SND_MODE_NOISE` + 波形 NOISE + ADSR 0/18/0/12。音程はノート番号のままで、ドラムごとの音色の違いはまだ無い）
- 扱う出来事: ノートオン・オフ、CC7・CC11・CC64 サステイン・CC121 リセット・CC120 / 123 全部止める、RPN 0（ピッチベンドの幅）、ピッチベンド、
  プログラムチェンジ、テンポ。CC10 パンも左右のゲインに反映する（2026-10-30。中央は両方そのまま、端で反対側を 0 にするバランス）
- 速さの倍率（25〜400%）、一時停止（鳴っている音はリリース）、くり返し

## Ruby の Sound

初めて使ったときに音を開き（消音を解く）、Ruby の終わり（ESC で止めたときも）に閉じる（`rbrun.c`）。

| メソッド | 意味 |
|---|---|
| `Sound.channels` | ポートの数 |
| `note_on(ch, note, vel = 100)` / `note_off(ch)` | note 0..127（69 = A4 = 440Hz） |
| `volume(ch, v)` / `expression(ch, v)` / `pan(ch, v)` / `master(v)` | CC7・CC11・CC10（0 = 左、64 = 中央、127 = 右）・全体（0..127） |
| `adsr(ch, a, d, s, r)` | 各 0..127 |
| `wave(ch, Sound::SQUARE など)` / `program(ch, gm)` | 波形を直に（`Sound::NOISE` もある）・GM の音色の置き換えで |
| `bend(ch, -8192..8191, range = 2)` / `freq(ch, hz)` | ピッチベンド・Hz で直に |
| `all_off` | 全ポートをリリース |
| `mode(ch)` / `set_mode(ch, Sound::WT / STREAM / NOISE_MODE / PCM)` | `PCM` は 32 サンプルのループ（`pcm` で標本を渡す）。`NOISE_MODE` は 4ch 目のドラム用 |
| `pcm(ch, data)` | PCM の標本。符号付き 8 ビットの String を 1〜32 バイト（32 未満は 0 で埋める）。ループする |
| `level(ch)` / `phase(ch)` | エンベロープのレベル（0..255）と段 |
| `play(data_or_path, loop = false)` / `stop` / `pause` / `resume` | BGM（SMF / SGT。文字列の中身か、ファイルのパス） |
| `playing?` / `paused?` / `position` / `length` | ms |
| `tempo(percent)` | 速さ |
| `sfx(data_or_path, ch)` / `sfx_stop(ch)` / `sfx_playing?(ch)` / `reserve(ch, bool)` | 効果音のフレーズ |

範囲外の値は ArgumentError、待ち行列が 2ms 埋まったままなら RuntimeError。見本は `samples/ruby/sound.rb`（SMF）と `samples/ruby/sound_sgt.rb`（SGT）、曲は `samples/sound/WTF4CH.mid`（4 チャンネル・45 秒）と `samples/sound/NOISE_ROCK.SGT`（ノイズ・ドラムのロック、約 70 秒）。

## ファイラーの SMF / SGT プレイヤー（2026-10-18、SGT は 2026-10-29）

一覧で `.mid` / `.smf` / `.sgt` を Enter で、窓を出して鳴らす（`src/filer/fsmf.c`）。ファイルを PSRAM へ読み込み（`fload`、1MB まで）、`sndseq_play` に渡して（シーケンサーが写すので読み込みの置き場はすぐ返す）、
経過・長さ・バーを出す。Space で一時停止、q / ESC で止めて閉じる、終わったら「終了しました」と出して何かキーで閉じる。音は開いている間だけ開く（`snd_open` / `snd_close`）。
**開いている間は FB を隠す**（ファイラーには Ruby のような「取得の間 core1 を待たせる」仕組みが無く、シーケンサーのタスクがアプリ時間の外で PSRAM の曲データとフラッシュのコードを使うので、
FB を出したままだと同期が乱れた。ユーザー報告）

## 試し

- ホスト: `scripts/test_sound.py`（`scripts/host_sound/`）。エンベロープの時間が表と合うこと、サステイン、WTF4CH.mid と NOISE_ROCK.SGT のノートオン・オフの数・重なり・
  同時発音数・長さ（45.099 秒 / 70.397 秒）を Python の読み手と比べる。チャンネル 10 のドラム 2 発と CC10（左・右）を入れた SMF も作り、
  ノイズモードへの切り替えとパンの命令が呼ばれることを見る（2026-10-30）
- 実機（2026-10-18）: `sound.rb` が最後まで鳴り（走り終えて 50.7 秒）、終わりで消音（`mute_all(true)`）。間の `underrun=0`
- 実機（2026-10-29）: `Sound.set_mode(3, Sound::NOISE_MODE)` のあと `Sound.mode(3)` が 3 を返し、`Sound.note_on(3, ...)` を
  4 音（36・40・43・36）続けて例外なく鳴らせた（1.4 秒、ヒープ 96,676 B、スタック 6,108 B）。**スピーカーでの聴感はまだユーザー未確認**
- 実機（2026-10-30）: チャンネル 10 にドラム 8 発を入れた `zzzzz.mid` をファイラーの SMF プレイヤーで開き、`[filer] SONG: playing zzzzz.mid (2.000 s)` から `done` まで進んだ（underrun 0）
- 実機（2026-10-30、REPL）: `Sound.set_mode(2, Sound::PCM)` -> `Sound.pcm(2, ([100]*16 + [-100]*16).pack("c*"))` ->
  `Sound.pan(2, 0)` -> `Sound.adsr(2, 0, 30, 110, 40)` -> `Sound.note_on(2, 69, 100)` を例外なく実行。`Sound.mode(2)` が 1（PCM）、
  `Sound.phase(2)` が `:sustain`。`Sound.pan(2, 127)` のあと `note_off`、`set_mode(2, WT)` も通った（underrun 0）。
  **スピーカーでの聴感はまだユーザー未確認**

## あとで

- ~~シーケンサーのチャンネル 10（ドラム）をノイズへ割り当てる~~（2026-10-29 に対処: ノイズ + 短い ADSR。ホスト試験は 2 発のドラム SMF、実機は `.mid` プレイヤーで確認）、~~PCM モード・パン~~（2026-10-30 に対処）、MIDI の入出力との統合
- 6 ボイス（基板で DDC の SDA / SCL を入れ替えれば PIO2 を音源に戻せる）
