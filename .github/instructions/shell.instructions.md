---
description: "Use when writing or editing any .sh file in server-report-script — bash style, naming, output glyphs, strict-mode traps, and the copy-pasted lib-finder bootstrap that must be updated in three files at once."
applyTo: "**/*.sh"
---
# Bash Conventions (`server-report-script`)

Project-level context lives in [`AGENTS.md`](../../AGENTS.md). This file covers the shell-language rules.

## Strict mode

`set -euo pipefail` is set in **`lib/common.sh:5`** and **`install.sh:22`** — *not* in the three report scripts. The report scripts inherit it when they source `common.sh`, which means **the bootstrap block at the top of each report script runs before strict mode is active**. Code you add above the `source` line sees no `-e`/`-u` protection.

## Naming

- `UPPERCASE` = global / cross-function state (`REPORT_RECIPIENTS`, `REPORT_BODY_FILE`, `REMAINING_ARGS`, `C_BOLD`, `TIME_ARG`, `SINCE`, `TMPFILE_FULL`).
- `lowercase` = `local` inside a function, or a top-level script variable in `memory-report.sh` (`mem_total`, `swap_free`).
- Colour variables are exactly six: `C_RED`, `C_GREEN`, `C_YELLOW`, `C_BLUE`, `C_BOLD`, `C_RESET`.

## Quoting and expansion

- Double-quote every expansion: `"$VAR"`, `"${VAR:-}"`. Use `"${VAR:-default}"` for optional values.
- Command substitution is always `$(...)`, never backticks.
- `$(...)` cannot set globals — `parse_email_flags` **must** be called in the current shell, never inside `$(...)`.
- Prefer `printf '%s\n' "$x"` over `echo`.

## Output glyphs

Match these exactly — they are a user-facing convention:

| Glyph | Meaning | Spacing |
|-------|---------|---------|
| `❌` | error | one space |
| `⚠️` | warning | **two** spaces |
| `✉️` | email sent | **two** spaces |
| `🔧` | debug (`.env` load path) | one space |
| `🔹` | script banner (`banner_script`) | one space |
| `▶` | section header (`section`) / installer step | one space |
| `✅` | success metric | one space |

`section` prints a blue **▶** header; `banner_script` prints a bold **🔹** title. They are not interchangeable.

## `set -e` / `pipefail` interactions

- Every `grep -c` needs `|| true` — `grep -c` exits **1** on zero matches, which would abort the script under `-e`.
- Pipelines that may legitimately be empty are written as `{ cmd || true; } | top_n 10`.
- `|| true` also swallows genuine errors (e.g. a missing temp file) — don't rely on it to detect failures.
- `journalctl … > "$TMPFILE"` is **not** `|| true`-guarded in `auth-report.sh` / `attack-report.sh` (a journalctl failure aborts), but **is** guarded in `memory-report.sh`. Match the file you are editing.

## Temp files and traps

- The `EXIT` trap is installed **only on the email path** (when a recipient is configured). Without email, `TMPFILE_FULL` / `TMPFILE_ATTACKS` / `TMPFILE_KERNEL` are left behind in `/tmp`. If you add a temp file, add it to the existing `trap 'rm -f …' EXIT` line.
- **Assign the temp variable before the first statement that can exit.** In `auth-report.sh` and `attack-report.sh` the order is `trap` → `parse_time_arg` → `TMPFILE_FULL="$(mktemp)"`. `parse_time_arg` exits 1 on an invalid range (e.g. `5x`), so the `EXIT` trap fires while `$TMPFILE_FULL` is still unset and — with `-u` inherited from `common.sh` — dies with `TMPFILE_FULL: unbound variable` instead of the intended `❌ Unknown time unit` message. `memory-report.sh` assigns `TMPFILE_KERNEL` *before* calling `parse_time_arg` and therefore exits cleanly. **Follow `memory-report.sh`:** create the temp file first, then install the trap.

## Report body capture (email path)

The idiom, identical in all three report scripts:

```bash
if [ "$REPORT_NO_EMAIL" -ne 1 ] && [ -n "$REPORT_RECIPIENTS" ]; then
    REPORT_BODY_FILE="$(mktemp)"
    trap 'rm -f "$TMPFILE_FULL" "$REPORT_BODY_FILE"' EXIT
    exec > >(tee "$REPORT_BODY_FILE" >&1)
else
    REPORT_BODY_FILE="/dev/null"
fi
```

Order is fixed: bootstrap → `load_env_file` → `require_journalctl` → `require_privileges` → `--help` → `parse_email_flags` → time-range extraction → stdout redirect → report body → `send_email_if_requested "<subject>"`.

## `--help` is the file header

The report scripts implement `--help` by slicing their own header comment:

```bash
sed -n '2,4p' "$0"    # auth-report.sh, attack-report.sh
sed -n '2,6p' "$0"    # memory-report.sh
```

**Adding or removing a header line silently changes the help output.** Keep the header block exactly 3 lines (auth/attack) or 5 lines (memory). Also note `--help` is only recognised as `$1` — it is checked before `parse_email_flags`, so `--email a@b.c --help` is *not* help.

`install.sh` uses a `usage()` function with a `cat <<'EOF'` heredoc instead — unrelated mechanism.

## The bootstrap block must be edited in three places

The inline lib-finder is byte-identical in `auth-report.sh`, `attack-report.sh`, and `memory-report.sh` (only the comment header, the error heredoc's script name, and the example time range differ). If you change it, **change all three** — they will otherwise drift.

## Environment resolution gotchas

- The `.env` loader resolves the per-user path via **`$SUDO_UID`** (through `getent passwd`), then `$SUDO_USER`, then `$HOME`. `install.sh` uses **`$SUDO_USER` only**. Two different rules in one repo — don't unify them casually.
- The `.env` search is **`$PWD`-based**, not script-directory-based. Running from a different CWD picks up a different (or no) `.env`.
- `SCRIPT_DIR` is assigned in all three report scripts but **never read** — the lookup uses `SCRIPT_DIR_DEFAULT` exclusively. `SCRIPT_DIR=/elsewhere ./script.sh` has no effect. Only `LIB_DIR` works as an override.

## Other constraints

- `parse_time_arg` uses **GNU `date`** (`date -u --date=…`). It will not work on BSD/macOS. Units are case-sensitive: `m` minutes, `h` hours, `d` days, `w` weeks, **`M` months**.
- The output timestamp has no timezone suffix (`2026-10-26T10:00:00`).
- Keep the existing shellcheck directives (`# shellcheck source=lib/common.sh`, `# shellcheck disable=SC1090`, `SC2206`, `SC2086`) — `shellcheck` is not installed locally, but the directives are intentional.
- Comments in this codebase explain **why**, and often cite the version that introduced a behaviour (`# Since 2.1.0: …`). Match that density and tone.

## Adding a new report script

1. Copy the bootstrap block from an existing report script verbatim; adjust the error heredoc's script name.
2. Keep the header comment exactly 3 lines and adjust the `sed -n` range if you use a different length.
3. Source `lib/common.sh`, call `load_env_file`, `require_journalctl`, `require_privileges`, then the `--help` branch.
4. Use `parse_email_flags "$@"` (current shell, not a subshell) and read the time range from `REMAINING_ARGS`.
5. Use `banner_script` for the title and `section` for numbered sections.
6. End with `printf "\n${C_BOLD}Reporting completed.${C_RESET}\n"` and `send_email_if_requested "<subject>"`.
7. Register the script in `install.sh` (`SRC_SCRIPTS`, the `preflight` existence check, the `install` list, and the uninstall list) and in the README tables.
