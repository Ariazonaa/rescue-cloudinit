#!/bin/bash
# smart-full.sh -- full SMART report for each VM disk; optional self-test.
. /root/rescue-lib.sh
for d in $(target_disks); do
    hr; echo "SMART: $d  ($(lsblk -dno SIZE "$d" 2>/dev/null | xargs), $(lsblk -dno MODEL "$d" 2>/dev/null | xargs))"; hr
    if smartctl -H "$d" >/dev/null 2>&1 && smartctl -H "$d" 2>/dev/null | grep -qiE 'PASSED|FAILED'; then
        smartctl -H "$d" 2>/dev/null | grep -iE 'result|PASSED|FAILED'
        echo "-- key attributes --"
        smartctl -A "$d" 2>/dev/null | grep -iE 'Reallocated|Pending|Uncorrect|Wear|Power_On_Hours|Temperature|Media_Wearout|Percentage' | sed 's/^/  /'
    else
        echo "  no SMART data (virtual disk or unsupported)"
    fi
done
echo
read -rp "Start a SHORT self-test on a disk? Enter device (blank = skip): " dev
if [ -n "$dev" ] && [ -b "$dev" ]; then
    smartctl -t short "$dev" 2>/dev/null && echo "self-test started; results later with: smartctl -a $dev"
fi
