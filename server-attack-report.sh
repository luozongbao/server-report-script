#!/bin/bash
# SSH attack-focused summary over a time window.
# Usage: ./server-attack-report.sh <time-range>   e.g. 45m, 12h, 3d, 2w, 1M

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
TMPFILE_ATTACKS="$(mktemp)"
trap 'rm -f "$TMPFILE_FULL" "$TMPFILE_ATTACKS"' EXIT

journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso \
    > "$TMPFILE_FULL"

# Subset of sshd events we treat as "attacks"
grep -E "Failed password|Invalid user|banner exchange" "$TMPFILE_FULL" \
    > "$TMPFILE_ATTACKS" || true

banner_script "Analyzing logs for the last $1 (since $SINCE)"

FAILS=$(  grep -c "Failed password"  "$TMPFILE_ATTACKS" || true)
INVALID=$(grep -c "Invalid user"      "$TMPFILE_ATTACKS" || true)
BANNER=$( grep -c "banner exchange"   "$TMPFILE_ATTACKS" || true)
TOTAL=$((FAILS + INVALID + BANNER))

printf "1) Failed password        : %d\n"  "$FAILS"
printf "2) Invalid user attempts  : %d\n"  "$INVALID"
printf "3) Banner exchange (scan) : %d\n"  "$BANNER"
printf "${C_BOLD}   Total attack events   : %d${C_RESET}\n\n" "$TOTAL"

# ---- Top IPs --------------------------------------------------------------
section "4) Top 10 attacker IP addresses"
grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' "$TMPFILE_ATTACKS" \
    | awk '{print $2}' | top_n 10

# ---- Top usernames ---------------------------------------------------------
section "5) Top 10 targeted usernames"
# Match "for <user> from ..." (password) and "Invalid user <user> from ..." (invalid).
grep -oE '(Failed password for|Invalid user) [^ ]+' "$TMPFILE_ATTACKS" \
    | awk '{print $NF}' | top_n 10

# ---- Recent events ---------------------------------------------------------
section "6) Recent attack log entries (last 10)"
tail -10 "$TMPFILE_ATTACKS" || true

printf "\n${C_BOLD}Reporting completed.${C_RESET}\n"