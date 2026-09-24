#!/bin/bash
# Installer for server-report-script.
#
# Idempotent. Re-running is safe — existing files are left in place unless
# --force is passed. Run from the repo root:
#
#   sudo ./install.sh           # install (or refresh) the system copy
#   sudo ./install.sh --force   # overwrite any existing /etc config
#   sudo ./install.sh --dry-run # print what would happen, change nothing
#   sudo ./install.sh --uninstall
#   ./install.sh --help
#
# Layout produced:
#   /usr/local/bin/{auth,attack,memory}-report.sh        (0755)
#   /usr/local/share/server-report-script/lib/common.sh (0644)
#   /etc/server-report-script.env                        (0600)  — only if missing
#
# The .env is created from .env.example if it doesn't already exist on disk.
# /etc/server-report-script.env is intentionally chmod 0600 because users
# often drop SMTP credentials inside it.

set -euo pipefail

# --- Paths (overridable for testing) ---------------------------------------
PREFIX_BIN="${PREFIX_BIN:-/usr/local/bin}"
PREFIX_SHARE="${PREFIX_SHARE:-/usr/local/share/server-report-script}"
PREFIX_ETC="${PREFIX_ETC:-/etc}"

SCRIPT_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SCRIPTS=(auth-report.sh attack-report.sh memory-report.sh)
SRC_LIB="lib"

# --- Colors (auto-disabled when not a TTY) ---------------------------------
if [ -t 1 ]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
    C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_RESET=''
fi

die() { printf '%s❌ %s%s\n' "${C_RED}" "$*" "${C_RESET}" >&2; exit 1; }
info() { printf '%s▶ %s%s\n' "${C_GREEN}" "$*" "${C_RESET}"; }
warn() { printf '%s⚠️  %s%s\n' "${C_YELLOW}" "$*" "${C_RESET}"; }

usage() {
    cat <<'EOF'
Usage: sudo ./install.sh [OPTIONS]

Install server-report-script system-wide.

Options:
  --force         Overwrite existing /etc/server-report-script.env
  --dry-run       Print what would happen, change nothing
  --uninstall     Remove everything this script installs
  --prefix DIR    Install under DIR (defaults to /usr/local, /etc)
                 (For testing; not needed for normal installs.)
  -h, --help      Show this help

Files installed:
  <prefix>/bin/{auth,attack,memory}-report.sh        (0755)
  <prefix>/share/server-report-script/lib/common.sh  (0644)
  /etc/server-report-script.env                      (0600, only if missing)

When /etc/server-report-script.env already exists, it is left alone unless
--force is passed. Edit it with:  sudo \$EDITOR /etc/server-report-script.env
EOF
}

# --- Argument parsing ------------------------------------------------------
FORCE=0
DRY_RUN=0
UNINSTALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force)    FORCE=1;    shift ;;
        --dry-run)  DRY_RUN=1;  shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --prefix)
            [ $# -ge 2 ] || die "--prefix requires a directory argument"
            PREFIX_BIN="$2/bin"
            PREFIX_SHARE="$2/share/server-report-script"
            shift 2
            ;;
        -h|--help)  usage; exit 0 ;;
        *) die "Unknown argument: $1 (try --help)" ;;
    esac
done

# --- Root check (only for real installs; dry-run + help don't need it) -----
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Must be run as root (or via sudo). Try: sudo $0"
    fi
}

# --- Helpers ---------------------------------------------------------------
# run_cmd <description> <cmd...>
# Echoes the command (with dry-run marker) and runs it unless --dry-run.
run_cmd() {
    local desc="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  [dry-run] %s\n' "$desc"
        printf '           %s\n' "$*"
    else
        printf '  • %s\n' "$desc"
        "$@"
    fi
}

