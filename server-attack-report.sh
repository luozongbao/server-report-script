#!/bin/bash
# SSH attack report using journalctl for systemd systems

# Check if journalctl is available
if ! command -v journalctl &> /dev/null; then
    echo "❌ journalctl command not found. This script requires systemd systems."
    exit 1
fi

# === Parse time argument ===
if [ -n "${1-}" ]; then
    ARG=$1
    UNIT=${ARG: -1}
    NUM=${ARG%?}
    case $UNIT in
        m) RANGE="$NUM minutes ago";;
        h) RANGE="$NUM hours ago";;
        d) RANGE="$NUM days ago";;
        w) RANGE="$NUM weeks ago";;
        M) RANGE="$NUM months ago";;
        *) echo "❌ Usage: $0 Nm|Nh|Nd|Nw|NM  (eg: 45m 12h, 3d, 2w, 1M)"; exit 1;;
    esac
    SINCE=$(date -u --date="$RANGE" +"%Y-%m-%dT%H:%M:%S")
    echo "🔹 Authentication summary for last $ARG (since $SINCE)"
else
    echo "Must provide time range argument (e.g. 45m, 12h, 3d, 2w, 1M)"
    exit 1
fi
echo "---------------------------------------"

# Use journalctl to access SSH logs with time filtering
# Filter by time using journalctl's built-in time filtering
FILTERED=$(journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso)

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
