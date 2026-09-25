#!/bin/bash
# reset-root-pw.sh -- set a new root password on the installed VM.
# Usage: bash /root/reset-root-pw.sh [/dev/ROOT]
. /root/rescue-lib.sh
root="${1:-$(find_root_part)}"
[ -b "$root" ] || { echo "no root filesystem found; pass one: bash /root/reset-root-pw.sh /dev/XXX"; exit 1; }
mp=/mnt/vmroot; mkdir -p "$mp"
mount "$root" "$mp" || { echo "mount failed"; exit 1; }
for b in dev proc sys; do mount --rbind "/$b" "$mp/$b" 2>/dev/null; done
echo "Setting the root password inside $root:"
chroot "$mp" passwd root
umount -R "$mp" 2>/dev/null
echo "done. (If login still fails, check that the account isn't expired/locked: chage -l root)"
