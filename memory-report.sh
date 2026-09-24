#!/bin/bash
# Memory & swap report — current state plus OOM / low-memory events from journalctl.
# Usage: ./memory-report.sh <time-range>   e.g. 45m, 12h, 3d, 2w, 1M

# Resolve script directory up front so we can locate lib/common.sh below.
# Use BASH_SOURCE so this works whether the script is invoked as
#   ./memory-report.sh  /path/to/memory-report.sh  bash memory-report.sh  source memory-report.sh
SCRIPT_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR:-$SCRIPT_DIR_DEFAULT}"

# --- Locate and source lib/common.sh --------------------------------------
# This lookup is intentionally self-contained (doesn't depend on anything from
# common.sh) so it works both when the script is run from the checkout AND
# after `sudo cp memory-report.sh /usr/local/bin/` (with no lib/ beside it).
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
     sudo cp memory-report.sh /usr/local/bin/
     sudo mkdir -p /usr/local/share/server-report-script
     sudo cp -r lib  /usr/local/share/server-report-script/

   Or point at a custom location:
     sudo LIB_DIR=/path/to/lib ./memory-report.sh 4h
__HELP__
    exit 1
fi
# shellcheck source=lib/common.sh
source "$_LIB_CANDIDATE/common.sh"
unset _LIB_CANDIDATE _lib_try
# Keep SCRIPT_DIR_DEFAULT around — some helpers below may use it.

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
    trap 'rm -f "$TMPFILE_KERNEL" "$REPORT_BODY_FILE"' EXIT
    exec > >(tee "$REPORT_BODY_FILE" >&1)
else
    REPORT_BODY_FILE="/dev/null"
fi

SINCE="$(parse_time_arg "$TIME_ARG")"
TMPFILE_KERNEL="$(mktemp)"

# Pull kernel messages for OOM / low-mem events over the window.
journalctl --no-pager --since="$SINCE" --output=short-iso -k \
    > "$TMPFILE_KERNEL" || true

banner_script "Memory report for last $TIME_ARG (since $SINCE)"

# ---- 1. Current memory state ---------------------------------------------
section "1) Current memory state (/proc/meminfo)"
if [ -r /proc/meminfo ]; then
    mem_total=$(awk '/^MemTotal:/     {print $2}' /proc/meminfo)
    mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    mem_free=$( awk '/^MemFree:/      {print $2}' /proc/meminfo)
    cached=$(   awk '/^Cached:/       {print $2}' /proc/meminfo)
    buffers=$(  awk '/^Buffers:/      {print $2}' /proc/meminfo)
    swap_total=$(awk '/^SwapTotal:/   {print $2}' /proc/meminfo)
    swap_free=$( awk '/^SwapFree:/    {print $2}' /proc/meminfo)

    to_mb() { awk -v k="$1" 'BEGIN {printf "%.1f MB", k/1024}'; }
    pct()   { awk -v a="$1" -v b="$2" 'BEGIN {if (b>0) printf "%.1f%%", a*100/b; else print "n/a"}'; }

    used=$((mem_total - mem_avail))
    swap_used=$((swap_total - swap_free))

    printf "MemTotal     : %s\n"   "$(to_mb "$mem_total")"
    printf "MemUsed      : %s  (%s)\n" "$(to_mb "$used")"   "$(pct "$used"      "$mem_total")"
    printf "MemAvailable : %s  (%s)\n" "$(to_mb "$mem_avail")" "$(pct "$mem_avail" "$mem_total")"
    printf "MemFree      : %s\n"   "$(to_mb "$mem_free")"
    printf "Cached       : %s\n"   "$(to_mb "$cached")"
    printf "Buffers      : %s\n"   "$(to_mb "$buffers")"
    printf "SwapTotal    : %s\n"   "$(to_mb "$swap_total")"
    printf "SwapUsed     : %s  (%s)\n" "$(to_mb "$swap_used")" "$(pct "$swap_used" "$swap_total")"

    # ---- pressure state ---------------------------------------------------
    if [ -r /proc/pressure/memory ]; then
        section "1b) PSI memory pressure (avg10 / avg60 / avg300 seconds)"
        awk '{
            for (i=1;i<=NF;i++) {
                if ($i ~ /^avg10=/  || $i ~ /^avg60=/ || $i ~ /^avg300=/) {
                    split($i, kv, "=")
                    printf "  %-9s : %s\n", kv[1], kv[2]
                }
            }
        }' /proc/pressure/memory
    fi
else
    echo "❌ /proc/meminfo not readable"
fi

# ---- 2. OOM kills ---------------------------------------------------------
section "2) OOM killer events"
OOM=$(grep -cE "Out of memory: Killed process|oom-kill|invoked oom-killer" \
    "$TMPFILE_KERNEL" || true)
printf "Total OOM events : %d\n\n" "$OOM"
if [ "$OOM" -gt 0 ]; then
    echo "Recent OOM events:"
    grep -E "Out of memory: Killed process|invoked oom-killer|oom_reaper" \
        "$TMPFILE_KERNEL" | tail -10 || true
fi

# ---- 3. Low-memory warnings ----------------------------------------------
section "3) Low-memory / page-allocation warnings"
LOW=$(grep -ciE "low memory|page allocation failure|killed process.*\(vmstat\)" \
    "$TMPFILE_KERNEL" || true)
printf "Total low-memory warnings : %d\n\n" "$LOW"
if [ "$LOW" -gt 0 ]; then
    echo "Recent warnings:"
    grep -iE "low memory|page allocation failure" "$TMPFILE_KERNEL" \
        | tail -10 || true
fi

# ---- 4. Swap activity -----------------------------------------------------
section "4) Swap activity"
SWAP_IN=$(  grep -c "swapin:"      "$TMPFILE_KERNEL" || true)
SWAP_OUT=$( grep -c "swapout:"     "$TMPFILE_KERNEL" || true)
printf "swap_in  events : %d\n" "$SWAP_IN"
printf "swap_out events : %d\n" "$SWAP_OUT"

# ---- 5. Top RSS processes (snapshot) -------------------------------------
section "5) Top 10 processes by RSS (current snapshot)"
if command -v ps >/dev/null 2>&1; then
    ps -eo pid,user,rss,comm --sort=-rss | head -11 | \
        awk 'NR==1 {printf "%-7s %-12s %-10s %s\n", $1, $2, "RSS(MB)", $4}
             NR>1  {printf "%-7s %-12s %-10.1f %s\n", $1, $2, $3/1024, $4}'
else
    echo "ps not available"
fi

# ---- 6. Recent kernel memory events --------------------------------------
section "6) Recent memory-related kernel log entries"
grep -iE "oom|memory|swap|allocation failure" "$TMPFILE_KERNEL" \
    | tail -15 || true

printf "\n${C_BOLD}Reporting completed.${C_RESET}\n"
send_email_if_requested "Server memory report — last $TIME_ARG ($(hostname 2>/dev/null || echo server))"