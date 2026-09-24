# 📝 Release Notes

All notable changes to **server-report-script** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] — 2026-09-24

### ⚠️ Breaking changes
- **Script names unified.** The three scripts now follow a consistent
  `*-report.sh` convention. **Any cron jobs, systemd timers, or shell
  aliases referencing the old names will stop working.**
  - `auth-summary.sh` → [`auth-report.sh`](auth-report.sh)
  - `server-attack-report.sh` → [`attack-report.sh`](attack-report.sh)
  - `server-memory-report.sh` → [`memory-report.sh`](memory-report.sh)
- All cross-references in [README.md](README.md), [`.env.example`](.env.example),
  and in-script header comments were updated to the new names.

### Upgrade steps
1. Replace the old names anywhere they're invoked:
   ```bash
   sed -i 's/auth-summary\.sh/auth-report.sh/g;           \
           s/server-attack-report\.sh/attack-report.sh/g; \
           s/server-memory-report\.sh/memory-report.sh/g' \
          /etc/cron.d/* /etc/systemd/system/*.timer ~/.bashrc
   ```
2. Re-test any cron commands — the scripts behave identically otherwise.
3. Pull the new files. The old files are removed from the repo.

### Changed
- No behavioral changes to report contents, flags, env vars, or `.env`
  auto-load behavior — only file names changed.

---

## [1.1.0] — 2026-09-24

### Added
- **Email-sending via msmtp / mail / mailx / sendmail.** All three scripts
  can email the report automatically:
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
- **`$LIB_DIR` override** for system-wide installs (`/usr/local/bin/`,
  `/usr/share/...`), so `lib/common.sh` can live anywhere.
- **`.env.example`** template documenting every variable.
- **`.gitignore`** covering `.env`, logs, editor junk, etc.

### Changed
- All scripts use `${BASH_SOURCE[0]}` for path resolution, so they work
  whether invoked as `./script.sh`, `bash script.sh`, or sourced.
- Email sending uses an RFC-822 envelope piped to the mailer's `-t` flag.

### Fixed
- `set -e` + `pipefail` no longer aborts `attack-report.sh` when the
  attack-log window is empty (the `grep -oE` pipeline now tolerates
  empty input via `{ ... || true; }`).

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
