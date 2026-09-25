#!/bin/bash
# copy-out.sh -- rsync important directories off the installed VM (read-only source).
# Usage: bash /root/copy-out.sh [/dev/ROOT] [DEST_DIR]
. /root/rescue-lib.sh
root="${1:-$(find_root_part)}"
[ -b "$root" ] || { echo "no root filesystem found; pass one: bash /root/copy-out.sh /dev/ROOT [DEST]"; exit 1; }
dest="${2:-/root/vm-rescue-$(date +%Y%m%d)}"
mp=/run/co.mnt; mkdir -p "$mp"
mount -o ro "$root" "$mp" || { echo "mount failed"; exit 1; }
mkdir -p "$dest"
echo "Copying key data from $root (ro) -> $dest"
for d in etc home root srv var/www var/lib/mysql var/lib/postgresql; do
    [ -d "$mp/$d" ] || continue
    echo "  $d ..."
    mkdir -p "$dest/$(dirname "$d")"
    rsync -aHAX --numeric-ids "$mp/$d" "$dest/$(dirname "$d")/" 2>/dev/null
done
umount "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null
echo "done: $dest ($(du -sh "$dest" 2>/dev/null | cut -f1))"
echo "fetch it off the box: scp -r root@<this-ip>:$dest ."