# --- Uninstall -------------------------------------------------------------
do_uninstall() {
    require_root
    info "Uninstalling server-report-script"
    run_cmd "remove scripts from $PREFIX_BIN" \
        rm -f "$PREFIX_BIN/auth-report.sh" \
              "$PREFIX_BIN/attack-report.sh" \
              "$PREFIX_BIN/memory-report.sh"
    run_cmd "remove $PREFIX_SHARE" rm -rf "$PREFIX_SHARE"
    if [ -f "$PREFIX_ETC/server-report-script.env" ]; then
        warn "Found $PREFIX_ETC/server-report-script.env — leaving it in place"
        warn "Remove manually with:  sudo rm $PREFIX_ETC/server-report-script.env"
    fi
    info "Done. (Re-run $0 to reinstall.)"
}

# --- Pre-flight checks -----------------------------------------------------
preflight() {
    # Run from repo root (so ./install.sh works) — installer sources scripts
    # from the repo, not from itself, so the CWD matters.
    cd "$SCRIPT_DIR_DEFAULT"

    for s in "${SRC_SCRIPTS[@]}"; do
        [ -f "$s" ] || die "Missing $s in $SCRIPT_DIR_DEFAULT — run from the repo root"
    done
    [ -f "$SRC_LIB/common.sh" ] || die "Missing $SRC_LIB/common.sh"

    if [ "$DRY_RUN" -ne 1 ]; then
        require_root
    fi
}

# --- Main install ----------------------------------------------------------
do_install() {
    preflight

    info "Installing server-report-script"
    printf '   bin   : %s\n' "$PREFIX_BIN"
    printf '   share : %s\n' "$PREFIX_SHARE"
    printf '   etc   : %s/server-report-script.env\n' "$PREFIX_ETC"

    # 1. Scripts to /usr/local/bin/ (0755)
    run_cmd "create $PREFIX_BIN" install -d "$PREFIX_BIN"
    for s in "${SRC_SCRIPTS[@]}"; do
        run_cmd "install $s -> $PREFIX_BIN/" \
            install -m 0755 "$s" "$PREFIX_BIN/$s"
    done

    # 2. lib/ to /usr/local/share/server-report-script/ (0644).
    # Create the lib/ subdirectory BEFORE populating it so install(1)
    # doesn't try to write to a missing parent.
    run_cmd "create $PREFIX_SHARE" install -d "$PREFIX_SHARE"
    run_cmd "create $PREFIX_SHARE/lib" install -d "$PREFIX_SHARE/lib"
    # Copy each shell file from lib/ into the target dir.
    for f in "$SRC_LIB"/*.sh; do
        # Skip the literal pattern if glob didn't match (no .sh files).
        [ -f "$f" ] || continue
        run_cmd "install ${f#$SCRIPT_DIR_DEFAULT/} -> $PREFIX_SHARE/lib/" \
            install -m 0644 "$f" "$PREFIX_SHARE/lib/"
    done

    # 3. /etc/server-report-script.env from .env.example (0600).
    # PREFIX_ETC is /etc by default but respects --prefix for testing.
    local env_path="$PREFIX_ETC/server-report-script.env"
    local example="$SCRIPT_DIR_DEFAULT/.env.example"
    if [ -f "$env_path" ] && [ "$FORCE" -ne 1 ]; then
        warn "$env_path already exists — leaving as is (use --force to overwrite)"
        warn "Edit with:  sudo \$EDITOR $env_path"
    else
        if [ ! -f "$example" ]; then
            die "Cannot seed $env_path — $example missing in the repo"
        fi
        run_cmd "create $PREFIX_ETC" install -d "$PREFIX_ETC"
        run_cmd "install $example -> $env_path (mode 0600)" \
            install -m 0600 "$example" "$env_path"
    fi

    info "Installed."
    printf '\n'
    printf '%sNext steps:%s\n' "${C_BOLD}" "${C_RESET}"
    printf '  1. Edit the system config:\n'
    printf '       sudo $EDITOR %s\n' "$env_path"
    printf '  2. Verify the install:\n'
    printf '       sudo /usr/local/bin/auth-report.sh --help\n'
    printf '       sudo REPORT_ENV_DEBUG=1 /usr/local/bin/auth-report.sh --help\n'
    printf '  3. Smoke-test from the shell:\n'
    printf '       sudo /usr/local/bin/attack-report.sh 5m\n'
}

# --- Dispatch --------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall
else
    do_install
fi
