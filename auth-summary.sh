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
        h) RANGE="$NUM hours ago";;
        d) RANGE="$NUM days ago";;
        w) RANGE="$NUM weeks ago";;
        m) RANGE="$NUM months ago";;
        *) echo "❌ Usage: $0 Nh|Nd|Nw|Nm  (eg: 12h, 3d, 2w, 1m)"; exit 1;;
    esac
    SINCE=$(date -u --date="$RANGE" +"%Y-%m-%dT%H:%M:%S")
    echo "🔹 Authentication summary for last $ARG (since $SINCE)"
else
    SINCE="1970-01-01T00:00:00"
    echo "🔹 Authentication summary for ALL logs"
fi
echo "---------------------------------------"

# === Collect & filter logs once ===
TMPFILE=$(mktemp)
# Use journalctl to access authentication logs with time filtering
if [ "$SINCE" = "1970-01-01T00:00:00" ]; then
    # No time limit - get all logs
    journalctl --no-pager _COMM=sshd --output=json | jq -r '.MESSAGE' 2>/dev/null | grep -E "(Accepted|Failed|Invalid|authentication|banner|preauth)" > "$TMPFILE" || true
else
    # Filter by time using journalctl's built-in time filtering
    journalctl --no-pager _COMM=sshd --since="$SINCE" --output=json | jq -r '.MESSAGE' 2>/dev/null | grep -E "(Accepted|Failed|Invalid|authentication|banner|preauth)" > "$TMPFILE" || true
fi

# === Counters ===
PASS_ACCEPT=$(grep -c "Accepted password" "$TMPFILE" || true)
PASS_FAIL=$(grep -c "Failed password" "$TMPFILE" || true)
KEY_ACCEPT=$(grep -c "Accepted publickey" "$TMPFILE" || true)
KEY_FAIL=$(grep -c "Failed publickey" "$TMPFILE" || true)
INVALID=$(grep -c "Invalid user" "$TMPFILE" || true)
PAMFAIL=$(grep -ci "authentication failure" "$TMPFILE" || true)
BANNER=$(grep -c "banner exchange" "$TMPFILE" || true)
PREAUTH=$(grep -c "preauth" "$TMPFILE" || true)

rm -f "$TMPFILE"

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
