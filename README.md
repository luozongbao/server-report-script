# 🛡️ Server Report Scripts

A small collection of Bash scripts for **analyzing SSH and memory pressure** on systemd-based Linux servers. All scripts use `journalctl` for log retrieval, share the same time-range argument convention, and auto-disable color output when piped.

## 📦 Scripts

| Script | Purpose |
|--------|---------|
| [`auth-report.sh`](auth-report.sh) | Detailed SSH authentication breakdown by category, with full per-category log listings |
| [`attack-report.sh`](attack-report.sh) | Attack-focused SSH summary: top IPs, top usernames, recent events |
| [`memory-report.sh`](memory-report.sh) | Memory pressure: OOM kills, low-memory warnings, swap activity, current snapshot |
| [`lib/common.sh`](lib/common.sh) | Shared library — time parser, journalctl helpers, email sending |
| [`install.sh`](install.sh) | One-shot installer — copies scripts to `/usr/local/bin/`, `lib/` to `/usr/local/share/`, seeds `/etc/server-report-script.env` (0600) |
| [`.env.example`](.env.example) | Template for recipient / sender / msmtp config |

## 🚀 Features

- **Shared library** (`lib/common.sh`) — time parser, journalctl wrapper, helpers reused across scripts
- **Time-range argument required** — `Nm` `Nh` `Nd` `Nw` `NM` (minutes, hours, days, weeks, months)
- **Optional emailing** — `-e` / `--email` flag, `REPORT_EMAIL` env var, or `.env` file (auto-loaded); ANSI stripped from body
- **Auto-loads `.env`** — no `source .env` boilerplate; honors `$REPORT_ENV_FILE`, `$PWD/.env`, `$HOME/.config/...`, `/etc/...`
- **Install-friendly** — each script locates `lib/common.sh` itself with a 4-tier lookup, so it works whether you run from the checkout, copy scripts to `/usr/local/bin/`, or install via a distro package. If the library can't be found, you get a single actionable error with copy-paste install instructions — never a cascade of `command not found`.
- **Auto color output** — disabled when piped or redirected
- **Privilege & dependency checks** — fails fast with clear messages
- **Robust IP/username extraction** — regex-based, not positional word matching
- **Trap-based cleanup** — temporary files removed on exit

## 📋 Usage

```bash
chmod +x *.sh lib/*.sh

./auth-report.sh        12h    # last 12 hours
./attack-report.sh 3d    # last 3 days
./memory-report.sh 1w    # last 1 week

./auth-report.sh --help        # shows usage + email flags
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
sudo ./attack-report.sh --email admin@example.com 12h

# Same thing, with the short flag
sudo ./attack-report.sh -e admin@example.com 12h

# Multiple recipients + custom subject
sudo ./auth-report.sh \
    -e sec@example.com -e ops@example.com \
    -s "[ALERT] auth summary" 1d

# msmtp with a named account and explicit config path
# (no need to set env vars or rely on $HOME under sudo)
sudo ./memory-report.sh \
    --msmtp-account default \
    --msmtp-config /home/$USER/.msmtprc \
    --email admin@example.com 4h

# Recipient via env var (set once in cron)
REPORT_EMAIL=ops@example.com sudo ./memory-report.sh 1w

# Mix: default recipient from env + extra CLI recipient + override subject
sudo REPORT_EMAIL=ops@example.com \
    ./auth-report.sh -e sec@example.com \
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
sudo ./attack-report.sh 24h
```

Disable auto-loading with `REPORTS_NO_AUTOLOAD=1`. Debug which file was loaded with `REPORT_ENV_DEBUG=1`. The `.env` file itself is gitignored.

## 📥 Installation

You can run the scripts directly from the repo, or install them system-wide
with the bundled installer.

### Run from the repo

```bash
chmod +x *.sh lib/*.sh
sudo ./auth-report.sh 12h
```

### Install system-wide (`install.sh`)

The recommended way to install is the bundled installer. Run from the
repo root:

```bash
sudo ./install.sh
```

That's it — one command. The installer is **idempotent** (safe to re-run)
and produces this layout:

| Path | Mode | Source |
|------|------|--------|
| `/usr/local/bin/{auth,attack,memory}-report.sh` | `0755` | copies of the scripts |
| `/usr/local/share/server-report-script/lib/common.sh` | `0644` | the shared library |
| `/etc/server-report-script.env` | `0600` | seeded from `.env.example` (only if missing) |

After it finishes, edit the system-wide config and you're ready:

