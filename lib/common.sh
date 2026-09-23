#!/bin/bash
# Shared helpers for server-report-script
# Source this file from other scripts:  source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# ---- Colors (auto-disabled when not a TTY) ---------------------------------
if [ -t 1 ]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_RESET=''
fi

# ---- Systemd check ---------------------------------------------------------
require_journalctl() {
    if ! command -v journalctl >/dev/null 2>&1; then
        echo "❌ journalctl not found. These scripts require a systemd-based system." >&2
        exit 1
    fi
}

# ---- Privilege check -------------------------------------------------------
require_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ Root/sudo privileges required to read system logs." >&2
        exit 1
    fi
}

# ---- Time-argument parser --------------------------------------------------
# Accepts:  45m 12h 3d 2w 1M
# Prints:   <since_iso>   (UTC, e.g. 2026-09-23T10:00:00)
# Exits non-zero on bad input.
parse_time_arg() {
    local arg="${1-}"
    if [ -z "$arg" ]; then
        echo "❌ Usage: <time-range>   e.g. 45m, 12h, 3d, 2w, 1M" >&2
        exit 1
    fi
    local unit="${arg: -1}"
    local num="${arg%?}"
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid time range: '$arg'" >&2
        exit 1
    fi
    case "$unit" in
        m) local range="$num minutes ago" ;;
        h) local range="$num hours ago"   ;;
        d) local range="$num days ago"    ;;
        w) local range="$num weeks ago"   ;;
        M) local range="$num months ago"  ;;
        *) echo "❌ Unknown time unit '$unit'. Use m|h|d|w|M." >&2; exit 1 ;;
    esac
    date -u --date="$range" +"%Y-%m-%dT%H:%M:%S"
}

# ---- Section header --------------------------------------------------------
section() {
    printf '\n%s%s▶ %s%s\n' "${C_BOLD}" "${C_BLUE}" "$1" "${C_RESET}"
    printf '%s\n' "-------------------------------------------"
}

# ---- Top-N counter from a stream of tokens ---------------------------------
# Reads tokens (one per line) on stdin, prints the top N with counts, descending.
top_n() {
    local n="${1:-10}"
    sort | uniq -c | sort -nr | head -n "$n"
}

# ---- IP extractor ----------------------------------------------------------
# Extracts IPv4 addresses from a stream of sshd log lines.
# Avoids false positives by requiring the line to be an sshd event.
extract_ips() {
    grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' \
        | awk '{print $2}' \
        | top_n 10
}

# ---- Banner printing -------------------------------------------------------
banner_script() {
    local title="$1"
    printf '%s🔹 %s%s\n' "${C_BOLD}" "$title" "${C_RESET}"
    printf '%s\n' "-------------------------------------------"
}