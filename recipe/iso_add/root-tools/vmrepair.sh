#!/bin/bash
# vmrepair.sh -- find broken filesystems and repair them (writes to disk!).
#
#   bash /root/vmrepair.sh            # auto-detect broken filesystems, repair them
#   bash /root/vmrepair.sh /dev/sdXN  # repair just that one device
#
# No need to run vmcheck first -- this scans read-only itself, then repairs only
# the filesystems that are not clean (after one confirmation).
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SELF/rescue-lib.sh" 2>/dev/null || . /root/rescue-lib.sh 2>/dev/null || { echo "rescue-lib.sh not found"; exit 1; }
activate_storage

# --- single device given: repair just that one ---
if [ -n "${1:-}" ]; then
    dev="$1"
    [ -b "$dev" ] || { echo "not a block device: $dev"; exit 1; }
    fst="$(blkid -o value -s TYPE "$dev" 2>/dev/null)"
    echo "Device: $dev (${fst:-unknown})"
    echo "WARNING: repair can modify or lose data. Image first if unsure: bash /root/backup-disk.sh"
    confirm "Repair $dev?" || { echo "aborted."; exit 1; }
    repair_fs "$dev" "$fst"
    exit 0
fi

# --- no argument: auto-detect the broken filesystems ---
echo "Scanning the VM filesystems (read-only) ..."
broken=()
found=0
while read -r dev fst; do
    found=1
    if [ "$(fs_status "$dev" "$fst")" = errors ]; then
        c_err "$dev ($fst) -> NEEDS REPAIR"
        broken+=("$dev|$fst")
    else
        c_ok "$dev ($fst) clean"
    fi
done < <(list_target_fs)

[ "$found" = 0 ] && { echo "No checkable filesystems found (all mounted, or none present)."; exit 0; }
if [ "${#broken[@]}" -eq 0 ]; then
    echo; echo "All filesystems are clean -- nothing to repair."; exit 0
fi

echo
echo "Broken filesystem(s): $(for e in "${broken[@]}"; do printf '%s ' "${e%%|*}"; done)"
echo "WARNING: repair can modify or lose data. Image first if unsure: bash /root/backup-disk.sh"
confirm "Repair the ${#broken[@]} filesystem(s) above?" || { echo "aborted."; exit 1; }
for e in "${broken[@]}"; do repair_fs "${e%%|*}" "${e##*|}"; done
echo "done. Re-check with: bash /root/vmcheck.sh"
