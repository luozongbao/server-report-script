# 🛡️ Server Report Scripts

A small collection of Bash scripts for **analyzing SSH and memory pressure** on systemd-based Linux servers. All scripts use `journalctl` for log retrieval, share the same time-range argument convention, and auto-disable color output when piped.

## 📦 Scripts

| Script | Purpose |
|--------|---------|
| [`auth-summary.sh`](auth-summary.sh) | Detailed SSH authentication breakdown by category, with full per-category log listings |
| [`server-attack-report.sh`](server-attack-report.sh) | Attack-focused SSH summary: top IPs, top usernames, recent events |
| [`server-memory-report.sh`](server-memory-report.sh) | Memory pressure: OOM kills, low-memory warnings, swap activity, current snapshot |
| [`lib/common.sh`](lib/common.sh) | Shared library — time parser, journalctl helpers, email sending |
| [`.env.example`](.env.example) | Template for recipient / sender / msmtp config |

## 🚀 Features

- **Shared library** (`lib/common.sh`) — time parser, journalctl wrapper, helpers reused across scripts
- **Time-range argument required** — `Nm` `Nh` `Nd` `Nw` `NM` (minutes, hours, days, weeks, months)
- **Optional emailing** — `-e` / `--email` flag, `REPORT_EMAIL` env var, or `.env` file (auto-loaded); ANSI stripped from body
- **Auto-loads `.env`** — no `source .env` boilerplate; honors `$REPORT_ENV_FILE`, `$PWD/.env`, `$HOME/.config/...`, `/etc/...`
- **Install-friendly** — scripts find `lib/common.sh` via `$LIB_DIR`, relative to the script, or in `/usr/local/share/...`
- **Auto color output** — disabled when piped or redirected
- **Privilege & dependency checks** — fails fast with clear messages
- **Robust IP/username extraction** — regex-based, not positional word matching
- **Trap-based cleanup** — temporary files removed on exit

## 📋 Usage

```bash
chmod +x *.sh lib/*.sh

./auth-summary.sh        12h    # last 12 hours
./server-attack-report.sh 3d    # last 3 days
./server-memory-report.sh 1w    # last 1 week

./auth-summary.sh --help        # shows usage + email flags
```

## ✉️ Emailing the report

All three scripts can email the report after printing it to the terminal. The email body is a plain-text copy of the report with ANSI escapes stripped.

### CLI flags (apply to every script)

| Flag | Meaning |
|------|---------|
| `-e`, `--email ADDR` | Recipient — repeatable; combines with `$REPORT_EMAIL` |
| `-f`, `--email-from ADDR` | Sender address (default: `root@<hostname>`) |
| `-s`, `--email-subject TEXT` | Override default subject |
| `--msmtp-account NAME` | msmtp account name from `~/.msmtprc` (passed as `-a`) |
| `--msmtp-config PATH` | Path to msmtp config file (passed as `-C`) |
| `--no-email` | Skip email even if recipients are configured |

CLI flags take precedence over the env vars of the same name.

### Env vars

| Variable | Default | Purpose |
|----------|---------|---------|
| `REPORT_EMAIL` | _(unset)_ | Default recipient(s), comma-separated |
| `REPORT_SENDER` | `root@$(hostname)` | Default `From:` address |
| `EMAIL_CMD` | auto-detected | Force `msmtp`, `mail`, `mailx`, or `sendmail` |
| `MSMTP_ACCOUNT` | _(unset)_ | msmtp account name (overridden by `--msmtp-account`) |
| `MSMTP_CONFIG` | _(unset)_ | msmtp config path (overridden by `--msmtp-config`) |

### Auto-detected mailers

Detection order is **msmtp → mail → mailx → sendmail**. `msmtp` is preferred because it is a standalone SMTP client (TLS, SMTP auth, per-user config in `~/.msmtprc`) and does **not** require a running local MTA like Postfix/Exim. The other three require a local MTA to be installed and running.

The scripts build a standard RFC-822 envelope (From/To/Subject/Content-Type headers + body) and pipe it to the chosen mailer's stdin. All four supported mailers accept this format, so swapping in msmtp is a strict superset of the default behavior.

### Examples

```bash
# One-off email
sudo ./server-attack-report.sh --email admin@example.com 12h

# Same thing, with the short flag
sudo ./server-attack-report.sh -e admin@example.com 12h

# Multiple recipients + custom subject
sudo ./auth-summary.sh \
    -e sec@example.com -e ops@example.com \
    -s "[ALERT] auth summary" 1d

# msmtp with a named account and explicit config path
# (no need to set env vars or rely on $HOME under sudo)
sudo ./server-memory-report.sh \
    --msmtp-account default \
    --msmtp-config /home/zongbao/.msmtprc \
    --email admin@lorwongam.com 4h

# Recipient via env var (set once in cron)
REPORT_EMAIL=ops@example.com sudo ./server-memory-report.sh 1w

# Mix: default recipient from env + extra CLI recipient + override subject
sudo REPORT_EMAIL=ops@example.com \
    ./auth-summary.sh -e sec@example.com \
    -s "[ALERT] daily auth" 1d
```

