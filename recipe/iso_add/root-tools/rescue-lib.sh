#!/bin/bash
# rescue-lib.sh -- shared helpers for the /root rescue scripts.
#   source it with:   . /root/rescue-lib.sh

c_ok()   { echo "  [ OK ] $*"; }
c_warn() { echo "  [WARN] $*"; }
c_err()  { echo "  [FAIL] $*"; }
c_inf()  { echo "         $*"; }
hr()     { echo "----------------------------------------------------------------"; }

# activate LVM / MD-RAID so their volumes become visible (safe: no file data written)
activate_storage() {
    mdadm --assemble --scan >/dev/null 2>&1
    vgchange -ay            >/dev/null 2>&1
    partprobe               >/dev/null 2>&1
}

# echo the VM's real disks, one per line (excludes the rescue CD, cidata, loop)
target_disks() {
    local bootsrc n type dp
    bootsrc="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null | sed 's/[0-9]*$//')"
    while read -r n type; do
        [ "$type" = disk ] || continue
        dp="/dev/$n"
        lsblk -rno LABEL "$dp" 2>/dev/null | grep -qE '^(RESCUE[0-9]+|cidata)$' && continue
        [ -n "$bootsrc" ] && [ "$dp" = "$bootsrc" ] && continue
        echo "$dp"
    done < <(lsblk -dno NAME,TYPE)
}

# resolve an fstab source spec (UUID=/LABEL=/PARTUUID=/dev) to a device node
resolve_spec() {
    case "$1" in
        UUID=*)     blkid -U "${1#UUID=}" 2>/dev/null;;
        LABEL=*)    blkid -L "${1#LABEL=}" 2>/dev/null;;
        PARTUUID=*) blkid -t "PARTUUID=${1#PARTUUID=}" -o device 2>/dev/null | head -1;;
        /dev/*)     echo "$1";;
        *)          echo "";;
    esac
}

# echo the device that holds the installed Linux root (best guess), or fail
find_root_part() {
    activate_storage
    local mp dev
    mp="$(mktemp -d)"
    for dev in $(lsblk -rpno NAME,FSTYPE | awk '$2 ~ /^(ext4|ext3|ext2|xfs|btrfs)$/{print $1}'); do
        findmnt -rno TARGET "$dev" >/dev/null 2>&1 && continue          # skip mounted
        mount -o ro "$dev" "$mp" 2>/dev/null || continue
        if [ -e "$mp/etc/fstab" ] && [ -d "$mp/usr" ] && \
           { [ -e "$mp/sbin/init" ] || [ -L "$mp/sbin/init" ] || [ -d "$mp/usr/lib/systemd" ]; }; then
            umount "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null; echo "$dev"; return 0
        fi
        umount "$mp" 2>/dev/null
    done
    rmdir "$mp" 2>/dev/null; return 1
}

# mount target root (+ /boot, /boot/efi from its fstab) at $1; mode $2 = ro|rw (default ro)
mount_target() {
    local root="$1" mp="$2" mode="${3:-ro}" src tgt rest d
    mount -o "$mode" "$root" "$mp" || return 1
    while read -r src tgt rest; do
        case "$src" in ""|\#*) continue;; esac
        case "$tgt" in /boot|/boot/efi) : ;; *) continue;; esac
        d="$(resolve_spec "$src")"
        [ -n "$d" ] && [ -b "$d" ] && { mkdir -p "$mp$tgt"; mount -o "$mode" "$d" "$mp$tgt" 2>/dev/null; }
    done < <(grep -vE '^\s*#|^\s*$' "$mp/etc/fstab" 2>/dev/null)
}

confirm() { local a; read -rp "${1:-Continue?} Type YES to proceed: " a; [ "$a" = YES ]; }

# print "dev fstype" for each checkable filesystem on the VM's disks
# (partitions + LVs; skips mounted, swap, LUKS and LVM PVs)
list_target_fs() {
    local d name fst dev
    for d in $(target_disks); do
        while read -r name fst; do
            case "$fst" in ext2|ext3|ext4|xfs|btrfs|vfat|fat12|fat16|fat32|msdos|ntfs) ;; *) continue;; esac
            dev="/dev/$name"; [ -b "$dev" ] || dev="/dev/mapper/${name##*/}"
            [ -b "$dev" ] || continue
            findmnt -rno TARGET "$dev" >/dev/null 2>&1 && continue
            echo "$dev $fst"
        done < <(lsblk -rno NAME,FSTYPE "$d")
    done
}

# read-only status of one filesystem -> echoes "clean" or "errors"
fs_status() {
    local dev="$1" fst="$2"
    case "$fst" in
        ext2|ext3|ext4)               e2fsck -fn "$dev"          >/dev/null 2>&1;;
        xfs)                          xfs_repair -n "$dev"       >/dev/null 2>&1;;
        btrfs)                        btrfs check --readonly "$dev" >/dev/null 2>&1;;
        vfat|fat12|fat16|fat32|msdos) fsck.fat -n "$dev"         >/dev/null 2>&1;;
        ntfs)                         ntfsfix -n "$dev"          >/dev/null 2>&1;;
        *)                            return 0;;
    esac && echo clean || echo errors
}

# actually REPAIR one filesystem (writes to disk!)
repair_fs() {
    local dev="$1" fst="$2"
    findmnt -rno TARGET "$dev" >/dev/null 2>&1 && { c_warn "$dev is mounted -- skipping"; return 1; }
    echo ">> repairing $dev ($fst) ..."
    case "$fst" in
        ext2|ext3|ext4)               e2fsck -fy "$dev";;
        xfs)                          xfs_repair "$dev";;
        vfat|fat12|fat16|fat32|msdos) fsck.fat -a "$dev";;
        ntfs)                         ntfsfix "$dev";;
        btrfs)                        echo "  btrfs is risky to auto-repair -- do it manually:";
                                      echo "    btrfs check --readonly $dev   (assess)";
                                      echo "    btrfs check --repair   $dev   (LAST resort)";;
        *)                            echo "  no automatic repair for '$fst'";;
    esac
}
