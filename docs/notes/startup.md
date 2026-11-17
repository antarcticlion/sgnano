# ブート自動起動（Startup.cfg）

2026-11-07 に追加。電源投入後、`S:/SystemSettings/Startup.cfg` があれば
バナー終了後に指定のプログラムを 1 回だけ起動する。実装は `src/filer/fstartup.c`、
コミットは `e505d63`（起動）と `4ee8d7a`（書き込み時の core1 halt）。

## 設定

```text
# S:/SystemSettings/Startup.cfg
enabled = 1
path = S:/bin/XSYS35.SGX
args = S:/bin -kiosk
```

- `path` は絶対パス。`args` は空白区切りで最大 4 個（`"..."` で囲める）。
- `enabled = 0` またはファイル削除で無効。ファイルが無ければ従来どおりファイラー。
- `.sgx` だけでなく `.rb` / `.mrb` も起動できる。
- 設定と引数は PSRAM、コードはフラッシュ。SRAM 使用量は増えない。

## 実機の現在の状態（2026-11-07 引渡し時）

- `Startup.cfg` が有効で、起動すると `S:/bin/XSYS35.SGX S:/bin -kiosk` が動く。
- `S:/SystemSettings/kiosk.cfg`: `idle_ms = 60000`、`dev_exit = 1`。
- XSYS35 の開発用抜け道: `Ctrl+Alt+Shift+Q` を 2 秒、または UART から `~q` で
  ファイラーへ戻る（`dev_exit = 1` のときだけ）。
- ファイラーへ戻したいだけなら、起動バナー（8 秒）の間に何かキーを押す。
  自動起動をキャンセルしてファイラーに入る。設定を変えるならそこで
  `Startup.cfg` の `enabled` を 0 にするか、ファイルを消す。
- `~q` は UART から `~` の後 1.5 秒以内に `q`。`scripts/console.sh -k '~q'` で送れる
  （0.2 秒間隔なので間に合う）。

## 異常起動時の扱い

- 前回がクラッシュ（`crash_last`）またはウォッチドッグの時限切れだった場合、
  自動起動しない。ログは
  `[startup] skipped after an abnormal boot (crash=... reason=...)`。
- その次の通常起動では自動起動が戻る。
- アプリが終了しても自動で再起動はしない（開発用の抜け道でファイラーへ戻れる）。

## 書き込み

- キオスク実行中に `flash_chunks.sh` で書き込むと、core1 のアプリが消去・書き込みに
  干渉して途中で止まることがあった。`scripts/flash_chunks.sh` は各チャンクで
  `targets rp2350.cm0 rp2350.cm1` を選んで両コアを halt してから書くようにした。
- アプリが動いている状態で書き込むときは、先にファイラーへ戻すか、この版の
  `flash_chunks.sh` を使う。
- `flash_swd.sh` の一括 `program` は、大きいイメージで消去がタイムアウトすることが
  ある。その場合は `flash_chunks.sh` を使う。

## 注意

- `Startup.cfg` は S: 上にありファイラーから編集できる。セキュリティ境界ではない。
- 他のエージェントがファイラーを常用する場合は、`enabled = 0` にしておくのが安全。
- `kiosk.cfg` は XSYS35 側の設定で、sgnano は解釈しない。
