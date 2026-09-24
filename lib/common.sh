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

# ---- Email support ---------------------------------------------------------
# Globals used by send_email_if_requested (set by parse_email_flags):
#   REPORT_RECIPIENTS   space-separated list of recipients
#   REPORT_SENDER       From: address
#   REPORT_NO_EMAIL     1 = skip email even if recipients are set
#   REPORT_BODY_FILE    path to file that already contains the report body
# (Callers are expected to redirect all stdout to $REPORT_BODY_FILE when
#  email is requested, then invoke send_email_if_requested at the end.)

# Detect an available mailer. Echoes the binary name; empty if none.
# msmtp is checked first because it's a standalone SMTP client (TLS, auth,
# per-user config) and needs no running MTA. Fall back to local MTAs.
detect_mailer() {
    for m in msmtp mail mailx sendmail; do
        if command -v "$m" >/dev/null 2>&1; then
            printf '%s\n' "$m"
            return 0
        fi
    done
    return 1
}

# Build the mailer invocation. Honors $EMAIL_CMD first, then $MSMTP_ACCOUNT,
# then auto-detection. Echoes "<mailer>|<extra-args>" so the caller can
# split when invoking. msmtp gets "-a <account>" when MSMTP_ACCOUNT is set.
mailer_command() {
    local mailer="${EMAIL_CMD:-}"
    local extra=""

    if [ -z "$mailer" ]; then
        if ! mailer="$(detect_mailer)"; then
            return 1
        fi
    elif ! command -v "$mailer" >/dev/null 2>&1; then
        echo "⚠️  EMAIL_CMD='$mailer' not found." >&2
        return 1
    fi

    if [ "$mailer" = "msmtp" ] && [ -n "${MSMTP_ACCOUNT:-}" ]; then
        extra="-a $MSMTP_ACCOUNT"
    fi

    printf '%s|%s\n' "$mailer" "$extra"
}

# Build a clean plain-text copy of the report (strip ANSI escapes) into a temp
# file and echo it. Requires REPORT_BODY_FILE to already be populated.
strip_ansi_copy() {
    local out
    out="$(mktemp)"
    # Remove ANSI CSI sequences: ESC [ ... letter
    sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$REPORT_BODY_FILE" > "$out"
    printf '%s\n' "$out"
}

