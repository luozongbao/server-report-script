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
- **Optional emailing** — `--email` flag or `REPORT_EMAIL` env var; ANSI stripped from body
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
| `--email ADDR` | Recipient — repeatable; combines with `$REPORT_EMAIL` |
| `--email-from ADDR` | Sender address (default: `root@<hostname>`) |
| `--email-subject TEXT` | Override default subject |
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

# Multiple recipients + custom subject
sudo ./auth-summary.sh \
    --email sec@example.com --email ops@example.com \
    --email-subject "[ALERT] auth summary" 1d

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
    ./auth-summary.sh --email sec@example.com \
    --email-subject "[ALERT] daily auth" 1d
```

> **Tip:** when running under `sudo`, `~/.msmtprc` won't be found because `$HOME` becomes `/root`. Always pass `--msmtp-config <path>` (or set `MSMTP_CONFIG`) when invoking with `sudo`.

### Configuration via `.env`

A template is provided at [`.env.example`](.env.example). Copy and edit:

```bash
cp .env.example .env
set -a && source .env && set +a
sudo ./server-attack-report.sh 24h
```

The `.env` file is gitignored.

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