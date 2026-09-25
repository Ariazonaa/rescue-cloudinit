#!/bin/bash
# vmcheck.sh -- read-only health check of the VM's disks and filesystems.
# SAFE: never modifies the target (fsck -n / xfs_repair -n / btrfs check --readonly).
# Repairs are a separate, explicit script:  /root/vmrepair.sh /dev/DEVICE
# Usage: bash /root/vmcheck.sh [/dev/DEVICE ...]     (no args = all VM disks)
. /root/rescue-lib.sh
LOG=/var/log/vm-healthcheck.log
exec > >(tee -a "$LOG") 2>&1

RC=0
ok()   { echo "  [ OK ] $*"; }
warn() { echo "  [WARN] $*"; [ "$RC" -lt 1 ] && RC=1; }
bad()  { echo "  [FAIL] $*"; RC=2; }
inf()  { echo "         $*"; }

echo "================================================================"
echo " VM health check  $(date -u +%FT%TZ)"
echo "================================================================"
activate_storage

if [ "$#" -gt 0 ]; then disks=("$@"); else mapfile -t disks < <(target_disks); fi
if [ "${#disks[@]}" -eq 0 ]; then warn "no target disks found"; echo "== nothing to check =="; exit "$RC"; fi
echo "Target disks: ${disks[*]}"; echo

is_mounted() { findmnt -rno TARGET "$1" >/dev/null 2>&1; }

check_fs() {
    local dev="$1" fst="$2" t=/tmp/vc.$$
    [ -b "$dev" ] || return
    if is_mounted "$dev"; then inf "$dev ($fst): mounted, skipped"; return; fi
    case "$fst" in
        ext2|ext3|ext4)
            if e2fsck -fn "$dev" >"$t" 2>&1; then ok "$dev ($fst): clean"
            else warn "$dev ($fst): errors detected (repair: /root/vmrepair.sh $dev)"; tail -4 "$t" | sed 's/^/           /'; fi ;;
        xfs)
            if xfs_repair -n "$dev" >"$t" 2>&1; then ok "$dev (xfs): clean"
            else warn "$dev (xfs): dirty log or errors (repair: /root/vmrepair.sh $dev)"; grep -iE 'corrupt|bad|would|dirty|mount' "$t" | head -3 | sed 's/^/           /'; fi ;;
        btrfs)
            if btrfs check --readonly "$dev" >"$t" 2>&1; then ok "$dev (btrfs): clean"
            else warn "$dev (btrfs): errors (inspect: btrfs check $dev)"; fi ;;
        vfat|fat12|fat16|fat32|msdos)
            if fsck.fat -n "$dev" >"$t" 2>&1; then ok "$dev (vfat): clean"
            else warn "$dev (vfat): errors (repair: /root/vmrepair.sh $dev)"; fi ;;
        ntfs)
            if command -v ntfsfix >/dev/null 2>&1 && ntfsfix -n "$dev" >"$t" 2>&1; then ok "$dev (ntfs): consistent"
            else warn "$dev (ntfs): verify with Windows chkdsk"; fi ;;
        swap)        inf "$dev: swap (skipped)";;
        crypto_LUKS) inf "$dev: LUKS -> unlock first: cryptsetup open $dev x ; then bash /root/vmcheck.sh /dev/mapper/x";;
        LVM2_member) : ;;
        "")          : ;;
        *)           inf "$dev: $fst (no read-only checker)";;
    esac
    rm -f "$t"
}

for d in "${disks[@]}"; do
    [ -b "$d" ] || { bad "$d: not a block device"; continue; }
    echo "== $d =="
    inf "size: $(lsblk -dno SIZE "$d" 2>/dev/null)  model: $(lsblk -dno MODEL "$d" 2>/dev/null | xargs)"
    sm="$(smartctl -H "$d" 2>/dev/null)"
    if   echo "$sm" | grep -qi "PASSED"; then ok "SMART: PASSED"
    elif echo "$sm" | grep -qi "FAILED"; then bad "SMART: FAILED - disk may be failing"
    else inf "SMART: not available (virtual disk)"; fi
    ptt="$(lsblk -dno PTTYPE "$d" 2>/dev/null | head -1)"
    if [ "$ptt" = gpt ] && command -v sgdisk >/dev/null 2>&1; then
        pv="$(sgdisk -v "$d" 2>/dev/null)"
        if echo "$pv" | grep -qi 'No problems found'; then ok "GPT partition table: no problems"
        elif echo "$pv" | grep -qiE 'problem|corrupt'; then warn "GPT: $(echo "$pv" | grep -iE 'problem|corrupt' | head -1 | xargs)"; fi
    elif [ -n "$ptt" ]; then inf "partition table: $ptt"
    fi
    while read -r name fst; do
        [ "$name" = "$(basename "$d")" ] && continue
        dev="/dev/$name"; [ -b "$dev" ] || dev="/dev/mapper/${name##*/}"
        check_fs "$dev" "$fst"
    done < <(lsblk -rno NAME,FSTYPE "$d")
    wf="$(lsblk -dno FSTYPE "$d" 2>/dev/null | head -1)"
    [ -n "$wf" ] && check_fs "$d" "$wf"
    echo
done

echo "== capacity (read-only mount test) =="
mp=/run/vmcheck.mnt; mkdir -p "$mp"
while read -r name fst; do
    case "$fst" in ext4|ext3|ext2|xfs|btrfs) ;; *) continue;; esac
    dev="/dev/$name"; [ -b "$dev" ] || dev="/dev/mapper/${name##*/}"
    is_mounted "$dev" && continue
    if mount -o ro "$dev" "$mp" 2>/dev/null; then
        inf "$dev ($fst): mountable, used $(df -h "$mp" | awk 'NR==2{print $3"/"$2" ("$5")"}')"
        umount "$mp" 2>/dev/null
    fi
done < <(for d in "${disks[@]}"; do lsblk -rno NAME,FSTYPE "$d"; done)
rmdir "$mp" 2>/dev/null

echo "== Verdict =="
case "$RC" in
    0) echo "  RESULT: VM looks HEALTHY";;
    1) echo "  RESULT: WARNINGS - review the [WARN] lines above";;
    2) echo "  RESULT: PROBLEMS FOUND - review the [FAIL] lines above";;
esac
echo "  log: $LOG  |  re-run: bash /root/vmcheck.sh  |  repair: bash /root/vmrepair.sh /dev/DEVICE"
exit "$RC"