# Parse --email / --email-from / --email-subject / --no-email out of the
# argument list. Sets REPORT_RECIPIENTS / REPORT_SENDER / REPORT_SUBJECT /
# REPORT_NO_EMAIL globals and writes remaining positional args into the
# REMAINING_ARGS global array. Must be called in the *current* shell
# (NOT inside $(...) command substitution), because globals don't survive
# subshell boundaries.
parse_email_flags() {
    REPORT_RECIPIENTS="${REPORT_RECIPIENTS:-}"
    REPORT_SENDER="${REPORT_SENDER:-root@$(hostname -f 2>/dev/null || hostname)}"
    REPORT_SUBJECT="${REPORT_SUBJECT:-}"
    REPORT_NO_EMAIL="${REPORT_NO_EMAIL:-0}"
    REMAINING_ARGS=()

    # Allow comma-separated env var as a default.
    if [ -n "${REPORT_EMAIL:-}" ]; then
        REPORT_RECIPIENTS="$REPORT_EMAIL"
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --email)
                [ $# -ge 2 ] || { echo "❌ --email requires an address" >&2; exit 1; }
                REPORT_RECIPIENTS="${REPORT_RECIPIENTS:+$REPORT_RECIPIENTS }$2"
                shift 2
                ;;
            --email=*)
                REPORT_RECIPIENTS="${REPORT_RECIPIENTS:+$REPORT_RECIPIENTS }${1#--email=}"
                shift
                ;;
            --email-from)
                [ $# -ge 2 ] || { echo "❌ --email-from requires an address" >&2; exit 1; }
                REPORT_SENDER="$2"
                shift 2
                ;;
            --email-from=*)
                REPORT_SENDER="${1#--email-from=}"
                shift
                ;;
            --email-subject)
                [ $# -ge 2 ] || { echo "❌ --email-subject requires text" >&2; exit 1; }
                REPORT_SUBJECT="$2"
                shift 2
                ;;
            --email-subject=*)
                REPORT_SUBJECT="${1#--email-subject=}"
                shift
                ;;
            --no-email)
                REPORT_NO_EMAIL=1
                shift
                ;;
            --msmtp-account)
                [ $# -ge 2 ] || { echo "❌ --msmtp-account requires a name" >&2; exit 1; }
                MSMTP_ACCOUNT="$2"
                shift 2
                ;;
            --msmtp-account=*)
                MSMTP_ACCOUNT="${1#--msmtp-account=}"
                shift
                ;;
            --msmtp-config)
                [ $# -ge 2 ] || { echo "❌ --msmtp-config requires a path" >&2; exit 1; }
                MSMTP_CONFIG="$2"
                shift 2
                ;;
            --msmtp-config=*)
                MSMTP_CONFIG="${1#--msmtp-config=}"
                shift
                ;;
            --)
                shift
                while [ $# -gt 0 ]; do REMAINING_ARGS+=("$1"); shift; done
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Print the email-flag help block. Scripts include it in --help output.
email_help() {
    cat <<'EOF'
Email options:
  --email ADDR             Send report to ADDR (repeatable; combines with $REPORT_EMAIL)
  --email-from ADDR        From: address (default: root@<hostname>)
  --email-subject TEXT     Override default subject
  --msmtp-account NAME     msmtp account name from ~/.msmtprc (passed as -a)
  --msmtp-config PATH      Path to msmtp config file (passed as -C)
  --no-email               Skip email even if recipients are configured

Env vars:
  REPORT_EMAIL             Default recipient(s), comma-separated
  REPORT_SENDER            Default From: address
  EMAIL_CMD                Force a specific mailer: msmtp, mail, mailx, sendmail
  MSMTP_ACCOUNT            Default msmtp account (overridden by --msmtp-account)
  MSMTP_CONFIG             Default msmtp config path (overridden by --msmtp-config)
EOF
}

# Send $REPORT_BODY_FILE to $REPORT_RECIPIENTS. No-op if no recipients or
# --no-email was passed. Always exits 0 (email failures are warnings).
send_email_if_requested() {
    local default_subject="$1"

    if [ "$REPORT_NO_EMAIL" -eq 1 ]; then
        return 0
    fi
    if [ -z "$REPORT_RECIPIENTS" ]; then
        return 0
    fi

    local mailer extra mailer_pair
    if ! mailer_pair="$(mailer_command)"; then
        echo "⚠️  No mail client found (msmtp/mail/mailx/sendmail). Skipping email." >&2
        return 0
    fi
    mailer="${mailer_pair%%|*}"
    extra="${mailer_pair#*|}"
    # extra is "" unless msmtp + MSMTP_ACCOUNT. Also support MSMTP_CONFIG (-C).
    if [ "$mailer" = "msmtp" ] && [ -n "${MSMTP_CONFIG:-}" ]; then
        extra="$extra -C $MSMTP_CONFIG"
    fi

    local subject="${REPORT_SUBJECT:-$default_subject}"
    local clean_body
    clean_body="$(strip_ansi_copy)"
    local hostname_short
    hostname_short="$(hostname 2>/dev/null || echo server)"

    # Build a simple header + body. We avoid -a "From:" because mailx/mail
    # flag syntax differs; pipe headers via sendmail-style envelope instead.
    local envelope
    envelope="$(mktemp)"
    {
        printf 'From: %s\n' "$REPORT_SENDER"
        printf 'To: %s\n' "$REPORT_RECIPIENTS"
        printf 'Subject: %s\n' "$subject"
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf 'X-Report-Host: %s\n' "$hostname_short"
        printf '\n'
        cat "$clean_body"
    } > "$envelope"

    # Invoke the mailer. All four supported mailers accept "< envelope" and
    # honor the From/To headers in the envelope (or extract them from the
    # body via -t). msmtp adds -a/-C when configured.
    local rc=0
    # shellcheck disable=SC2086
    "$mailer" -t $extra < "$envelope" || rc=$?

    rm -f "$envelope" "$clean_body"

    if [ "$rc" -ne 0 ]; then
        echo "⚠️  Email send failed (mailer=$mailer, rc=$rc). Report still printed above." >&2
    else
        printf '%s✉️  Report emailed to: %s%s\n' "${C_GREEN}" "$REPORT_RECIPIENTS" "${C_RESET}"
    fi
    return 0
}