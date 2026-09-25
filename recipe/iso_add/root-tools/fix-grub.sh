#!/bin/bash
# fix-grub.sh -- reinstall GRUB and regenerate its config inside the installed VM.
# Usage: bash /root/fix-grub.sh [/dev/ROOT] [/dev/DISK]
. /root/rescue-lib.sh
root="${1:-$(find_root_part)}"
[ -b "$root" ] || { echo "no root filesystem found; pass one: bash /root/fix-grub.sh /dev/ROOT [/dev/DISK]"; exit 1; }
disk="$2"; [ -z "$disk" ] && disk="/dev/$(lsblk -no PKNAME "$root" 2>/dev/null | head -1)"
echo "Root: $root    BIOS boot disk: ${disk:-<unknown>}"
confirm "Reinstall GRUB and run update-grub?" || { echo "aborted."; exit 1; }
mp=/mnt/vmroot; mkdir -p "$mp"
mount_target "$root" "$mp" rw || { echo "mount failed"; exit 1; }
for b in dev dev/pts proc sys run; do mount --rbind "/$b" "$mp/$b" 2>/dev/null; done
cp -f /etc/resolv.conf "$mp/etc/resolv.conf" 2>/dev/null

if mountpoint -q "$mp/boot/efi"; then
    echo "UEFI: installing GRUB to the ESP ..."
    chroot "$mp" bash -c 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck 2>/dev/null \
        || grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck'
fi
if [ -n "$disk" ] && [ -b "$disk" ]; then
    echo "BIOS: installing GRUB to $disk ..."
    chroot "$mp" grub-install --target=i386-pc --recheck "$disk" 2>/dev/null || chroot "$mp" grub-install "$disk"
fi
echo "regenerating grub.cfg ..."
chroot "$mp" bash -c 'update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg'
umount -R "$mp" 2>/dev/null
echo "done."
