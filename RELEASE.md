# 📝 Release Notes

All notable changes to **server-report-script** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.1] — 2026-09-24

Small QoL release — bundled a one-shot installer so the system-wide
install no longer requires copying five `install -m ...` snippets from
the README.

### Added
- **[`install.sh`](install.sh)** — single-command system install. Run as
  root from the repo:
  ```bash
  sudo ./install.sh
  ```
  Produces:
  - `/usr/local/bin/{auth,attack,memory}-report.sh` (`0755`)
  - `/usr/local/share/server-report-script/lib/common.sh` (`0644`)
  - `/etc/server-report-script.env` (`0600`, seeded from `.env.example` —
    only if missing; existing files are preserved)
  Idempotent and re-runnable. Supports `--force` (overwrite the env
  file), `--dry-run`, `--uninstall`, `--prefix DIR` (for CI/packaging),
  and `--help`.

### Changed
- **README install flow simplified.** The "Install to `/usr/local/bin`"
  section now leads with `sudo ./install.sh`. The verbose manual steps
  are kept as a "Manual install" sub-section for users who prefer them,
  and the production-deployment section explicitly mentions that
  `install.sh` already produces the right layout.
- **Production deployment section** now starts with a one-liner pointing
  at the installer and explicitly references `/etc/server-report-script.env`
  (the recommended cron/timer config path).
- **Uninstall section** uses `sudo ./install.sh --uninstall` as the
  primary path, with manual `rm` commands kept as a fallback.

### Notes
- 2.0.1 is fully compatible with 2.0.0 — no breaking changes. If you
  already installed 2.0.0 by hand, `sudo ./install.sh` will lay down the
  same files in the same places, then leave your existing
  `/etc/server-report-script.env` untouched.
- The lib-resolution chain in [lib/common.sh](lib/common.sh) was not
  changed; the installer honors it (scripts land in `/usr/local/bin/`,
  `lib/` in `/usr/local/share/server-report-script/lib/`, the third
  fallback path in the chain).

---

## [2.0.0] — 2026-09-24 — *The rewrite*

The 1.x line was a quick collection of inline scripts. **2.0 is a full
rewrite** that consolidates every script onto a single shared library,
adds optional email delivery, and introduces a brand-new memory-pressure
report. Treat this as a major release.

### ⚠️ Breaking changes
- **Script names unified.** All three scripts follow a consistent
  `*-report.sh` convention. **Any cron jobs, systemd timers, or shell
  aliases referencing the old names will stop working.**
  | Old name | New name |
  |----------|----------|
  | `auth-summary.sh` | [`auth-report.sh`](auth-report.sh) |
  | `server-attack-report.sh` | [`attack-report.sh`](attack-report.sh) |
  | `server-memory-report.sh` | [`memory-report.sh`](memory-report.sh) |
- **New shared library** ([`lib/common.sh`](lib/common.sh)). Every script
  now sources it — if you were inlining helpers, drop those snippets.
- **Bootstrap order changed.** Each script does a self-contained lookup
  for `lib/common.sh` before defining any functions (see *Fixed* below).
  Custom wrappers that pre-set `PATH` or `LD_LIBRARY_PATH` are unaffected.

### Upgrade steps
1. Replace old names anywhere they're invoked:
   ```bash
   sed -i 's/auth-summary\.sh/auth-report.sh/g;           \
           s/server-attack-report\.sh/attack-report.sh/g; \
           s/server-memory-report\.sh/memory-report.sh/g' \
          /etc/cron.d/* /etc/systemd/system/*.timer ~/.bashrc
   ```
2. Re-test cron commands — the scripts behave identically otherwise.
3. Pull the new files (old names are removed from the repo).
4. If you have a system-wide install, copy `lib/` alongside the scripts:
   ```bash
   sudo install -d /usr/local/share/server-report-script
   sudo install -m 0755 auth-report.sh attack-report.sh memory-report.sh \
       /usr/local/share/server-report-script/
   sudo cp -r lib /usr/local/share/server-report-script/
   ```

