# 📝 Release Notes

All notable changes to **server-report-script** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.1.0] — 2026-09-25

Minor release — installer no longer seeds `/etc/server-report-script.env`.
The user-level XDG path is now the only path the installer manages; the
`/etc/...` location is reduced to a **read-only last-resort fallback**
in [`load_env_file`](lib/common.sh). This matches how the scripts are
actually invoked in 2026: 95% of the time as a non-cron user via
`./auth-report.sh` or `sudo ./attack-report.sh`, where seeding config
into `/etc/` is the wrong default.

### Changed (installer)
- **[`install.sh`](install.sh) no longer creates or touches
  `/etc/server-report-script.env`.** When run via `sudo`, the example
  `.env` is seeded **only** to the invoking user's XDG path —
  `/home/<user>/.config/server-report-script/.env` (mode `0700`
  directory, `0600` file, owned by `<user>`). When run without
  `$SUDO_USER` (rare), the installer skips seeding entirely and prints
  copy-paste manual instructions rather than writing to `/etc/`.
  *Behaviour change from 2.0.2, which seeded both paths.*
- **`--uninstall`** still leaves any pre-existing
  `/etc/server-report-script.env` untouched (it didn't create it, so
  removing it would be presumptuous). It only removes files it
  itself installed.
- **`--force`** still overwrites the user-level XDG seed; it no longer
  has any `/etc/` side effect.
- Layout summary (`install.sh --dry-run` first page) now points at
  `<invoking-user> ~/.config/server-report-script/.env` instead of
  `/etc/server-report-script.env`.

### Changed (library)
- *No functional change.* The [lib/common.sh](lib/common.sh)
  `load_env_file` search order still ends with `/etc/server-report-script.env`
  as a last-resort fallback, so cron / systemd timers that run as root
  with no `$SUDO_USER` context keep working — they just no longer get
  the file seeded there automatically. If you relied on that, write
  `/etc/server-report-script.env` yourself (or, better, drop a root-level
  `~/.config/server-report-script/.env` and rely on the resolved-`$HOME`
  tier above it).

### Notes
- **2.1.0 is backward-compatible with 2.0.2 in terms of running scripts.**
  Any existing `/etc/server-report-script.env` you have is still picked
  up by the auto-loader. The change is purely in what the *installer*
  writes on a fresh install.
- **If you upgrade a 2.0.2 system:** the upgrade is a no-op for any
  `/etc/server-report-script.env` you already have — `install.sh` is
  idempotent and never overwrites or deletes it. To migrate to the new
  default, just copy the file to the user-level XDG path and delete
  the `/etc` copy manually:
  ```bash
  sudo -u <user> install -d -m 0700 \
      /home/<user>/.config/server-report-script
  sudo cp /etc/server-report-script.env \
          /home/<user>/.config/server-report-script/.env
  sudo chown <user>:<user> \
          /home/<user>/.config/server-report-script/.env
  sudo chmod 0600 /home/<user>/.config/server-report-script/.env
  ```
  Skipping the migration is also fine — `/etc/server-report-script.env`
  will continue to be read as a fallback.
- After upgrading, re-run `sudo ./install.sh` to refresh
  `/usr/local/share/server-report-script/lib/common.sh` and
  `/usr/local/bin/*-report.sh`. No flags needed; the installer is
  idempotent.

---

## [2.0.2] — 2026-09-25

Patch release — small but useful improvements to email delivery,
discovered while debugging a delivery issue reported on the installed
copy at `/usr/local/bin`.

### Changed
- **Recipient deduplication.** [`parse_email_flags`](lib/common.sh) in
  [lib/common.sh](lib/common.sh) now collapses duplicate addresses before
  building the mail envelope. Previously, passing `--email ADDR` on the
  command line while `REPORT_EMAIL` was also set produced an envelope
  with `To: ADDR ADDR` (two space-separated copies of the same address),
  which worked but was ugly and could trip strict msmtp parsers.
  The new `_dedupe_recipients` helper accepts both comma- and
  space-separated input, trims whitespace, preserves first-seen order,
  and re-emits as a clean comma-separated list.

### Added
- **`MSMTP_DEBUG=1`** — when set, [lib/common.sh](lib/common.sh) passes
  `--debug` to msmtp so the full SMTP session (EHLO, STARTTLS, RCPT,
  DATA, response codes) is printed to stderr. Useful when delivery
  silently fails (auth blip, wrong `from=`, recipient rejected). Set
  it temporarily while debugging, then unset.
- **`REPORT_EMAIL_FAIL_EXIT=1`** — when set, [`send_email_if_requested`](lib/common.sh)
  exits with status `1` if the mailer returns non-zero, instead of just
  printing a warning. Recommended for cron jobs and systemd timers so
  failures alert you (cron will mail the output; a `.service` with
  `OnFailure=` can page you) instead of silently succeeding.

### Notes
- 2.0.2 is fully compatible with 2.0.1. No breaking changes.
- The default behavior is unchanged: email send failures still warn but
  exit `0`. Both new env vars are opt-in.
- After upgrading, run `sudo ./install.sh` (no flags needed — it's
  idempotent) to copy the new [lib/common.sh](lib/common.sh) into
  `/usr/local/share/server-report-script/lib/`. The installed scripts
  in `/usr/local/bin/` pick it up automatically on next run.
- Documented in [`.env.example`](.env.example) under the
  `msmtp-specific` block.

### Changed (installer)
- **`.env` now seeds to the invoking user's XDG path, not `/etc`.** When
  [`install.sh`](install.sh) detects `$SUDO_USER`, it seeds the config at
  `/home/<user>/.config/server-report-script/.env` (mode `0700` directory,
  `0600` file, owned by that user) instead of `/etc/server-report-script.env`.
  This keeps SMTP-adjacent config next to the user's `~/.msmtprc` and
  keeps the file user-private. The `/etc` path is **kept as the last-resort
  fallback** — the `load_env_file` search order in [lib/common.sh](lib/common.sh)
  still ends with `/etc/server-report-script.env`, so cron / systemd
  timers that run as root with no `$SUDO_USER` context keep working.
- The "Next steps" output now tells you *which* level was used (user vs.
  system) and prints the right `sudo -u <user> $EDITOR ...` command when
  applicable.

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