```bash
sudo $EDITOR /etc/server-report-script.env       # set REPORT_EMAIL, REPORT_SENDER, MSMTP_ACCOUNT, ...
sudo /usr/local/bin/auth-report.sh --help        # smoke-test
sudo REPORT_ENV_DEBUG=1 /usr/local/bin/auth-report.sh --help
# Expected: "🔧 Loading .env from: /etc/server-report-script.env"
sudo /usr/local/bin/attack-report.sh 5m          # end-to-end run
```

#### Installer options

```bash
sudo ./install.sh              # install (or refresh) — env file preserved if present
sudo ./install.sh --force      # overwrite an existing /etc/server-report-script.env
sudo ./install.sh --dry-run    # show what would happen, change nothing
sudo ./install.sh --uninstall  # remove scripts + lib (leaves /etc/server-report-script.env in place)
./install.sh --help            # full usage

# CI / packaging (testing only):
sudo ./install.sh --prefix /opt/server-report-script --dry-run
```

#### Library lookup chain

The scripts locate `lib/common.sh` themselves, so the install works
whether you ran the installer, copied scripts by hand, or are running
from the checkout. First match wins:

1. `$LIB_DIR` — explicit override (accepts the lib dir OR a direct path to `common.sh`)
2. `<script_dir>/lib` — bundled next to the script (works for in-repo and for `/usr/local/bin/` scripts when `lib/` was installed beside them)
3. `/usr/local/share/server-report-script/lib` — produced by `install.sh`
4. `/usr/share/server-report-script/lib` — distro-package fallback

The lookup runs *before* any function from `lib/common.sh` is called, so
system-wide installs work cleanly. If the library still can't be found,
the script prints a single error with copy-paste install instructions
rather than a cascade of `command not found`.

#### Manual install (if you prefer)

If you'd rather wire it up by hand, the equivalent of `sudo ./install.sh`
is:

```bash
sudo install -d /usr/local/bin
sudo install -m 0755 auth-report.sh attack-report.sh memory-report.sh \
    /usr/local/bin/

sudo install -d /usr/local/share/server-report-script/lib
sudo install -m 0644 lib/common.sh \
    /usr/local/share/server-report-script/lib/

sudo install -d /etc
sudo install -m 0600 .env.example /etc/server-report-script.env
```

> Email send **failures are warnings**, not errors — the script still exits 0 and prints the report to stdout.

## 🚀 Production deployment

For a real server: scripts in `/usr/local/bin/`, system-wide config in
`/etc/`, and reports running on a schedule. After `sudo ./install.sh`
you're already most of the way there — drop your config into
`/etc/server-report-script.env` and schedule the timers.

### Where `.env` should live

The scripts search for `.env` in (first match wins):

| # | Path | When to use |
|---|------|-------------|
| 1 | `$REPORT_ENV_FILE` | One-off override |
| 2 | `$PWD/.env` | Dev work in the repo |
| 3 | `$HOME/.config/server-report-script/.env` | Per-user installs |
| 4 | `/etc/server-report-script.env` | **Production, system-wide** |

**Use `/etc/server-report-script.env` for production.** Cron and systemd
both run with a stripped environment where `$HOME` and `$PWD` aren't
reliable, but `/etc/...` is always an absolute path. `install.sh`
seeds this file (mode `0600`, since SMTP creds often live there). Don't
put `.env` in `/usr/local/bin/` — it's in `PATH`, gets clobbered by
package updates, and the permissions story is messy.

```bash
# After sudo ./install.sh, edit what was seeded:
sudo $EDITOR /etc/server-report-script.env

# Or, equivalently, write it from scratch:
sudo tee /etc/server-report-script.env > /dev/null <<'EOF'
REPORT_EMAIL="admin@example.com,ops@example.com"
REPORT_SENDER="server-reports@example.com"
MSMTP_ACCOUNT="default"
EOF
sudo chmod 0600 /etc/server-report-script.env    # protect creds
```

### Install layout produced by `install.sh`

```
/usr/local/bin/
├── auth-report.sh        (0755)
├── attack-report.sh      (0755)
└── memory-report.sh      (0755)
/usr/local/share/server-report-script/
└── lib/
    └── common.sh         (0644)
/etc/
└── server-report-script.env   (0600)
```

The lib-resolution fallback chain in [lib/common.sh](lib/common.sh) finds
`lib/common.sh` at `/usr/local/share/server-report-script/lib/`
automatically — no `LIB_DIR` export needed.

