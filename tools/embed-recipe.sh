#!/usr/bin/env bash
# Re-embed recipe/iso_add into build-on-linux.sh (the base64 block between
# `base64 -d ... <<'RECIPE_B64'` and `RECIPE_B64`).
#
#   tools/embed-recipe.sh           # rewrite build-on-linux.sh in place
#   tools/embed-recipe.sh --check   # exit 1 if the embedded copy is stale
#
# The tarball carries no owner names or real timestamps (fixed owner, mtime and
# file order, no gzip timestamp). --check compares the unpacked *contents* with
# recipe/iso_add, so different tar/gzip versions or file modes don't matter.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET=build-on-linux.sh

if [ "${1:-}" = --check ]; then
    x="$(mktemp -d)"; trap 'rm -rf "$x"' EXIT
    sed -n '/<<.RECIPE_B64.$/,/^RECIPE_B64$/p' "$TARGET" | sed '1d;$d' \
        | base64 -d | tar -xzf - -C "$x"
    if diff -r "$x/iso_add" recipe/iso_add; then echo "embedded recipe is up to date"; exit 0; fi
    echo "embedded recipe in $TARGET is stale -- run tools/embed-recipe.sh" >&2
    exit 1
fi

payload="$(tar --sort=name --owner=0 --group=0 --numeric-owner \
               --mtime='2000-01-01 00:00:00 UTC' --mode='u=rwX,go=rX' \
               -C recipe -cf - iso_add | gzip -9n | base64 -w 76)"

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
awk -v payload="$payload" '
    /^RECIPE_B64$/            { skip = 0 }
    !skip                     { print }
    /<<.RECIPE_B64.$/         { print payload; skip = 1 }
' "$TARGET" > "$tmp"
cat "$tmp" > "$TARGET"
echo "re-embedded recipe/iso_add into $TARGET"
