#!/bin/bash
# SSH attack report for ISO8601 logs (/var/log/auth.log on systemd machines)

LOGDIR="/var/log"
LOGFILES=$(ls -1 ${LOGDIR}/auth.log* 2>/dev/null)

if [ -z "$LOGFILES" ]; then
    echo "❌ ไม่พบไฟล์ log ที่ ${LOGDIR}/auth.log*"
    exit 1
fi

# parse argument (Nh, Nd, Nw, Nm)
if [ -n "$1" ]; then
    ARG=$1
    UNIT=${ARG: -1}
    NUM=${ARG%?}
    case $UNIT in
        h) SECONDS=$((NUM*3600));;
        d) SECONDS=$((NUM*86400));;
        w) SECONDS=$((NUM*604800));;
        m) SECONDS=$((NUM*2592000));;
        *) echo "❌ ใช้รูปแบบ Nh Nd Nw Nm เช่น 12h, 3d, 2w"; exit 1;;
    esac
    SINCE=$(date -u --date="-$SECONDS seconds" +"%Y-%m-%dT%H:%M:%S")
    echo "🔹 กำลังวิเคราะห์ log ย้อนหลัง $ARG (ตั้งแต่ $SINCE)"
else
    SINCE="1970-01-01T00:00:00"
    echo "🔹 กำลังวิเคราะห์ log ทั้งหมด"
fi
echo "---------------------------------------"

TMPFILE=$(mktemp)
for f in $LOGFILES; do
    if [[ "$f" == *.gz ]]; then
        zcat "$f" >> $TMPFILE
    else
        cat "$f" >> $TMPFILE
    fi
done

FILTERED=$(awk -v since="$SINCE" '
{
    ts=$1
    gsub("\\..*","",ts)         # ตัด sub-second
    gsub("\\+.*","",ts)         # ตัด timezone
    if (ts >= since) print $0
}' $TMPFILE)
rm -f $TMPFILE

# Report
FAILS=$(echo "$FILTERED" | grep "Failed password" | wc -l)
INVALID=$(echo "$FILTERED" | grep "Invalid user" | wc -l)
BANNER=$(echo "$FILTERED" | grep "banner exchange" | wc -l)

echo "1) จำนวน ssh login ล้มเหลว (Failed password): $FAILS"
echo "2) จำนวน Invalid user attempts: $INVALID"
echo "3) จำนวน Banner exchange (noise scans): $BANNER"

echo
echo "4) Top 10 IP (ทุกประเภท):"
echo "$FILTERED" | egrep "Failed password|Invalid user|banner exchange" | \
    awk '{for(i=1;i<=NF;i++){ if ($i=="from"){print $(i+1)}}}' | \
    sort | uniq -c | sort -nr | head -10

echo
echo "5) Top 10 Username (จาก Failed/Invalid):"
echo "$FILTERED" | egrep "Failed password|Invalid user" | \
    awk '{for(i=1;i<=NF;i++){ if ($i=="user"||$i=="for"){print $(i+1)}}}' | \
    sort | uniq -c | sort -nr | head -10

echo
echo "6) ตัวอย่าง log ล่าสุด:"
echo "$FILTERED" | egrep "Failed password|Invalid user|banner exchange" | tail -10
