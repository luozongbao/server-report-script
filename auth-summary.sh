#!/bin/bash
# Detailed SSH authentication summary over a time window.
# Usage: ./auth-summary.sh <time-range>   e.g. 45m, 12h, 3d, 2w, 1M

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_journalctl
require_privileges

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,4p' "$0"
    exit 0
fi

SINCE="$(parse_time_arg "${1-}")"
TMPFILE_FULL="$(mktemp)"
trap 'rm -f "$TMPFILE_FULL"' EXIT

journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso \
    > "$TMPFILE_FULL"

banner_script "Authentication summary for last $1 (since $SINCE)"

# ---- Counters --------------------------------------------------------------
PASS_ACCEPT=$(grep -c "Accepted password"   "$TMPFILE_FULL" || true)
PASS_FAIL=$(  grep -c "Failed password"     "$TMPFILE_FULL" || true)
KEY_ACCEPT=$( grep -c "Accepted publickey"  "$TMPFILE_FULL" || true)
KEY_FAIL=$(   grep -c "Failed publickey"    "$TMPFILE_FULL" || true)
INVALID=$(    grep -c "Invalid user"        "$TMPFILE_FULL" || true)
PAMFAIL=$(    grep -ci "authentication failure" "$TMPFILE_FULL" || true)
BANNER=$(     grep -c "banner exchange"     "$TMPFILE_FULL" || true)
PREAUTH=$(    grep -c " preauth"            "$TMPFILE_FULL" || true)

SUCCESS=$((PASS_ACCEPT + KEY_ACCEPT))
FAIL=$((    PASS_FAIL   + KEY_FAIL   + INVALID + PAMFAIL))
NOISE=$((   BANNER      + PREAUTH))
TOTAL=$((   SUCCESS     + FAIL       + NOISE))

printf "Password : accepted=%-6d  failed=%-6d\n" "$PASS_ACCEPT" "$PASS_FAIL"
printf "PubKey   : accepted=%-6d  failed=%-6d\n" "$KEY_ACCEPT"  "$KEY_FAIL"
printf "Invalid  : %d\n"  "$INVALID"
printf "PAMfail  : %d\n"  "$PAMFAIL"
printf "Noise    : banner=%-4d  preauth=%-4d\n\n" "$BANNER" "$PREAUTH"

printf "${C_GREEN}✅ Success = %d${C_RESET}\n" "$SUCCESS"
printf "${C_RED}❌ Failed  = %d${C_RESET}\n" "$FAIL"
printf "${C_YELLOW}⚠️  Noise   = %d${C_RESET}\n" "$NOISE"
printf "Total = %d\n" "$TOTAL"

# ---- Per-category log listings --------------------------------------------
emit_logs() {
    local title="$1"; shift
    local pattern="$1"
    section "$title"
    if [ "$pattern" = "preauth_noise" ]; then
        grep -E "banner exchange| preauth" "$TMPFILE_FULL" || true
    else
        grep "$pattern" "$TMPFILE_FULL" || true
    fi
}

emit_logs "All Accepted Publickey logs" "Accepted publickey"
emit_logs "All Accepted Password logs" "Accepted password"
emit_logs "All Failed Publickey logs"   "Failed publickey"
emit_logs "All Failed Password logs"   "Failed password"
emit_logs "All Invalid User logs"      "Invalid user"
emit_logs "All Noise / Preauth logs"   "preauth_noise"

printf "\n${C_BOLD}Reporting completed.${C_RESET}\n"