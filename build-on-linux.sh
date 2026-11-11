#!/usr/bin/env bash
# ===========================================================================
# rescue-cloudinit -- self-contained builder for a customized SystemRescue ISO
#
# Run on a Linux host (your Proxmox node / Debian / Ubuntu / Arch / WSL):
#
#     sudo bash build-on-linux.sh [source.iso] [output.iso]
#
# No source given -> looks for systemrescue-<VER>-amd64.iso in the Proxmox ISO storage,
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
        [ -f "$d/systemrescue-${VER}-amd64.iso" ] && { SRC="$d/systemrescue-${VER}-amd64.iso"; break; }
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
