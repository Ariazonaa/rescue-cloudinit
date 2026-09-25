#!/bin/bash
# rescue-menu.sh -- interactive launcher for the /root rescue toolkit.
# Click through with arrow keys (dialog) or type a number (fallback).
cd /root || exit 1

# pairs: script  description   (keep one pair per line, space-separated)
ITEMS=(
  "vmcheck.sh"       "Health-check the VM disks (read-only)"
  "disk-usage.sh"    "Disk usage / biggest directories (read-only)"
  "smart-full.sh"    "Full SMART report / start self-test"
  "check-boot.sh"    "Diagnose why the VM will not boot"
  "mount-all-ro.sh"  "Mount all VM filesystems read-only under /mnt"
  "collect-logs.sh"  "Collect the VM's logs into a tarball"
  "copy-out.sh"      "Copy important data off the VM"
  "backup-disk.sh"   "Image a disk/partition to a file"
  "ddrescue.sh"      "Rescue a failing disk (ddrescue)"
  "enter-chroot.sh"  "Enter a chroot in the installed system"
  "fix-grub.sh"      "Reinstall the GRUB bootloader"
  "reset-root-pw.sh" "Reset the VM's root password"
  "vmrepair.sh"      "REPAIR a filesystem (writes to disk!)"
)

run() {
    clear
    echo ">>> $1"; echo
    bash "/root/$1"
    echo; read -rp "Press Enter to return to the menu..."
}

if command -v dialog >/dev/null 2>&1; then
    while :; do
        menu=(); i=0
        while [ "$i" -lt "${#ITEMS[@]}" ]; do
            menu+=( "$((i/2+1))" "${ITEMS[$((i+1))]}" ); i=$((i+2))
        done
        choice=$(dialog --clear --backtitle "SystemRescue toolkit" --title "Rescue menu" \
                 --cancel-label "Quit" --menu "Select a tool, then Enter:" 22 74 15 \
                 "${menu[@]}" 3>&1 1>&2 2>&3) || { clear; exit 0; }
        run "${ITEMS[$(( (choice-1)*2 ))]}"
    done
else
    while :; do
        clear
        echo "================ SystemRescue toolkit ================"
        i=0
        while [ "$i" -lt "${#ITEMS[@]}" ]; do
            printf "  %2d) %-17s %s\n" "$((i/2+1))" "${ITEMS[$i]}" "${ITEMS[$((i+1))]}"
            i=$((i+2))
        done
        echo "   q) Quit"
        read -rp "Choice: " c
        [ "$c" = q ] && exit 0
        case "$c" in ''|*[!0-9]*) continue;; esac
        idx=$(( (c-1)*2 ))
        [ "$idx" -ge 0 ] && [ -n "${ITEMS[$idx]:-}" ] && run "${ITEMS[$idx]}"
    done
fi
