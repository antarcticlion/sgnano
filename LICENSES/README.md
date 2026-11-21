# 外部の部品のライセンス

sgnano のファームウェアと、このリポジトリの SGX（外部実行ファイル）が使っている外部の部品です。
ファームウェアに入っているものは、本体のファイラーのライセンスの画面と、ルートの `LICENSE` の 3 にも全文を載せています。

## ファームウェアに入っているもの

| 部品 | 用途 | ライセンス | ファイル |
|---|---|---|---|
| Raspberry Pi Pico SDK 2.2.0 | 土台の SDK | BSD-3-Clause | `pico-sdk.txt` |
| CMSIS（Pico SDK の中） | Cortex-M33 のヘッダ | Apache-2.0 | `cmsis-Apache-2.0.txt` |
| newlib（newlib-nano） | C ライブラリ | BSD 系（複数） | `newlib.txt` |
| TinyUSB | USB ホスト | MIT | `tinyusb.txt` |
| lwIP 2.2 | TCP/IP | BSD-3-Clause | `lwip.txt` |
| Mbed TLS 3.6.2 | TLS 1.2、SHA | Apache-2.0（GPL-2.0 との二重。sgnano は Apache-2.0 を選ぶ） | `mbedtls.txt` |
| mruby 4.0.0（同梱の mrbgem を含む） | Ruby | MIT | `mruby.txt` |
| mruby-json | Ruby の JSON | MIT | `mruby-json.txt` |
| mruby-onig-regexp | Ruby の正規表現 | MIT（上流の README と mrbgem.rake による） | `mruby-onig-regexp.txt` |
| Onigmo 6.2.0 | 正規表現のエンジン | BSD-2-Clause | `onigmo.txt` |
| MicroPython 1.29.0 | Python | MIT | `micropython.txt` |
| SG BASIC | BASIC | MIT（Microsoft BASIC 6502 の元のソースも MIT、著作権表示は別記） | `sgbasic.txt`・`sgbasic-microsoft.txt` |
| ymfm | VGM の FM 音源 | BSD-3-Clause | `ymfm.txt` |
| libvgm（一部の音源の core） | VGM の PCM 音源 | BSD-3-Clause | `libvgm.txt` |
| Tetorica OPNA rhythm sounds | YM2608 のリズムの代替 ROM | BSD-3-Clause | `opna-rhythm.txt` |
| minimp3 | MP3 の解読 | CC0-1.0 | `minimp3.txt` |
| stb_vorbis | OGG の解読 | MIT / Public Domain | `stb_vorbis.txt` |
| stb_image | PNG・JPEG・GIF の解読 | MIT / Public Domain | `stb.txt` |
| miniz | gzip・zlib・deflate（VGZ・ZIP・tar.gz）の圧縮と展開 | MIT | `miniz.txt` |
| libbzip2 1.0.8 | bzip2（.bz2・ZIP の方式 12） | bzip2 のライセンス（BSD 系） | `bzip2.txt` |
| LZMA SDK 26.06 | LZMA・LZMA2・xz・7z | パブリックドメイン | `lzma-sdk.txt` |
| sgnanoime | IME（日本語・英語・韓国語・中国語） | BSD-2-Clause（取り込んだ部品は別記） | `sgnanoime.txt`・`sgnanoime-third-party.md` |
| Unicode Character Database（Unihan） | sgnanoime の倉頡の表 | Unicode License V3 | `unicode-unihan.txt` |
| EmbUniFont | フォント ROM の形と道具 | MIT | `EmbUniFont.txt` |
| GNU Unifont | フォント ROM の字形 | SIL OFL 1.1 | `GNU-Unifont-OFL-1.1.txt` |

## SGX（別のリポジトリ）

`DOOM.SGX` と `wav2mp3.sgx` のソースとビルドの手順は、このリポジトリには入れていません。
[`sgnano_doomgeneric`](https://github.com/antarcticlion/sgnano_doomgeneric) と
[`sgnano_wav2mp3`](https://github.com/antarcticlion/sgnano_wav2mp3) にあります。
S: のドライブの初期値に入っている `wav2mp3.sgx` は LAME を静的にリンクしているので、ライセンス文をここに置いています。

| 部品 | 使う SGX | ライセンス | ファイル |
|---|---|---|---|
| doomgeneric | `DOOM.SGX`（`sgnano_doomgeneric`） | GPL-2.0 | `doomgeneric-GPL-2.0.txt` |
| LAME 3.100 | `wav2mp3.sgx`（`sgnano_wav2mp3`、静的にリンク） | LGPL-2.0-or-later | `lame-LGPL.txt` |

`DOOM.SGX` で遊ぶには IWAD（Freedoom など）が別に要ります。Freedoom は BSD-3-Clause で、[freedoom.github.io](https://freedoom.github.io/) から入手できます。
