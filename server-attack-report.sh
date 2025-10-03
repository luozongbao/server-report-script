#!/bin/bash
# SSH attack report using journalctl for systemd systems

# Check if journalctl is available
if ! command -v journalctl &> /dev/null; then
    echo "❌ journalctl command not found. This script requires systemd systems."
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
        *) echo "❌ Usage format: Nh Nd Nw Nm e.g. 12h, 3d, 2w"; exit 1;;
    esac
    SINCE=$(date -u --date="-$SECONDS seconds" +"%Y-%m-%dT%H:%M:%S")
    echo "🔹 Analyzing logs for the last $ARG (since $SINCE)"
else
    SINCE=""
    echo "🔹 Analyzing ALL logs"
fi
echo "---------------------------------------"

# Use journalctl to access SSH logs with time filtering
if [ -n "$SINCE" ]; then
    # Filter by time using journalctl's built-in time filtering
    FILTERED=$(journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso)
else
    # No time limit - get all SSH logs
    FILTERED=$(journalctl --no-pager _COMM=sshd --output=short-iso)
fi

# Report
FAILS=$(echo "$FILTERED" | grep "Failed password" | wc -l)
INVALID=$(echo "$FILTERED" | grep "Invalid user" | wc -l)
BANNER=$(echo "$FILTERED" | grep "banner exchange" | wc -l)

echo "1) Number of SSH login failures (Failed password): $FAILS"
echo "2) Number of Invalid user attempts: $INVALID"
echo "3) Number of Banner exchange (noise scans): $BANNER"

echo
echo "4) Top 10 IP addresses (all types):"
echo "$FILTERED" | egrep "Failed password|Invalid user|banner exchange" | \
    awk '{for(i=1;i<=NF;i++){ if ($i=="from"){print $(i+1)}}}' | \
    sort | uniq -c | sort -nr | head -10

echo
echo "5) Top 10 Usernames (from Failed/Invalid):"
echo "$FILTERED" | egrep "Failed password|Invalid user" | \
    awk '{for(i=1;i<=NF;i++){ if ($i=="user"||$i=="for"){print $(i+1)}}}' | \
    sort | uniq -c | sort -nr | head -10

echo
echo "6) Recent log examples:"
echo "$FILTERED" | egrep "Failed password|Invalid user|banner exchange" | tail -10
