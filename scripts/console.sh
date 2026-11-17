#!/usr/bin/env bash
# シリアルコンソール（デバッグプローブの UART ブリッジ、既定 /dev/ttyACM0）。
#
#   scripts/console.sh                  ログを流しっぱなしで表示（Ctrl-C で終了）
#   scripts/console.sh -t <秒>          その秒数だけ表示して終わる
#   scripts/console.sh -t <秒> -o <file> その秒数だけファイルへ記録
#   scripts/console.sh -k <文字列>      キーを送る（例: -k vvo）
#   scripts/console.sh -r -t 8 -o <file> リセットしてから記録（起動ログを取る）
#   scripts/console.sh -k v -t 5        キーを送ってから5秒ぶん記録
#   scripts/console.sh -k '{F1}{DOWN}x' 特殊キーは {名前} で（下の keyseq）
#
# 環境変数: SGNANO_TTY（既定 /dev/ttyACM0）、SGNANO_BAUD（既定 921600）
set -eu
TTY=${SGNANO_TTY:-/dev/ttyACM0}
BAUD=${SGNANO_BAUD:-921600}
KEYS=""; SECS=""; OUT=""; RESET=""

while [ $# -gt 0 ]; do
    case "$1" in
    -k) KEYS=$2; shift 2 ;;
    -t) SECS=$2; shift 2 ;;
    -o) OUT=$2;  shift 2 ;;
    -r) RESET=1; shift 1 ;;
    *)  echo "使い方: $0 [-k <keys>] [-t <sec>] [-o <file>]" >&2; exit 1 ;;
    esac
done

[ -c "$TTY" ] || { echo "$TTY がありません（usbipd で attach したか確認）" >&2; exit 1; }
stty -F "$TTY" "$BAUD" raw -echo

if [ -n "$RESET" ]; then
    "$(dirname "$0")/flash_swd.sh" --reset >/dev/null 2>&1 || true
fi

CATPID=""
if [ -n "$SECS" ]; then
    # サブシェルに入れると wait できないので、直接バックグラウンドにする
    if [ -n "$OUT" ]; then
        timeout "$SECS" cat "$TTY" > "$OUT" &
    else
        timeout "$SECS" cat "$TTY" &
    fi
    CATPID=$!
    sleep 0.3
fi

# 特殊キーは {名前} で書く（2026-10-05）。エスケープ列をひとまとまりで送る:
#   {UP} {DOWN} {LEFT} {RIGHT} {PGUP} {PGDN} {HOME} {END} {INS} {DEL} {F1}..{F12} {S-F1}..{S-F12} {S-UP} {S-DOWN} {S-LEFT} {S-RIGHT} {A-F1}..{A-F12} {C-F1}..{C-F12} {ESC} {ENTER} {BS} {TAB}
#   {LBRACE} {RBRACE}（波かっこそのもの）
keyseq() {
    case "$1" in
    UP) printf '\033[A' ;; DOWN) printf '\033[B' ;; RIGHT) printf '\033[C' ;; LEFT) printf '\033[D' ;;
    HOME) printf '\033[1~' ;; INS) printf '\033[2~' ;; DEL) printf '\033[3~' ;; END) printf '\033[4~' ;;
    PGUP) printf '\033[5~' ;; PGDN) printf '\033[6~' ;; MENU) printf '\033[29~' ;;
    IME) printf '\000' ;;                     # Ctrl+Space（NUL。ファームが IME のオン・オフにする）
    S-UP) printf '\033[1;2A' ;; S-DOWN) printf '\033[1;2B' ;; S-RIGHT) printf '\033[1;2C' ;; S-LEFT) printf '\033[1;2D' ;;
    F1) printf '\033OP' ;; F2) printf '\033OQ' ;; F3) printf '\033OR' ;; F4) printf '\033OS' ;;
    F5) printf '\033[15~' ;; F6) printf '\033[17~' ;; F7) printf '\033[18~' ;; F8) printf '\033[19~' ;;
    F9) printf '\033[20~' ;; F10) printf '\033[21~' ;; F11) printf '\033[23~' ;; F12) printf '\033[24~' ;;
    S-F1) printf '\033[1;2P' ;; S-F2) printf '\033[1;2Q' ;; S-F3) printf '\033[1;2R' ;; S-F4) printf '\033[1;2S' ;;
    S-F5) printf '\033[15;2~' ;; S-F6) printf '\033[17;2~' ;; S-F7) printf '\033[18;2~' ;; S-F8) printf '\033[19;2~' ;;
    S-F9) printf '\033[20;2~' ;; S-F10) printf '\033[21;2~' ;; S-F11) printf '\033[23;2~' ;; S-F12) printf '\033[24;2~' ;;
    # Ctrl・Alt つきの F5〜F12（2026-10-23。xterm の修飾の値: Alt 3・Ctrl 5。ファイラーの Alt+F5 = 画面の写し、Ctrl+F5 = FB の保存）
    [AC]-F1|[AC]-F2|[AC]-F3|[AC]-F4)
        m=3; [ "${1%%-*}" = C ] && m=5
        case "${1#*-}" in F1) n=P ;; F2) n=Q ;; F3) n=R ;; F4) n=S ;; esac
        printf '\033[1;%s%s' "$m" "$n" ;;
    [AC]-F5|[AC]-F6|[AC]-F7|[AC]-F8|[AC]-F9|[AC]-F10|[AC]-F11|[AC]-F12)
        m=3; [ "${1%%-*}" = C ] && m=5
        case "${1#*-}" in F5) n=15 ;; F6) n=17 ;; F7) n=18 ;; F8) n=19 ;; F9) n=20 ;; F10) n=21 ;; F11) n=23 ;; F12) n=24 ;; esac
        printf '\033[%s;%s~' "$n" "$m" ;;
    ESC) printf '\033' ;; ENTER) printf '\r' ;; BS) printf '\b' ;; TAB) printf '\t' ;;
    PRINT) printf '\033[32~' ;; A-PRINT) printf '\033[32;3~' ;;   # PrintScreen / Alt+PrintScreen（2026-10-29。UART から試す用）
    LBRACE) printf '{' ;; RBRACE) printf '}' ;;     # 波かっこそのもの（Ruby のブロックなどを打ち込むとき、2026-10-11）
    *) echo "知らないキーの名前: {$1}" >&2; return 1 ;;
    esac
}

if [ -n "$KEYS" ]; then
    # 1キーずつ間を空けて送る（受け側は1フレーム周期のループで拾う）
    i=0
    while [ $i -lt ${#KEYS} ]; do
        ch=${KEYS:$i:1}
        if [ "$ch" = "{" ] && [[ "${KEYS:$i}" == *"}"* ]]; then
            rest=${KEYS:$((i+1))}; name=${rest%%\}*}
            keyseq "$name" > "$TTY"
            i=$((i + ${#name} + 2))
        else
            printf '%s' "$ch" > "$TTY"
            i=$((i + 1))
        fi
        sleep 0.2
    done
fi

if [ -n "$SECS" ]; then
    wait "$CATPID" 2>/dev/null || true
    [ -n "$OUT" ] && { echo "記録しました: $OUT ($(wc -l < "$OUT") 行)"; }
elif [ -z "$KEYS" ]; then
    cat "$TTY"
fi
