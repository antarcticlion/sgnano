#!/usr/bin/env bash
# UF2 書き込み補助。書き込みは手動運用のため、既定では手順を表示するだけ。
#   scripts/flash.sh              手順を表示
#   scripts/flash.sh /mnt/<drive> BOOTSEL でマウントされた Windows ドライブへ UF2 をコピー（方法 a）
#   scripts/flash.sh --picotool   usbipd-win 経由で picotool により書き込み（方法 b）
set -euo pipefail
cd "$(dirname "$0")/.."
UF2=build/sgnano.uf2
[ -f "$UF2" ] || { echo "$UF2 がありません。先に scripts/build.sh を実行してください" >&2; exit 1; }

case "${1:-}" in
  "")
    cat <<MSG
UF2: $(realpath "$UF2")

(a) BOOTSEL でマウントされた Windows ドライブへコピー
    1. BOOTSEL ボタンを押しながら USB 接続（または RESET）→ RP2350 ドライブがマウントされる
    2. scripts/flash.sh /mnt/<ドライブ文字>   （または エクスプローラー / cp で UF2 をコピー）
       ※ ドライブが /mnt/<x> に見えない場合: sudo mkdir -p /mnt/<x> && sudo mount -t drvfs <X>: /mnt/<x>

(b) usbipd-win + picotool
    Windows(管理者PowerShell): usbipd list → usbipd bind --busid <BUSID> → usbipd attach --wsl --busid <BUSID>
    WSL: picotool load -f build/sgnano.elf && picotool reboot
    （BOOTSEL 状態のデバイスを attach すること。実行中の sgnano は USB-CDC のみで
      picotool 用のリセット対応(stdio_usb reset interface)は入れていない）
MSG
    ;;
  --picotool)
    picotool load -f build/sgnano.elf
    picotool reboot
    ;;
  *)
    [ -d "$1" ] || { echo "$1 がありません（BOOTSEL 状態か確認してください）" >&2; exit 1; }
    cp "$UF2" "$1"/ && sync && echo "コピー完了: $1"
    ;;
esac
