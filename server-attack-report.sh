#!/bin/bash
# SSH attack-focused summary over a time window.
# Usage: ./server-attack-report.sh <time-range>   e.g. 45m, 12h, 3d, 2w, 1M

# Use BASH_SOURCE so this works whether the script is invoked as
#   ./server-attack-report.sh  /path/to/server-attack-report.sh  bash server-attack-report.sh  source server-attack-report.sh
SCRIPT_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR:-$SCRIPT_DIR_DEFAULT}"
LIB_DIR_RESOLVED="$(resolve_lib_dir 2>/dev/null || echo "$SCRIPT_DIR_DEFAULT/lib")"
# shellcheck source=lib/common.sh
source "$LIB_DIR_RESOLVED/common.sh"
unset LIB_DIR_RESOLVED SCRIPT_DIR_DEFAULT

# Auto-load .env if present (no-op if not).
load_env_file

require_journalctl
require_privileges

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,4p' "$0"
    echo
    email_help
    exit 0
fi

# Pull email flags out first; whatever remains is the time range.
parse_email_flags "$@"
if [ "${#REMAINING_ARGS[@]}" -lt 1 ]; then
    echo "❌ Usage: $0 [--email ADDR]... <time-range>" >&2
    exit 1
fi
TIME_ARG="${REMAINING_ARGS[0]}"

# If email is requested, capture all stdout to a file (we still tee to TTY).
if [ "$REPORT_NO_EMAIL" -ne 1 ] && [ -n "$REPORT_RECIPIENTS" ]; then
    REPORT_BODY_FILE="$(mktemp)"
    trap 'rm -f "$TMPFILE_FULL" "$TMPFILE_ATTACKS" "$REPORT_BODY_FILE"' EXIT
    exec > >(tee "$REPORT_BODY_FILE" >&1)
else
    REPORT_BODY_FILE="/dev/null"
fi

SINCE="$(parse_time_arg "$TIME_ARG")"
TMPFILE_FULL="$(mktemp)"
TMPFILE_ATTACKS="$(mktemp)"

journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso \
    > "$TMPFILE_FULL"

# Subset of sshd events we treat as "attacks"
grep -E "Failed password|Invalid user|banner exchange" "$TMPFILE_FULL" \
    > "$TMPFILE_ATTACKS" || true

banner_script "Analyzing logs for the last $TIME_ARG (since $SINCE)"

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
{ grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' "$TMPFILE_ATTACKS" \
    | awk '{print $2}' || true; } | top_n 10

# ---- Top usernames ---------------------------------------------------------
section "5) Top 10 targeted usernames"
# Match "for <user> from ..." (password) and "Invalid user <user> from ..." (invalid).
{ grep -oE '(Failed password for|Invalid user) [^ ]+' "$TMPFILE_ATTACKS" \
    | awk '{print $NF}' || true; } | top_n 10

# ---- Recent events ---------------------------------------------------------
section "6) Recent attack log entries (last 10)"
tail -10 "$TMPFILE_ATTACKS" || true

printf "\n${C_BOLD}Reporting completed.${C_RESET}\n"
send_email_if_requested "SSH attack report — last $TIME_ARG ($(hostname 2>/dev/null || echo server))"