#!/bin/bash
# SSH Authentication Summary with Time Filter (Nh, Nd, Nw, Nm)

set -euo pipefail
# Use journalctl for log access instead of direct file access

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

# === Collect & filter logs once ===
TMPFILE=$(mktemp)
TMPFILE_FULL=$(mktemp)
# Use journalctl to access authentication logs with time filtering
# Get logs with timestamps in short-iso format for better readability
journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso | grep -E "(Accepted|Failed|Invalid|authentication|banner|preauth)" > "$TMPFILE_FULL" || true
# Extract just messages for counting (preserve original functionality)
cat "$TMPFILE_FULL" | awk '{$1=""; $2=""; $3=""; print substr($0,4)}' > "$TMPFILE" || true

# === Counters ===
PASS_ACCEPT=$(grep -c "Accepted password" "$TMPFILE" || true)
PASS_FAIL=$(grep -c "Failed password" "$TMPFILE" || true)
KEY_ACCEPT=$(grep -c "Accepted publickey" "$TMPFILE" || true)
KEY_FAIL=$(grep -c "Failed publickey" "$TMPFILE" || true)
INVALID=$(grep -c "Invalid user" "$TMPFILE" || true)
PAMFAIL=$(grep -ci "authentication failure" "$TMPFILE" || true)
BANNER=$(grep -c "banner exchange" "$TMPFILE" || true)
PREAUTH=$(grep -c "preauth" "$TMPFILE" || true)

# === Totals ===
TOTAL=$((PASS_ACCEPT + PASS_FAIL + KEY_ACCEPT + KEY_FAIL + INVALID + PAMFAIL + BANNER + PREAUTH))
SUCCESS=$((PASS_ACCEPT + KEY_ACCEPT))
FAIL=$((PASS_FAIL + KEY_FAIL + INVALID + PAMFAIL))
NOISE=$((BANNER + PREAUTH))

# === Report ===
echo "Password: accepted=$PASS_ACCEPT failed=$PASS_FAIL"
echo "PubKey  : accepted=$KEY_ACCEPT failed=$KEY_FAIL"
echo "Invalid : $INVALID"
echo "PAMfail : $PAMFAIL"
echo "Noise   : banner=$BANNER preauth=$PREAUTH"
echo
echo "✅ Success = $SUCCESS"
echo "❌ Failed  = $FAIL"
echo "⚠️ Noise   = $NOISE"
echo "Total=$TOTAL"
echo ""
echo "--------------------------------"
echo ""
echo "All Accepted Publickey logs:"
grep "Accepted publickey" "$TMPFILE_FULL" || true
echo ""
echo "--------------------------------" 
echo ""
echo "All Accepted Password logs:"
grep "Accepted password" "$TMPFILE_FULL" || true
echo ""
echo "--------------------------------"
echo ""
echo "All Failed Publickey logs:"
grep "Failed publickey" "$TMPFILE_FULL" || true
echo ""
echo "--------------------------------"
echo ""
echo "All Failed Password logs:"
grep "Failed password" "$TMPFILE_FULL" || true
echo ""
echo "--------------------------------"
echo ""
echo "All Invalid User logs:"
grep "Invalid user" "$TMPFILE_FULL" || true
echo ""
echo "--------------------------------"
echo ""
rm -f "$TMPFILE" "$TMPFILE_FULL"
echo "Reporting completed."

