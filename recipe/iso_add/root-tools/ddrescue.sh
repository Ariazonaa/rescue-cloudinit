#!/bin/bash
# ddrescue.sh -- rescue a failing disk into an image with a resumable mapfile.
. /root/rescue-lib.sh
command -v ddrescue >/dev/null 2>&1 || { echo "ddrescue not available on this medium"; exit 1; }
echo "Block devices:"; lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL 2>/dev/null | sed 's/^/  /'
read -rp "FAILING source device (e.g. /dev/sdb): " src
[ -b "$src" ] || { echo "not a block device"; exit 1; }
def="/root/$(basename "$src").img"
read -rp "Output image [$def]: " img; img="${img:-$def}"
map="$img.map"
echo "Pass 1: fast copy, skip bad areas ..."
ddrescue -f -n "$src" "$img" "$map"
echo "Pass 2: retry the bad areas (3x) ..."
ddrescue -d -f -r3 "$src" "$img" "$map"
echo "done: $img   (mapfile: $map)"
echo "status: ddrescuelog -t $map    |    then check the image: bash /root/vmcheck.sh (loop-mount it)"
