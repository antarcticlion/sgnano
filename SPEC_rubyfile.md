# Ruby のファイル操作（仕様、2026-10-11）

`SPEC_mruby.md` の続き。Ruby のスクリプトから、ファイラーのドライブのファイルを読み書きする。CRuby に近い形（サブセット）。

## パス
- `"A:/dir/file.txt"` のように、**ファイラーのドライブ文字**（A: から）と `/` 区切り。`\` も `/` とみなす。
  **S: は内蔵フラッシュのシステムのドライブ**（2026-10-24、いつも S:。USB のドライブは S を飛ばして並ぶ）。`S:/SystemSettings`・`S:/SystemFiles`・`S:/SystemLogs` は
  消す・名前を変えると `Errno::EACCES`（中のファイルは自由に）。書くのは約 70 KB/s、FB を出していると 4KB を書くごとに約 56ms FB が消える
- ドライブ文字の無いパスは、いまのフォルダ（`Dir.pwd`）からの相対。`"/x"` はいまのドライブのルートから。`.` と `..` を解く。
- 実行を始めたときの `Dir.pwd` は、スクリプトのあるフォルダ。
- 名前は長い名前（UTF-8）でよい。FAT は大文字小文字を区別しない（下回りのとおり）。

## クラス（CRuby に近いサブセット）
- **`IO`**: `File` の親。`STDIN` `STDOUT` `STDERR` と `$stdin` `$stdout` `$stderr`。
  - `STDOUT` / `STDERR` への `write` `print` `puts` `p` `<<` は、いまの出力（テキスト面の端末と UART）へ。`Kernel#puts` などもいままでどおり。
  - **標準入力**はまだ無い。`$stdin.gets` / `Kernel#gets` は `nil`（入力の終わり）を返す。
    あとでファイラー側に入力（キーボードの行入力）を足すときは、`src/ruby/rbfile.c` の `rb_stdin_read` を差し替える。
- **`File < IO`**（モードは `"r"` `"w"` `"a"` `"r+"` `"w+"` `"a+"`、`"b"` を付けてもよい）
  - クラスメソッド: `open`（ブロック可）・`new`・`read`・`write`・`binread`・`binwrite`・`readlines`・`foreach`・`exist?`・`file?`・`directory?`・
    `size`・`zero?`・`delete`・`unlink`・`rename`・`basename`・`dirname`・`extname`・`join`・`expand_path`
  - インスタンス: `read(n=nil)`・`readpartial`・`gets(sep="\n")`・`readline`・`readlines`・`each_line`・`each`・`getc`・`getbyte`・`readchar`・`readbyte`・
    `each_byte`・`write`・`print`・`puts`・`printf` は無し・`<<`・`putc`・`pos`・`pos=`・`tell`・`seek`・`rewind`・`eof?`・`size`・`path`・`close`・`closed?`・
    `flush`・`sync`・`sync=`・`binmode`
- **`Dir`**: `mkdir`・`rmdir`・`delete`・`unlink`・`entries`・`children`・`each_child`・`exist?`・`pwd`・`getwd`・`chdir`（ブロック可）・`empty?`
- **例外**: `IOError`、`SystemCallError` の下に `Errno::ENOENT`（無い）・`Errno::EEXIST`（ある）・`Errno::EACCES`（書けない）・`Errno::ENOTEMPTY`（空でない）・
  `Errno::ENOTDIR`・`Errno::EISDIR`・`Errno::EROFS`（読み出し専用のドライブ）・`Errno::ENOSPC`・`Errno::EIO`（読み書きの失敗）、`NotImplementedError`（下回りに無い操作）。

## テキストとバイナリ
- mruby/c の文字列はバイトの並びなので、どちらも中身はそのまま（改行の変換はしない。CRuby の Unix と同じ）。
- `gets` は区切り（既定 `"\n"`）までのバイト。`getc` は UTF-8 の 1 文字、`getbyte` は 1 バイト（整数）。`read` はバイト。

