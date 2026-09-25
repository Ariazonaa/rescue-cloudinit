#!/usr/bin/env bash
# ===========================================================================
# rescue-cloudinit -- self-contained builder for a customized SystemRescue ISO
#
# Run on a Linux host (your Proxmox node / Debian / Ubuntu / Arch / WSL):
#
#     sudo bash build-on-linux.sh [source.iso] [output.iso]
#
# No source given -> looks for systemrescue*.iso in the Proxmox ISO storage,
# and if none is found downloads SystemRescue 13.02. The finished ISO is put
# next to the source and, if a Proxmox ISO storage exists, copied there too.
#
# The whole recipe (autorun, sysrescue.d, root-tools) is embedded as a base64
# tarball. Boot configs are patched: mask NetworkManager-wait-online (fast boot)
# and restyle the boot menus black/red.
# ===========================================================================
set -euo pipefail

VER=13.02
DL="https://downloads.sourceforge.net/project/systemrescuecd/sysresccd-x86/${VER}/systemrescue-${VER}-amd64.iso"
ISO_DIRS=(/var/lib/vz/template/iso /mnt/pve/*/template/iso)
MASK="systemd.mask=NetworkManager-wait-online.service"

[ "$(id -u)" = 0 ] || { echo "please run as root (sudo bash $0 ...)"; exit 1; }

if ! command -v xorriso >/dev/null 2>&1; then
    echo ">> installing xorriso ..."
    if   command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y xorriso
    elif command -v dnf     >/dev/null 2>&1; then dnf install -y xorriso
    elif command -v pacman  >/dev/null 2>&1; then pacman -Sy --noconfirm libisoburn
    elif command -v zypper  >/dev/null 2>&1; then zypper --non-interactive install xorriso
    else echo "no known package manager -- install xorriso manually"; exit 1; fi
fi

SRC="${1:-}"
if [ -z "$SRC" ]; then
    for d in "${ISO_DIRS[@]}"; do
        for f in "$d"/systemrescue-*-amd64.iso; do [ -f "$f" ] && { SRC="$f"; break 2; }; done
    done
fi
if [ -z "$SRC" ]; then
    SRC="/tmp/systemrescue-${VER}-amd64.iso"
    echo ">> no source ISO found -- downloading ${VER} ..."
    curl -fL --retry 3 -o "$SRC" "$DL"
fi
[ -f "$SRC" ] || { echo "source ISO not found: $SRC"; exit 1; }
OUT="${2:-${SRC%.iso}-cloudinit.iso}"
echo ">> source : $SRC"
echo ">> output : $OUT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
base64 -d > "$WORK/recipe.tgz" <<'RECIPE_B64'
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
RECIPE_B64
mkdir -p "$WORK/x" && tar xzf "$WORK/recipe.tgz" -C "$WORK/x"

R="$WORK/x/iso_add"

echo ">> patching boot configs (mask wait-online + black/red menu) ..."
mkdir -p "$WORK/boot"
xorriso -indev "$SRC" -osirrox on \
    -extract /boot/grub/grubsrcd.cfg                     "$WORK/boot/grubsrcd.cfg" \
    -extract /sysresccd/boot/syslinux/sysresccd_sys.cfg  "$WORK/boot/sysresccd_sys.cfg" \
    -extract /sysresccd/boot/syslinux/sysresccd_head.cfg "$WORK/boot/sysresccd_head.cfg" >/dev/null 2>&1 || true
sed -i "s/iomem=relaxed/iomem=relaxed $MASK/g" "$WORK"/boot/grubsrcd.cfg "$WORK"/boot/sysresccd_sys.cfg 2>/dev/null || true
sed -i -e 's|set color_normal=.*|set color_normal=light-gray/black|' \
       -e 's|set color_highlight=.*|set color_highlight=black/red|' \
       -e 's|set menu_color_normal=.*|set menu_color_normal=light-gray/black|' \
       -e 's|set menu_color_highlight=.*|set menu_color_highlight=black/red|' \
       "$WORK/boot/grubsrcd.cfg" 2>/dev/null || true
sed -i -e 's|^MENU BACKGROUND .*|MENU BACKGROUND #ff000000|' \
       -e 's|^MENU color title .*|MENU COLOR title 1;31;40 #ffff3030 #00000000 std|' \
       -e 's|^MENU color sel .*|MENU COLOR sel 7;37;40 #ff000000 #ffcc0000 all|' \
       -e 's|^MENU color unsel .*|MENU COLOR unsel 37;40 #ffdddddd #00000000 none|' \
       -e 's|^MENU COLOR border .*|MENU COLOR border 30;44 #ffaa0000 #00000000 std|' \
       -e 's|^MENU COLOR help .*|MENU COLOR help 37;40 #ff999999 #00000000 std|' \
       -e 's|^MENU COLOR timeout_msg .*|MENU COLOR timeout_msg 37;40 #ffcc0000 #00000000 std|' \
       -e 's|^MENU COLOR timeout .*|MENU COLOR timeout 1;37;40 #ffff3030 #00000000 std|' \
       -e 's|^MENU color tabmsg .*|MENU COLOR tabmsg 1;31;40 #ffcc0000 #00000000 std|' \
       "$WORK/boot/sysresccd_head.cfg" 2>/dev/null || true

echo ">> building customized ISO with xorriso ..."
rm -f "$OUT"
maps=( -map "$R/autorun/autorun"                /autorun/autorun
       -map "$R/sysrescue.d/500-cloudinit.yaml" /sysrescue.d/500-cloudinit.yaml
       -map "$R/root-tools"                      /root-tools )
[ -s "$WORK/boot/grubsrcd.cfg" ]       && maps+=( -map "$WORK/boot/grubsrcd.cfg"       /boot/grub/grubsrcd.cfg )
[ -s "$WORK/boot/sysresccd_sys.cfg" ]  && maps+=( -map "$WORK/boot/sysresccd_sys.cfg"  /sysresccd/boot/syslinux/sysresccd_sys.cfg )
[ -s "$WORK/boot/sysresccd_head.cfg" ] && maps+=( -map "$WORK/boot/sysresccd_head.cfg" /sysresccd/boot/syslinux/sysresccd_head.cfg )
xorriso -indev "$SRC" -outdev "$OUT" \
    -boot_image any replay \
    "${maps[@]}" \
    -chmod 0755 /autorun/autorun -- \
    -chmod_r 0755 /root-tools -- \
    -commit

echo ">> checks:"
xorriso -indev "$OUT" -osirrox on -extract /boot/grub/grubsrcd.cfg "$WORK/_g" >/dev/null 2>&1 || true
grep -q "$MASK" "$WORK/_g" 2>/dev/null && echo "   [ok] wait-online masked" || echo "   [!!] mask missing"
grep -q 'menu_color_highlight=black/red' "$WORK/_g" 2>/dev/null && echo "   [ok] black/red GRUB theme" || echo "   [!!] theme missing"

for d in "${ISO_DIRS[@]}"; do
    if [ -d "$d" ] && [ -w "$d" ]; then
        cp -f "$OUT" "$d/" && echo ">> copied to Proxmox ISO storage: $d/$(basename "$OUT")"
        break
    fi
done

echo ">> done: $OUT"
echo "   boot it, then in /root:  ./rescue-menu.sh   (or ./vmcheck.sh etc.)"
