#!/usr/bin/env bash
# OpenOCD + PicoProbe(CMSIS-DAP) で書き込む / デバッグ用に接続する。
#
#   scripts/flash_swd.sh                 build/sgnano.elf を書き込んでリセット
#   scripts/flash_swd.sh <file.elf>      指定した ELF を書き込む
#   scripts/flash_swd.sh --attach        書き込まずに接続したままにする（gdb 用、:3333）
#   scripts/flash_swd.sh --reset         リセットするだけ
#   scripts/flash_swd.sh --rescue        QSPI が壊れてブートROMから進まないときの復旧
#
# 事前準備（WSL の場合）: Windows 側で PicoProbe を WSL へ渡す
#   usbipd list                          BUSID を調べる（"CMSIS-DAP" など）
#   usbipd bind   --busid <BUSID>        （初回のみ、管理者権限）
#   usbipd attach --busid <BUSID> --wsl
# 配線: PicoProbe の SWCLK/SWDIO/GND を、ボードのデバッグ端子へ。
set -eu

OPENOCD=${OPENOCD:-$HOME/Project/openocd/src/openocd}
OPENOCD_SCRIPTS=${OPENOCD_SCRIPTS:-$HOME/Project/openocd/tcl}
ADAPTER_SPEED=${ADAPTER_SPEED:-5000}
IFACE=${IFACE:-interface/cmsis-dap.cfg}
TARGET=${TARGET:-target/rp2350.cfg}

if [ ! -x "$OPENOCD" ]; then
    echo "OpenOCD が見つかりません: $OPENOCD" >&2
    echo "RP2350 に対応した Raspberry Pi 版が要ります（tcl/target/rp2350.cfg を持つもの）。" >&2
    echo "環境変数 OPENOCD / OPENOCD_SCRIPTS で場所を指定できます。" >&2
    exit 1
fi

run() { echo "+ $OPENOCD -s $OPENOCD_SCRIPTS -f $IFACE -f $TARGET $*"; "$OPENOCD" -s "$OPENOCD_SCRIPTS" -f "$IFACE" -f "$TARGET" "$@"; }

# 【重要】走らせる前にデバッグを切る（DHCSR の C_DEBUGEN を落とす）。
# TinyUSB の TU_ASSERT は「デバッガが繋がっているときだけ」BKPT で止まる作りなので、
# プローブを繋ぎっぱなしにしていると、列挙の assert ひとつで CPU ごと止まり
# 「フリーズした」ように見える。実機本来の動き（assert は false を返すだけ）にするため、
# 最後に C_DEBUGEN を落としてから離れる。DBGKEY=0xA05F。
# 【2026-10-02】**両コアとも**落とす。DHCSR はコアごとにあり、OpenOCD は接続するだけで両コアの
# C_DEBUGEN を立てる（実測で 0x01100001）。以前は core0 にしか書いていなかった。
DISARM_BOTH=(-c "rp2350.cm0 mww 0xE000EDF0 0xA05F0000" -c "rp2350.cm1 mww 0xE000EDF0 0xA05F0000")

# 【重要・2026-10-02】リセットは `cold_reset`（DP の CDBGRSTREQ でチップ全体を1回だけリセット）で行う。
# OpenOCD の `reset` は、両コアを SMP として扱い、**core0 -> core1 の順に1コアずつ SYSRESETREQ を書く**
# （rp2350.cfg の ocd_process_reset_inner）。core0 のリセットでファームが動き出し、core1 を起動したあとに
# core1 へのリセットが遅れて届くと、**core1 だけがブートROM に戻り**、そこで起動の合図を待って眠り続ける
# （描画が止まり underrun が増え続ける。申し送りの「core1 が描画しない」の正体。PC=0x000000d8）。
# 書き込み 9回に1回程度で起きていた。cold_reset なら両コアが同時に起動し直すので起きない（15回中0回）。
# なお core0 だけの構成（USE_CORE cm0）で reset すると、周辺回路が戻らず1回おきに起動しなくなった。

# 【2026-10-04】リセットする前に、コンソールから ` を送って CD の再生を止める（1秒待つ）。
# 光学ドライブは、読み出しの途中でホストがリセットされると固まり、バスリセットでも BOT のリセットでも、
# ハブのポートの電源の入れ直しでも戻らず、抜き挿しが要った。再生していなければ ` は何もしない。
# SGNANO_FLASH_NO_CD_STOP=1 で飛ばす（ボードが止まっているときなど）。
stop_cd() {
    [ "${SGNANO_FLASH_NO_CD_STOP:-0}" = 1 ] && return 0
    local here; here=$(cd "$(dirname "$0")" && pwd)
    "$here/console.sh" -k '`' -t 1 >/dev/null 2>&1 || true
}

case "${1:-}" in
--attach)
    run -c "adapter speed $ADAPTER_SPEED"
    ;;
--reset)
    stop_cd
    run -c "adapter speed $ADAPTER_SPEED" -c "init" -c "cold_reset" "${DISARM_BOTH[@]}" -c "exit"
    ;;
--rescue)
    # QSPI が中途半端な状態で止まってブートROMから進まなくなったときの復旧
    "$OPENOCD" -s "$OPENOCD_SCRIPTS" -f "$IFACE" -f target/rp2350-rescue.cfg -c "init" -c "exit"
    ;;
*)
    ELF=${1:-build/sgnano.elf}
    [ -f "$ELF" ] || { echo "ELF がありません: $ELF（先に scripts/build.sh）" >&2; exit 1; }
    ls -l "$ELF"
    stop_cd
    run -c "adapter speed $ADAPTER_SPEED" -c "program $ELF verify" -c "cold_reset" "${DISARM_BOTH[@]}" -c "exit"
    echo "書き込み完了: $ELF"
    ;;
esac
