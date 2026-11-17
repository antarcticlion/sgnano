#!/usr/bin/env bash
# Flash build/sgnano.elf in 128 KB chunks (2026-11-02).
# `flash write_image erase` sometimes times out in the middle of the full 2.4 MB erase
# ("timed out while waiting for target halted"). One short OpenOCD session per chunk,
# with a retry, is much more reliable than a long session.
#
#   scripts/flash_chunks.sh [elf]        (default: build/sgnano.elf)
#   ADAPTER_SPEED=100 scripts/flash_chunks.sh ...   slower SWD
#   FLASH_CHUNK=262144 scripts/flash_chunks.sh ...  bigger chunks (may time out)
set -euo pipefail
cd "$(dirname "$0")/.."
# --bin ファイル 位置: 生の像をフラッシュの位置（バイト、0x 可）へ書く（2026-11-16。フォント ROM なら
#   scripts/flash_chunks.sh --bin ../EmbFont16/output/EmbFont16Uni.bin 0xC00000）
BASE=0
RAW=""
if [ "${1:-}" = "--bin" ]; then
    RAW=${2:?--bin には像のファイルが要ります}; BASE=$(( ${3:?--bin には位置が要ります} ))
    [ -f "$RAW" ] || { echo "像がありません: $RAW" >&2; exit 1; }
    (( BASE % 4096 == 0 )) || { echo "位置は 4096 の倍数にしてください: $3" >&2; exit 1; }
    ELF=$RAW
else
    ELF=${1:-build/sgnano.elf}
    [ -f "$ELF" ] || { echo "ELF がありません: $ELF（先に scripts/build.sh）" >&2; exit 1; }
fi
OPENOCD=${OPENOCD:-$HOME/Project/openocd/src/openocd}
OPENOCD_SCRIPTS=${OPENOCD_SCRIPTS:-$HOME/Project/openocd/tcl}
ADAPTER_SPEED=${ADAPTER_SPEED:-500}
FLASH_CHUNK=${FLASH_CHUNK:-131072}
RETRIES=${RETRIES:-4}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/sgnano.bin"
if [ -n "$RAW" ]; then cp "$RAW" "$bin"; else arm-none-eabi-objcopy -O binary "$ELF" "$bin"; fi
total=$(stat -c%s "$bin")
n=$(( (total + FLASH_CHUNK - 1) / FLASH_CHUNK ))
echo "elf=$ELF bin=$total bytes, $n chunks of $FLASH_CHUNK, SWD ${ADAPTER_SPEED} kHz"

scripts/flash_swd.sh --rescue >/dev/null 2>&1 || true

ocd() { "$OPENOCD" -s "$OPENOCD_SCRIPTS" -f interface/cmsis-dap.cfg -f target/rp2350-rescue.cfg "$@"; }

for i in $(seq 0 $((n - 1))); do
    off=$((BASE + i * FLASH_CHUNK))
    f="$tmp/chunk_$i.bin"
    dd if="$bin" of="$f" bs="$FLASH_CHUNK" skip="$i" count=1 status=none
    sz=$(stat -c%s "$f")
    first=$((off / 4096))
    last=$(( (off + sz - 1) / 4096 ))
    ok=0
    for attempt in $(seq 1 "$RETRIES"); do
        log="$tmp/chunk_$i.$attempt.log"
        ocd -c "adapter speed $ADAPTER_SPEED" -c "init" \
            -c "targets rp2350.cm0 rp2350.cm1" -c "halt" \
            -c "flash erase_sector 0 $first $last" \
            -c "flash write_bank 0 $f $off" \
            -c "flash verify_bank 0 $f $off" \
            -c "exit" >"$log" 2>&1 || true
        if grep -q "contents match" "$log" && ! grep -q "Error:" "$log"; then ok=1; break; fi
        echo "  chunk $i attempt $attempt failed; retrying"
    done
    if [ "$ok" -ne 1 ]; then
        echo "chunk $i ($first..$last) failed after $RETRIES attempts; see $tmp/chunk_$i.*.log" >&2
        exit 1
    fi
    echo "  chunk $i/$((n - 1)) ok ($first..$last)"
done

ocd -c "adapter speed $ADAPTER_SPEED" -c "init" -c "cold_reset" \
    -c "rp2350.cm0 mww 0xE000EDF0 0xA05F0000" -c "rp2350.cm1 mww 0xE000EDF0 0xA05F0000" \
    -c "exit" >/dev/null 2>&1 || true
echo "書き込み完了: $ELF"