### Added
- **[`memory-report.sh`](memory-report.sh)** — *new script.* Reports
  current `/proc/meminfo` state, PSI memory pressure, OOM kills,
  low-memory and page-allocation warnings, swap activity, and the
  top-10 processes by RSS. Uses the same time-range argument as the
  SSH reports.
- **Optional email delivery for every script.** Reports can be
  emailed after printing:
  - `-e` / `--email ADDR` flag (repeatable for multiple recipients)
  - `-f` / `--email-from ADDR` for the sender
  - `-s` / `--email-subject TEXT` to override the subject
  - `--msmtp-account NAME` and `--msmtp-config PATH` for msmtp users
    (essential under `sudo`, where `$HOME` becomes `/root`)
  - `--no-email` to skip sending even when recipients are configured
- **Auto-loading `.env` files.** No more `set -a && source .env && set +a`
  boilerplate. The scripts look for `.env` in:
  1. `$REPORT_ENV_FILE` (explicit override)
  2. `$PWD/.env` (project-local)
  3. `$HOME/.config/server-report-script/.env` (per-user)
  4. `/etc/server-report-script.env` (system-wide)
  Disable with `REPORTS_NO_AUTOLOAD=1`; debug with `REPORT_ENV_DEBUG=1`.
- **Support for multiple mailers.** `msmtp` (preferred — standalone SMTP
  client, no local MTA required) is auto-detected first, then `mail`,
  `mailx`, `sendmail`. Force with `EMAIL_CMD`.
- **`$LIB_DIR` override** for system-wide installs. Accepts either the
  lib directory or a direct path to `lib/common.sh`.
- **[`.env.example`](.env.example)** template documenting every variable.
- **[`.gitignore`](.gitignore)** covering `.env`, logs, editor junk, etc.

### Changed
- **Full rewrite.** Every script is now a thin wrapper around
  [`lib/common.sh`](lib/common.sh) — no more copy-pasted helpers.
- All scripts use `${BASH_SOURCE[0]}` for path resolution, so they work
  whether invoked as `./script.sh`, `bash script.sh`, or sourced.
- Email sending uses a standard RFC-822 envelope piped to the mailer's
  stdin — works for msmtp, mail, mailx, and sendmail.
- Reports auto-disable ANSI color when piped or redirected.
- Privilege / dependency checks fail fast with clear, single-line errors.

### Fixed
- **Critical: chicken-and-egg in `lib/common.sh` resolution.** The 1.x
  scripts called `resolve_lib_dir` *before* `lib/common.sh` was sourced,
  even though the function was *defined inside* it. After a system-wide
  install (e.g. scripts in `/usr/local/bin/`, no `lib/` beside them)
  this produced a confusing cascade of `command not found` errors and
  a blank "Usage" line. The 2.0 bootstrap is now self-contained and
  prints a single, actionable error with install instructions if
  `lib/common.sh` can't be found.
- `set -e` + `pipefail` no longer aborts `attack-report.sh` when the
  attack-log window is empty (the `grep -oE` pipeline now tolerates
  empty input via `{ ... || true; }`).
- IP and username extraction is regex-based, not positional — fewer
  false positives in noisy logs.

---

## [1.1.0] — 2026-09-24

### Added
- Email-sending via msmtp / mail / mailx / sendmail.
- Auto-loading `.env` files.
- `$LIB_DIR` override for system-wide installs.

### Changed
- All scripts use `${BASH_SOURCE[0]}` for path resolution.

### Fixed
- `set -e` + `pipefail` empty-input tolerance in `attack-report.sh`.

---

## [1.0.0] — initial release

### Added
- [`auth-report.sh`](auth-report.sh) — full SSH authentication breakdown
  with per-category log listings.
- [`attack-report.sh`](attack-report.sh) — attack-focused summary with
  top attacker IPs, targeted usernames, and recent events.
- [`memory-report.sh`](memory-report.sh) — memory pressure report
  covering current state, PSI, OOM kills, low-memory warnings, swap,
  and top RSS processes.
- [`lib/common.sh`](lib/common.sh) — shared library: time parser,
  journalctl helpers, color output, ANSI stripping, privilege checks.
