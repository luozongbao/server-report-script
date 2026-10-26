# Project Guidelines

Bash toolkit for analyzing SSH auth activity and memory pressure on systemd-based Linux servers via `journalctl`. Ships three report scripts, one installer, and one shared library.

**No build step, no dependencies, no test suite, no CI.** The deliverable *is* the source file.

## Layout

| Path | Role |
|------|------|
| [`auth-report.sh`](auth-report.sh) | SSH auth breakdown by category — time range **required** |
| [`attack-report.sh`](attack-report.sh) | Attack-focused SSH summary (top IPs, top usernames) — time range **required** |
| [`memory-report.sh`](memory-report.sh) | Memory / OOM / swap report — time range **optional** (omitted ⇒ full kernel ring buffer) |
| [`install.sh`](install.sh) | Idempotent installer → `/usr/local/bin`, `/usr/local/share/…`, user XDG `.env` |
| [`lib/common.sh`](lib/common.sh) | The **only** shared code: `.env` loader, time parser, journal helpers, email sender |
| [`README.md`](README.md) | User-facing docs: install, cron/systemd scheduling, env vars, CLI flags |
| [`RELEASE.md`](RELEASE.md) | Changelog — the **only** place a version number lives |

`install.sh` deliberately does **not** source `lib/common.sh`; it is fully self-contained.

## Architecture rules

### 1. The lib-finder bootstrap is copy-pasted across three files — change all three

`auth-report.sh`, `attack-report.sh`, and `memory-report.sh` each inline an identical **self-contained** lib-finder, then `source` `lib/common.sh`. It must stay self-contained because `resolve_lib_dir()` *lives inside* `common.sh` — calling it before sourcing is a chicken-and-egg `command not found` cascade (the 1.x bug fixed in 2.0).

Search order (first match wins):

1. `$LIB_DIR` — explicit override; accepts either the lib **dir** or a direct path to `common.sh`
2. `<script_dir>/lib` — bundled checkout, and `/usr/local/bin` when `lib/` sits beside the script
3. `/usr/local/share/server-report-script/lib` — produced by `install.sh`
4. `/usr/share/server-report-script/lib` — distro-package fallback

> `resolve_lib_dir()` in [`lib/common.sh:77`](lib/common.sh#L77) is **dead code** — nothing calls it. `extract_ips()` at [`lib/common.sh:165`](lib/common.sh#L165) is dead too (`attack-report.sh` inlines the regex). Do not call either; do not delete them without checking `RELEASE.md` history.

### 2. `lib/common.sh` is the only shared module

Anything used by two or more report scripts belongs there. Anything used by exactly one belongs in that script (e.g. `top_n()` is attack-only; `emit_logs()` is auth-only). Keep `common.sh` free of script-specific logic.

### 3. `install.sh` is a separate universe

It does not source `common.sh` and it duplicates the `C_*` color block (without `C_BLUE`). It has its own `die()` / `info()` / `warn()` / `run_cmd()` helpers and its own `usage()` heredoc — the report scripts do **not** use `getopts`; they use `parse_email_flags` from `common.sh` instead.

## Verifying a change

There is no automated test suite — **you must verify manually**, and say so in your summary. `shellcheck` is not installed on this machine, but the codebase carries shellcheck directives, so keep them intact.

```bash
# 1. Syntax check everything (fast, no privileges needed)
for f in *.sh lib/*.sh; do bash -n "$f" || echo "SYNTAX FAIL: $f"; done

# 2. Unit-test the shared library without sudo
bash -c 'source lib/common.sh; parse_time_arg 45m; parse_email_flags --email a@b.c --email a@b.c; echo "$REPORT_RECIPIENTS"'

# 3. Library resolution — note `--help` requires root (privilege check runs first)
sudo ./memory-report.sh --help
LIB_DIR=/usr/local/share/server-report-script/lib bash /usr/local/bin/memory-report.sh --help

# 4. End-to-end (real email — use a 5m window)
sudo ./attack-report.sh 5m --email you@example.com

# 5. Installer dry-run (never mutates)
sudo ./install.sh --dry-run
```

Two traps when verifying:

- **`--help` needs root.** `require_privileges` runs *before* the `--help` branch, so a non-root user gets `❌ Root/sudo privileges required to read system logs.` and exit 1 — not the help text.
- **A copy of the script in `/tmp` may still resolve a library** via tier 3 (`/usr/local/share/…` exists on this machine). To exercise the "library not found" path you must also hide that directory.

## Release process

- **The version number lives only in `RELEASE.md`.** There is no `VERSION` constant in the shell code — do not add one. Code comments reference versions in prose (e.g. `# Since 2.1.0: …`).
- `RELEASE.md` follows Keep a Changelog + SemVer. Sections used: `### Added`, `### Changed`, `### Fixed`, `### Notes`, plus scoped variants like `### Changed (installer)` / `### Changed (library)` and `### ⚠️ Breaking changes`.
- Every entry links the touched file (`[\`install.sh\`](install.sh)`) and, where useful, the exact function. Behaviour changes must state whether they are breaking or backward-compatible.
- Dates are `YYYY-MM-DD`.
- Branch flow: feature branch → `dev` → PR → `main`. Tags use the odd `v.2.1.0` form (dot after the `v`).
- **Update `README.md` and `RELEASE.md` together** — the README duplicates the env-var, CLI-flag, and install-layout tables that the code changes.
- After a release, note that `sudo ./install.sh` is idempotent and refreshes the installed copies.

## Security

- **`.env` is gitignored and holds real recipients, sender addresses, and msmtp credentials.** Never `cat` it, never echo its contents into a commit, a log, or chat output. Use [`.env.example`](.env.example) as the template when documenting config.
- The project is intended to be **public**. Never hardcode credentials, real addresses, or hostnames in tracked files.
- `REPORT_SENDER` / `REPORT_EMAIL` defaults live in `.env`, not in code.

## Repo memory

Previously-debugged issues are recorded in the workspace repo memory (`server-report-script.md`). Check it before re-investigating the lib-finder bootstrap ordering.