## 作り
- **ファイルの中身は PSRAM の置き場に丸ごと読む**（開くとき。`"w"` は空から）。読み書き・`seek` はこの置き場の上で行い、
  **書き換えたら閉じるとき（`close`・`flush`）に丸ごと書く**（下回りは「同じ名前があれば置き換え」）。開けるのは同時に 8 個、1 個 4MB まで。
- 下回りは非同期（一覧・ストリーム読み・流し書き・消す・名前の変更・フォルダの作成）。Ruby の C のメソッドの中で始めて、
  終わるまで `app_yield()` を回して待つ（そのあいだ映像・USB・キーは動く）。
- 下回りの選び方: ドライブ文字 -> ファイラーのドライブ（USB の区画の FAT・exFAT・NTFS、フロッピー（FAT12）、CD（ISO9660）、S:（内蔵フラッシュの FAT12））。
  exFAT・NTFS のボリュームはファイラーが開いた枠 0 を使い、別の区画なら枠 1 に開く。`fs_poll()` は Ruby の実行中もファイラーのアプリ時間が毎フレーム呼んでいる（Ruby の側では呼ばない）。
- USB の完了から呼ばれる受け手（FAT・ISO9660 のストリームと流し書き）は SRAM（`src/ruby/rbfsio.c`）。モード1 なので PSRAM を読み書きしてよい。
- 前置き（prelude）: ブロックを取るメソッド・`IO` の便利なメソッドは Ruby で書き、実行のたびにコンパイルして利用者のプログラムより先に走らせる（実機で約 80ms、バイトコード約 6KB）。
  【実装の注記 2026-10-11】mruby/c ではクラスメソッドとインスタンスメソッドが同じ表に入るので、`File.read` / `f.read` のように同じ名前のものは受け手がクラスかどうか（`__cls?`）で振り分ける。前置きでは `ensure` を使わない（mruby/c で VM が止まった）。rescue で受けて投げ直す。

## 下回りの対応（2026-10-11 の時点）
| 操作 | FAT12/16/32 | exFAT | NTFS | CD |
|---|---|---|---|---|
| 一覧・読む | ○ | ○ | ○ | ○ |
| 書く（作る・置き換える）・消す | ○ | ○ | ○（$LogFile がきれいなとき） | 読み出し専用 |
| フォルダを作る | ○ | 第2段階で足す | 第3段階で足す | — |
| 名前を変える（同じフォルダの中） | ○ | 第2段階で足す | 第3段階で足す | — |
| 別のフォルダへ移す（`File.rename`） | 写して消す | 写して消す | 写して消す | — |
- 無い組み合わせは `NotImplementedError`。

## 試験
- ホスト試験: パスの解き方（`rb_path_resolve`）を C のままホストで。ファイル操作そのものは下回りが要るので実機で。
- 実機: `samples/ruby/fileio.rb`（書いて・読んで・追記して・行で読み・バイナリで読み書き・名前を変えて・フォルダを作って・消す）を
  FAT（USB メモリ）で。exFAT・NTFS は HDD の B: / C: で（`sgnano-test-write-drives`）。

【追記 2026-10-11】第 2 段階（exFAT のフォルダの作成・同じフォルダの中での名前の変更）を入れた（`fs_mkdir` / `fs_rename`、`src/fs/exfat_w.inc`）。
ホスト試験 `test_fs.py`（fsck.exfat・別の読み手）と、実機の HDD の B:（exFAT）で確かめた。NTFS は第 3 段階。
【追記 2026-10-11】第 3 段階（NTFS のフォルダの作成・名前の変更）も入れた（`src/fs/ntfs_w.inc`）。名前を変えると、このフォルダの名前（Win32・DOS）を外して
POSIX の名前 1 つにする（作るときと同じ）。日付・大きさは索引の項目から引き継ぐ。ホスト試験（ntfscheck・libntfs-3g）と実機の HDD の C:（NTFS）で確かめた。
