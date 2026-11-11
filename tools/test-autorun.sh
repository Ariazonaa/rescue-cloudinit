#!/usr/bin/env bash
# Offline tests for the network part of recipe/iso_add/autorun/autorun:
#   - the embedded network-config parser (JSON fixtures, so no PyYAML needed)
#   - apply_netcfg, with nmcli replaced by a stub that records its calls
#
#   tools/test-autorun.sh
set -euo pipefail
cd "$(dirname "$0")/.."

AUTORUN=recipe/iso_add/autorun/autorun
PY=""
for p in python3 python; do   # skip the Windows Store stub that only prints a hint
    command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys' >/dev/null 2>&1 && { PY="$(command -v "$p")"; break; }
done
[ -n "$PY" ] || { echo "python3 not found" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0

sed -n "/^cat > \"\$NETPARSE\" <<'PY'\$/,/^PY\$/p" "$AUTORUN" | sed '1d;$d' > "$T/netparse.py"

check() {   # name, expected, actual
    if [ "$2" = "$3" ]; then echo "ok   $1"
    else printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}
parse() { printf '%s' "$1" > "$T/in.json"; "$PY" -I "$T/netparse.py" "$T/in.json" | tr -d '\r'; }

# --- parser -----------------------------------------------------------------
# Proxmox, IPv6 only (ipconfig0: ip6=...,gw6=...)
check "v1 static6 only" \
"eth0 static6 2001:db8:10::169/64 2001:db8:10::1 2001:4860:4860::8888" \
"$(parse '{"version":1,"config":[
  {"type":"physical","name":"eth0","mac_address":"bc:24:11:00:00:01","subnets":[
    {"type":"static6","address":"2001:db8:10::169/64","gateway":"2001:db8:10::1"}]},
  {"type":"nameserver","address":["8.8.8.8","8.8.4.4","2001:4860:4860::8888"]}]}')"

# Proxmox, IPv4 only (ipconfig0: ip=...,gw=...)
check "v1 static only" \
"eth0 static 10.10.0.50/24 10.10.0.1 8.8.8.8" \
"$(parse '{"version":1,"config":[
  {"type":"physical","name":"eth0","mac_address":"bc:24:11:00:00:01","subnets":[
    {"type":"static","address":"10.10.0.50","netmask":"255.255.255.0","gateway":"10.10.0.1"}]},
  {"type":"nameserver","address":["8.8.8.8","2001:4860:4860::8888"]}]}')"

# Proxmox, dual stack
check "v1 dual stack" \
"eth0 static 10.10.0.50/24 10.10.0.1 -
eth0 static6 2001:db8:10::169/64 2001:db8:10::1 -" \
"$(parse '{"version":1,"config":[
  {"type":"physical","name":"eth0","mac_address":"bc:24:11:00:00:01","subnets":[
    {"type":"static","address":"10.10.0.50","netmask":"255.255.255.0","gateway":"10.10.0.1"},
    {"type":"static6","address":"2001:db8:10::169/64","gateway":"2001:db8:10::1"}]}]}')"

# netplan v2, dual stack
check "v2 dual stack" \
"eth0 static 10.10.0.50/24 10.10.0.1 1.1.1.1
eth0 static6 2001:db8:10::169/64 2001:db8:10::1 2606:4700:4700::1111" \
"$(parse '{"network":{"version":2,"ethernets":{"eth0":{
  "addresses":["10.10.0.50/24","2001:db8:10::169/64"],
  "routes":[{"to":"default","via":"10.10.0.1"},{"to":"::/0","via":"2001:db8:10::1"}],
  "nameservers":{"addresses":["1.1.1.1","2606:4700:4700::1111"]}}}}}')"

# OpenStack network_data.json, IPv6
check "openstack ipv6" \
"eth0 static6 2001:db8:10::169/64 2001:db8:10::1 -" \
"$(parse '{"links":[{"id":"eth0","ethernet_mac_address":"bc:24:11:00:00:01"}],
  "networks":[{"type":"ipv6","link":"eth0","ip_address":"2001:db8:10::169",
    "netmask":"ffff:ffff:ffff:ffff::","routes":[{"network":"::","netmask":"::","gateway":"2001:db8:10::1"}]}],
  "services":[]}')"

# --- apply_netcfg with a stub nmcli ----------------------------------------
sed -n -e '/^nm_run() {$/,/^}$/p' -e '/^apply_netcfg() {$/,/^}$/p' "$AUTORUN" > "$T/apply.sh"
cat > "$T/nmcli" <<'EOF'
#!/usr/bin/env bash
echo "nmcli $*" >> "$NMLOG"
EOF
chmod +x "$T/nmcli"
printf '#!/bin/sh\nexec "%s" -I "$@"\n' "$PY" > "$T/python3"
chmod +x "$T/python3"

run_apply() {   # json -> recorded nmcli calls
    printf '%s' "$1" > "$T/netcfg.json"; : > "$T/empty"; : > "$T/nm.log"
    (
        PATH="$T:$PATH" NMLOG="$T/nm.log" NETPARSE="$T/netparse.py" \
        NETCFG="$T/netcfg.json" NETJSON="$T/empty"
        export PATH NMLOG
        log() { :; }
        # shellcheck disable=SC1091
        . "$T/apply.sh"
        apply_netcfg
    ) >/dev/null 2>&1
    tr -d '\r' < "$T/nm.log"
}

out="$(run_apply '{"version":1,"config":[
  {"type":"physical","name":"eth0","subnets":[
    {"type":"static6","address":"2001:db8:10::169/64","gateway":"2001:db8:10::1"}]},
  {"type":"nameserver","address":["8.8.8.8","2001:4860:4860::8888"]}]}')"
check "apply v6: no IPv6 address in ipv4.*" "" "$(grep -E 'ipv4\.(addresses|gateway|dns) [^ ]*:' <<<"$out" || true)"
check "apply v6: ipv6 manual"   "1" "$(grep -c 'ipv6.method manual ipv6.addresses 2001:db8:10::169/64' <<<"$out" || true)"
check "apply v6: ipv6 gateway"  "1" "$(grep -c 'ipv6.gateway 2001:db8:10::1' <<<"$out" || true)"
check "apply v6: ipv6 dns"      "1" "$(grep -c 'ipv6.dns 2001:4860:4860::8888' <<<"$out" || true)"
check "apply v6: con up"        "1" "$(grep -c '^nmcli con up rescue-eth0' <<<"$out" || true)"

out="$(run_apply '{"version":1,"config":[
  {"type":"physical","name":"eth0","subnets":[
    {"type":"static","address":"10.10.0.50","netmask":"255.255.255.0","gateway":"10.10.0.1"},
    {"type":"static6","address":"2001:db8:10::169/64","gateway":"2001:db8:10::1"}]}]}')"
check "apply dual: one connection" "1" "$(grep -c '^nmcli con add' <<<"$out" || true)"
check "apply dual: ipv4 manual"    "1" "$(grep -c 'ipv4.method manual ipv4.addresses 10.10.0.50/24' <<<"$out" || true)"
check "apply dual: ipv6 manual"    "1" "$(grep -c 'ipv6.method manual ipv6.addresses 2001:db8:10::169/64' <<<"$out" || true)"
check "apply dual: one con up"     "1" "$(grep -c '^nmcli con up' <<<"$out" || true)"

[ "$fail" = 0 ] && echo "all tests passed" || { echo "tests FAILED"; exit 1; }
