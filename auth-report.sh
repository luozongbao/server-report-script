#!/bin/bash
# Detailed SSH authentication summary over a time window.
# Usage: ./auth-report.sh <time-range>   e.g. 45m, 12h, 3d, 2w, 1M

# Use BASH_SOURCE so this works whether the script is invoked as
#   ./auth-report.sh  /path/to/auth-report.sh  bash auth-report.sh  source auth-report.sh
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
     sudo cp auth-report.sh /usr/local/bin/
     sudo mkdir -p /usr/local/share/server-report-script
     sudo cp -r lib  /usr/local/share/server-report-script/

   Or point at a custom location:
     sudo LIB_DIR=/path/to/lib ./auth-report.sh 12h
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
    trap 'rm -f "$TMPFILE_FULL" "$REPORT_BODY_FILE"' EXIT
    exec > >(tee "$REPORT_BODY_FILE" >&1)
else
    REPORT_BODY_FILE="/dev/null"
fi

SINCE="$(parse_time_arg "$TIME_ARG")"
TMPFILE_FULL="$(mktemp)"

journalctl --no-pager _COMM=sshd --since="$SINCE" --output=short-iso \
    > "$TMPFILE_FULL"

banner_script "Authentication summary for last $TIME_ARG (since $SINCE)"

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
send_email_if_requested "SSH auth summary — last $TIME_ARG ($(hostname 2>/dev/null || echo server))"