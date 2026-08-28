#!/usr/bin/env bash
# vmd/wsl2win_cp.sh -- stage vmd/ to a Windows-visible path for headless VMD.
# VMD (Windows) can't read WSL /mnt/c paths directly; staging to
# tmp/biochemeleon-vmd/ (under /mnt/c) puts it where VMD's [pwd] resolves to
# a C:/... Windows path. Mirrors v1's pymol/wsl2win_cp.sh.
# The shebang is cosmetic (opencode.json may deny chmod); invoke via
# `bash vmd/wsl2win_cp.sh` if the executable bit is unset. The smoke runner
# inlines the `cp` anyway; this script is the standalone form.
set -e
STAGE="${1:-tmp/biochemeleon-vmd}"
mkdir -p "$STAGE"
cp -r vmd "$STAGE/"
echo "staged: $STAGE/vmd"
