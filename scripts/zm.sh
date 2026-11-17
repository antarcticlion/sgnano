#!/bin/bash
# 実機のファイラーと ZMODEM でファイルをやり取りする（2026-10-16）。説明は scripts/zm.py
#   scripts/zm.sh put FILE...   /   scripts/zm.sh get [DIR]
exec python3 "$(dirname "$0")/zm.py" "$@"