### Scheduling — pick one

After `sudo ./install.sh`, the executables live in `/usr/local/bin/`
and the env config is auto-loaded from `/etc/server-report-script.env`.
Both cron and systemd paths "just work."

#### Option A — `/etc/cron.d/` (simple)

```bash
sudo install -d /var/log/server-reports
sudo tee /etc/cron.d/server-reports > /dev/null <<'EOF'
# m h dom mon dow user  command
0 6   * * *   root   /usr/local/bin/attack-report.sh 1d >> /var/log/server-reports/attack.log  2>&1
0 7   * * *   root   /usr/local/bin/auth-report.sh  1d >> /var/log/server-reports/auth.log   2>&1
0 *   * * *   root   /usr/local/bin/memory-report.sh 1h >> /var/log/server-reports/memory.log 2>&1
EOF
sudo chmod 0644 /etc/cron.d/server-reports
```

Notes:
- `/etc/cron.d/` entries **must include a username field** (here: `root`).
- Cron does not source your shell rc — but `/etc/server-report-script.env`
  is an absolute path, so it works regardless of `$HOME` / `$PWD`.
- Output is appended (use `>>` not `>`); emails are sent independently
  via the `.env` settings.

#### Option B — systemd timers (recommended for new setups)

Better logging (`journalctl -u <name>`), automatic catch-up of missed
runs, and per-service resource controls.

```bash
# Reusable service unit
sudo tee /etc/systemd/system/server-report@.service > /dev/null <<'EOF'
[Unit]
Description=Server report (%i)

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/%i.sh 1d
StandardOutput=append:/var/log/server-reports/%i.log
StandardError=append:/var/log/server-reports/%i.log
EOF

# Timers — one per report
sudo tee /etc/systemd/system/auth-report.timer > /dev/null <<'EOF'
[Unit]
Description=Daily SSH auth report

[Timer]
OnCalendar=*-*-* 07:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/attack-report.timer > /dev/null <<'EOF'
[Unit]
Description=Daily SSH attack report

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/memory-report.timer > /dev/null <<'EOF'
[Unit]
Description=Hourly memory pressure report

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now auth-report.timer attack-report.timer memory-report.timer
```

Then trigger or inspect with:

```bash
sudo systemctl start auth-report.service      # run it now
sudo journalctl -u auth-report.service -n 50 # see logs
sudo systemctl list-timers --all              # see schedule
```

The `server-report@.service` template (`%i` = instance name) means a
single unit file handles `auth-report`, `attack-report`, and
`memory-report` — change the time range by editing the `ExecStart` line
or passing `--time`.

### Verify the install

```bash
# 1. Library resolution works from /usr/local/bin/
sudo /usr/local/bin/auth-report.sh --help

# 2. .env is loaded from /etc/
sudo REPORT_ENV_DEBUG=1 /usr/local/bin/auth-report.sh --help
# Expected: 🔧 Loading .env from: /etc/server-report-script.env

# 3. End-to-end send (5-minute window, real email)
sudo /usr/local/bin/attack-report.sh 5m

# 4. Cron / timer path works
sudo /usr/local/bin/memory-report.sh 1m   # should print + email
```

### Uninstall

```bash
# Easy path: use the installer
sudo ./install.sh --uninstall

# Plus your scheduling setup, if any:
sudo rm -f /etc/cron.d/server-reports
sudo rm -f /etc/systemd/system/{auth,attack,memory,server-report@}-report.{service,timer}
sudo systemctl daemon-reload

# Plus your env file (NOT touched by --uninstall, in case there's a custom setup):
sudo rm -f /etc/server-report-script.env
```

## ⏱️ Time-range syntax

| Suffix | Meaning  | Example   |
|--------|----------|-----------|
| `Nm`   | minutes  | `45m`     |
| `Nh`   | hours    | `12h`     |
| `Nd`   | days     | `3d`      |
| `Nw`   | weeks    | `2w`      |
| `NM`   | months   | `1M`      |

## 📊 What each script reports

### `auth-report.sh`
- Accepted/failed password + publickey counts
- Invalid user, PAM failure, banner-exchange, preauth noise
- Per-category full log listings
- Totals: ✅ success / ❌ failed / ⚠️ noise

### `attack-report.sh`
- Counters: failed password, invalid user, banner exchange
- **Top 10 attacker IPs** (from Failed/Invalid/Banner events)
- **Top 10 targeted usernames**
- 10 most recent attack log entries

### `memory-report.sh`
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