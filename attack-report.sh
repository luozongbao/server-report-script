#!/bin/bash
# SSH attack-focused summary over a time window.
# Usage: ./attack-report.sh <time-range>   e.g. 45m, 12h, 3d, 2w, 1M

# Use BASH_SOURCE so this works whether the script is invoked as
#   ./attack-report.sh  /path/to/attack-report.sh  bash attack-report.sh  source attack-report.sh
SCRIPT_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR:-$SCRIPT_DIR_DEFAULT}"

# --- Locate and source lib/common.sh --------------------------------------
# Self-contained lookup so install scenarios (script copied to /usr/local/bin
# without a lib/ beside it) work without relying on common.sh being loaded.
# Search order:
#   1. $LIB_DIR                 — explicit override (accepts either the lib
#                                dir, or a direct path to common.sh)
#   2. <script_dir>/lib         — bundled next to this script (checkout)
#   3. /usr/local/share/server-report-script/lib  — system install
#   4. /usr/share/server-report-script/lib        — distro package
_LIB_CANDIDATE=""
if [ -n "${LIB_DIR:-}" ]; then
    if [ -f "$LIB_DIR/common.sh" ]; then
        _LIB_CANDIDATE="$LIB_DIR"
    elif [ -f "$LIB_DIR" ] && [ "$(basename -- "$LIB_DIR")" = "common.sh" ]; then
        _LIB_CANDIDATE="$(dirname -- "$LIB_DIR")"
    fi
fi
if [ -z "$_LIB_CANDIDATE" ] && [ -f "$SCRIPT_DIR_DEFAULT/lib/common.sh" ]; then
    _LIB_CANDIDATE="$SCRIPT_DIR_DEFAULT/lib"
fi
if [ -z "$_LIB_CANDIDATE" ]; then
    for _lib_try in \
        /usr/local/share/server-report-script/lib \
        /usr/share/server-report-script/lib; do
        if [ -f "$_lib_try/common.sh" ]; then
            _LIB_CANDIDATE="$_lib_try"
            break
        fi
    done
fi
if [ -z "$_LIB_CANDIDATE" ]; then
    cat >&2 <<'__HELP__'
❌ Cannot find lib/common.sh.

   Copy the whole project (or just lib/common.sh) to the server:
     sudo cp attack-report.sh /usr/local/bin/
     sudo mkdir -p /usr/local/share/server-report-script
     sudo cp -r lib  /usr/local/share/server-report-script/

   Or point at a custom location:
     sudo LIB_DIR=/path/to/lib ./attack-report.sh 12h
__HELP__
    exit 1
fi
# shellcheck source=lib/common.sh
source "$_LIB_CANDIDATE/common.sh"
unset _LIB_CANDIDATE _lib_try

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