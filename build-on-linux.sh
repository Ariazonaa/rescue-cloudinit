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
