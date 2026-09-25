#!/usr/bin/env bash
# Bake the rescue-cloudinit recipe into the SystemRescue ISO.
# Run on Linux (a VPS or WSL) -- Windows has no xorriso/sysrescue-customize.
#
#   ./build.sh [source.iso] [output.iso]
#
# Defaults: source = systemrescue-13.02-amd64.iso
#           output = systemrescue-13.02-amd64-cloudinit.iso
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-systemrescue-13.02-amd64.iso}"
OUT="${2:-${SRC%.iso}-cloudinit.iso}"
RECIPE="recipe"
MASK="systemd.mask=NetworkManager-wait-online.service"

[ -f "$SRC" ] || { echo "source ISO not found: $SRC" >&2; exit 1; }
chmod 0755 "$RECIPE/iso_add/autorun/autorun" 2>/dev/null || true

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Apply boot patches to the extracted configs in dir $1:
#   - mask NetworkManager-wait-online on the kernel cmdline (faster boot)
#   - restyle the boot menus black/red (title text is left unchanged)
theme_boot() {
    local d="$1"
    sed -i "s/iomem=relaxed/iomem=relaxed $MASK/g" "$d"/grubsrcd.cfg "$d"/sysresccd_sys.cfg 2>/dev/null || true
    sed -i -e 's|set color_normal=.*|set color_normal=light-gray/black|' \
           -e 's|set color_highlight=.*|set color_highlight=black/red|' \
           -e 's|set menu_color_normal=.*|set menu_color_normal=light-gray/black|' \
           -e 's|set menu_color_highlight=.*|set menu_color_highlight=black/red|' \
           "$d"/grubsrcd.cfg 2>/dev/null || true
    sed -i -e 's|^MENU BACKGROUND .*|MENU BACKGROUND #ff000000|' \
           -e 's|^MENU color title .*|MENU COLOR title 1;31;40 #ffff3030 #00000000 std|' \
           -e 's|^MENU color sel .*|MENU COLOR sel 7;37;40 #ff000000 #ffcc0000 all|' \
           -e 's|^MENU color unsel .*|MENU COLOR unsel 37;40 #ffdddddd #00000000 none|' \
           -e 's|^MENU COLOR border .*|MENU COLOR border 30;44 #ffaa0000 #00000000 std|' \
           -e 's|^MENU COLOR help .*|MENU COLOR help 37;40 #ff999999 #00000000 std|' \
           -e 's|^MENU COLOR timeout_msg .*|MENU COLOR timeout_msg 37;40 #ffcc0000 #00000000 std|' \
           -e 's|^MENU COLOR timeout .*|MENU COLOR timeout 1;37;40 #ffff3030 #00000000 std|' \
           -e 's|^MENU color tabmsg .*|MENU COLOR tabmsg 1;31;40 #ffcc0000 #00000000 std|' \
           "$d"/sysresccd_head.cfg 2>/dev/null || true
}

if command -v xorriso >/dev/null 2>&1; then
    mkdir -p "$WORK/boot"
    xorriso -indev "$SRC" -osirrox on \
        -extract /boot/grub/grubsrcd.cfg                     "$WORK/boot/grubsrcd.cfg" \
        -extract /sysresccd/boot/syslinux/sysresccd_sys.cfg  "$WORK/boot/sysresccd_sys.cfg" \
        -extract /sysresccd/boot/syslinux/sysresccd_head.cfg "$WORK/boot/sysresccd_head.cfg" >/dev/null 2>&1 || true
    theme_boot "$WORK/boot"
fi

if command -v sysrescue-customize >/dev/null 2>&1; then
    echo ">> building with sysrescue-customize (official method)"
    REC="$WORK/recipe"; cp -a "$RECIPE" "$REC"
    if [ -s "$WORK/boot/grubsrcd.cfg" ]; then
        mkdir -p "$REC/iso_add/boot/grub" "$REC/iso_add/sysresccd/boot/syslinux"
        cp "$WORK/boot/grubsrcd.cfg"       "$REC/iso_add/boot/grub/grubsrcd.cfg"
        cp "$WORK/boot/sysresccd_sys.cfg"  "$REC/iso_add/sysresccd/boot/syslinux/sysresccd_sys.cfg"
        cp "$WORK/boot/sysresccd_head.cfg" "$REC/iso_add/sysresccd/boot/syslinux/sysresccd_head.cfg"
    fi
    exec sysrescue-customize --auto --source "$SRC" --dest "$OUT" --recipe-dir "$REC"
fi

if command -v xorriso >/dev/null 2>&1; then
    echo ">> sysrescue-customize not found -- falling back to xorriso"
    rm -f "$OUT"
    maps=( -map "$RECIPE/iso_add/autorun/autorun"                /autorun/autorun
           -map "$RECIPE/iso_add/sysrescue.d/500-cloudinit.yaml" /sysrescue.d/500-cloudinit.yaml
           -map "$RECIPE/iso_add/root-tools"                     /root-tools )
    [ -s "$WORK/boot/grubsrcd.cfg" ]       && maps+=( -map "$WORK/boot/grubsrcd.cfg"       /boot/grub/grubsrcd.cfg )
    [ -s "$WORK/boot/sysresccd_sys.cfg" ]  && maps+=( -map "$WORK/boot/sysresccd_sys.cfg"  /sysresccd/boot/syslinux/sysresccd_sys.cfg )
    [ -s "$WORK/boot/sysresccd_head.cfg" ] && maps+=( -map "$WORK/boot/sysresccd_head.cfg" /sysresccd/boot/syslinux/sysresccd_head.cfg )
    xorriso -indev "$SRC" -outdev "$OUT" \
        -boot_image any replay \
        "${maps[@]}" \
        -chmod 0755 /autorun/autorun -- \
        -chmod_r 0755 /root-tools -- \
        -commit
    echo ">> wrote $OUT"
    exit 0
fi

echo "error: need 'sysrescue-customize' or 'xorriso' (neither found)" >&2
exit 1
