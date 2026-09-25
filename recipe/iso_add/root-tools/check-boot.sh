#!/bin/bash
# check-boot.sh -- diagnose why the installed VM won't boot (read-only inspection).
# Usage: bash /root/check-boot.sh [/dev/ROOT]
. /root/rescue-lib.sh
root="${1:-$(find_root_part)}"
[ -b "$root" ] || { echo "no root filesystem found; pass one: bash /root/check-boot.sh /dev/XXX"; exit 1; }
mp=/run/cb.mnt; mkdir -p "$mp"
mount -o ro "$root" "$mp" || { echo "mount failed"; exit 1; }
echo "Root filesystem: $root"
( . "$mp/etc/os-release" 2>/dev/null && echo "OS: $PRETTY_NAME" )

hr; echo "fstab:"; grep -vE '^\s*#|^\s*$' "$mp/etc/fstab" 2>/dev/null | sed 's/^/  /'
echo "checking each fstab source exists:"
while read -r src tgt rest; do
    case "$src" in ""|\#*) continue;; esac
    case "$tgt" in swap|none) continue;; esac
    d="$(resolve_spec "$src")"
    if [ -n "$d" ] && [ -b "$d" ]; then c_ok "$src -> $d ($tgt)"
    else c_warn "$src ($tgt) NOT FOUND -> boot can hang waiting for it"; fi
done < <(grep -vE '^\s*#|^\s*$' "$mp/etc/fstab" 2>/dev/null)

hr; echo "kernel & initramfs in /boot:"
ls -1 "$mp"/boot/vmlinuz* "$mp"/boot/initrd* "$mp"/boot/initramfs* 2>/dev/null | sed 's/^/  /' \
    || c_warn "no kernel/initramfs in /boot -> regenerate (mkinitramfs/dracut) via enter-chroot.sh"

hr; echo "bootloader:"
[ -e "$mp/boot/grub/grub.cfg" ] && c_ok "/boot/grub/grub.cfg present" || c_warn "no /boot/grub/grub.cfg -> run fix-grub.sh"
[ -d "$mp/boot/efi" ] && c_inf "EFI directory present (ensure the ESP is in fstab and mounted)"

umount "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null
hr
echo "To fix: bash /root/enter-chroot.sh   (then: update-grub / mkinitramfs -u / passwd)"
echo "        bash /root/fix-grub.sh        (reinstall the bootloader)"
