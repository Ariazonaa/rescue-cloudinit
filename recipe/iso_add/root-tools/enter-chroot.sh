#!/bin/bash
# enter-chroot.sh -- mount the installed VM root (+ /boot, /boot/efi) and chroot into it.
# Usage: bash /root/enter-chroot.sh [/dev/ROOT]
. /root/rescue-lib.sh
root="${1:-$(find_root_part)}"
[ -b "$root" ] || { echo "no root filesystem found; pass one: bash /root/enter-chroot.sh /dev/XXX"; exit 1; }
mp=/mnt/vmroot; mkdir -p "$mp"
echo "Mounting root $root (read-write) at $mp ..."
mount_target "$root" "$mp" rw || { echo "mount failed"; exit 1; }
for b in dev dev/pts proc sys run; do mount --rbind "/$b" "$mp/$b" 2>/dev/null; done
cp -f /etc/resolv.conf "$mp/etc/resolv.conf" 2>/dev/null
echo
echo ">>> Entering chroot in $root. Fix things, then type 'exit'."
echo ">>> common fixes:  update-grub  |  grub-install /dev/DISK  |  mkinitramfs -u  |  passwd  |  nano /etc/fstab"
echo
chroot "$mp" /bin/bash --login
echo
echo ">>> leaving chroot, unmounting $mp ..."
umount -R "$mp" 2>/dev/null && echo "done." || echo "note: some mounts busy; run 'umount -R $mp' again if needed."