> **Tip:** when running under `sudo`, `~/.msmtprc` won't be found because `$HOME` becomes `/root`. Always pass `--msmtp-config <path>` (or set `MSMTP_CONFIG`) when invoking with `sudo`.

### Configuration via `.env`

A template is provided at [`.env.example`](.env.example). The scripts **auto-load** a `.env` file at startup — no `set -a && source .env` boilerplate needed.

**Search order** (first match wins):

| # | Path |
|---|------|
| 1 | `$REPORT_ENV_FILE` (explicit override) |
| 2 | `$PWD/.env` (project-local — most common) |
| 3 | `$HOME/.config/server-report-script/.env` (per-user) |
| 4 | `/etc/server-report-script.env` (system-wide) |

```bash
# Copy and edit the template
cp .env.example .env
$EDITOR .env

# Just run the script — .env is picked up automatically
sudo ./server-attack-report.sh 24h
```

Disable auto-loading with `REPORTS_NO_AUTOLOAD=1`. Debug which file was loaded with `REPORT_ENV_DEBUG=1`. The `.env` file itself is gitignored.

## 📥 Installation

You can run the scripts directly from the repo, or install them system-wide.

### Run from the repo

```bash
chmod +x *.sh lib/*.sh
sudo ./auth-summary.sh 12h
```

### Install to `/usr/local/bin`

The scripts look for `lib/common.sh` in (first match wins):

1. `$LIB_DIR` (env override)
2. `<script_dir>/lib` (relative to the script — works for both in-repo and `/usr/local/bin/` if you install `lib/` alongside)
3. `/usr/local/share/server-report-script/lib`
4. `/usr/share/server-report-script/lib`

```bash
# Option A: keep lib/ alongside the scripts (simplest)
sudo install -d /usr/local/bin
sudo install -m 0755 auth-summary.sh server-attack-report.sh server-memory-report.sh /usr/local/bin/
sudo install -d /usr/local/share/server-report-script
sudo cp -r lib /usr/local/share/server-report-script/
# Now /usr/local/bin/auth-summary.sh will look for lib/common.sh in both
# /usr/local/bin/lib/ (missing) and /usr/local/share/server-report-script/lib/ (found).

# Option B: put everything under /usr/local/share and symlink the scripts
sudo install -d /usr/local/share/server-report-script
sudo install -m 0755 *.sh lib/*.sh /usr/local/share/server-report-script/
sudo install -d /usr/local/bin
sudo ln -s /usr/local/share/server-report-script/auth-summary.sh        /usr/local/bin/
sudo ln -s /usr/local/share/server-report-script/server-attack-report.sh /usr/local/bin/
sudo ln -s /usr/local/share/server-report-script/server-memory-report.sh /usr/local/bin/

# Option C: explicit override via env
sudo LIB_DIR=/opt/reports/lib ./auth-summary.sh 12h
```

After any install method, verify with:

```bash
sudo ./auth-summary.sh --help    # shows email flags
sudo ./auth-summary.sh 1h        # smoke-test the lib resolution
```

> Email send **failures are warnings**, not errors — the script still exits 0 and prints the report to stdout.

## ⏱️ Time-range syntax

| Suffix | Meaning  | Example   |
|--------|----------|-----------|
| `Nm`   | minutes  | `45m`     |
| `Nh`   | hours    | `12h`     |
| `Nd`   | days     | `3d`      |
| `Nw`   | weeks    | `2w`      |
| `NM`   | months   | `1M`      |

## 📊 What each script reports

### `auth-summary.sh`
- Accepted/failed password + publickey counts
- Invalid user, PAM failure, banner-exchange, preauth noise
- Per-category full log listings
- Totals: ✅ success / ❌ failed / ⚠️ noise

### `server-attack-report.sh`
- Counters: failed password, invalid user, banner exchange
- **Top 10 attacker IPs** (from Failed/Invalid/Banner events)
- **Top 10 targeted usernames**
- 10 most recent attack log entries

### `server-memory-report.sh`
- Current `/proc/meminfo` state with usage %
- PSI memory pressure (`/proc/pressure/memory`)
- OOM-kill events from kernel log over the window
- Low-memory and page-allocation warnings
- Swap in/out event counts
- Top 10 processes by RSS (current snapshot)
- Recent kernel memory events

## 🔧 Requirements

- Linux with **systemd** (Ubuntu 16.04+, CentOS 7+, Debian 8+, …)
- `journalctl`, `awk`, `ps` available
- **Root or sudo** required (system logs are restricted)
- `bash` 4+
- For emailing: one of **`msmtp`** (preferred — standalone SMTP client), `mail`, `mailx`, or `sendmail` on `PATH`

## ⚠️ Notes

- These scripts **only report** — they do not block or mitigate.
- All scripts return non-zero on bad input or missing privileges.

## 🛡️ Recommended companion setup

Combine these reports with active protection:

```bash
# /etc/ssh/sshd_config
Port 2222
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
MaxAuthTries 3
```

- **Fail2Ban** for automatic IP banning
- **UFW/iptables** to restrict source networks
- **Key-based authentication** to remove password attacks entirely

---

👨‍💻 Authors: Atipat Lorwongam with AI assistance
📅 Updated: 2026-09