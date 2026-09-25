#!/bin/bash
# collect-logs.sh -- grab logs/config from the installed VM root into a tarball in /root.
# Usage: bash /root/collect-logs.sh [/dev/ROOT]
. /root/rescue-lib.sh
root="${1:-$(find_root_part)}"
[ -b "$root" ] || { echo "no root filesystem found; pass one: bash /root/collect-logs.sh /dev/XXX"; exit 1; }
mp=/run/logs.mnt; mkdir -p "$mp"
mount -o ro "$root" "$mp" || { echo "mount failed"; exit 1; }
out="/root/vmlogs-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "collecting from $root ..."
tar czf "$out" -C "$mp" --warning=no-file-changed --ignore-failed-read \
    var/log etc/fstab etc/hostname etc/os-release etc/network etc/netplan 2>/dev/null
[ -d "$mp/var/log/journal" ] && echo "  (systemd journal included)"
umount "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null
echo "wrote $out ($(du -h "$out" | cut -f1))"
echo "fetch it off the box: scp root@<this-ip>:$out ."
