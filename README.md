# 🛡️ Server Report Scripts

A small collection of Bash scripts for **analyzing SSH and memory pressure** on systemd-based Linux servers. All scripts use `journalctl` for log retrieval, share the same time-range argument convention, and auto-disable color output when piped.

## 📦 Scripts

| Script | Purpose |
|--------|---------|
| [`auth-report.sh`](auth-report.sh) | Detailed SSH authentication breakdown by category, with full per-category log listings |
| [`attack-report.sh`](attack-report.sh) | Attack-focused SSH summary: top IPs, top usernames, recent events |
| [`memory-report.sh`](memory-report.sh) | Memory pressure: OOM kills, low-memory warnings, swap activity, current snapshot |
| [`lib/common.sh`](lib/common.sh) | Shared library — time parser, journalctl helpers, email sending |
| [`install.sh`](install.sh) | One-shot installer — copies scripts to `/usr/local/bin/`, `lib/` to `/usr/local/share/`, seeds a user-level `.env` at `~/.config/server-report-script/.env`. `load_env_file` still reads `/etc/server-report-script.env` as a read-only last-resort fallback for cron / systemd timers. |
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
| `MSMTP_CONFIG` | _(unset)_ | msmtp config path (overridden by `--msmtp-config`). **Set this when running under sudo** — see below. |
| `MSMTP_DEBUG` | `0` | When `1`, passes `--debug` to msmtp so the full SMTP session is printed. |
| `REPORT_EMAIL_FAIL_EXIT` | `0` | When `1`, the script exits non-zero if email send fails (use for cron / systemd timers). |

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

# System-wide install + cron: write /root/.config/server-report-script/.env
# pointing at a root-readable .msmtprc (e.g. /etc/msmtprc). Cron / systemd
# timers run as root, so $HOME=/root and the unprivileged user's ~/.msmtprc
# won't be used. (2.1.0+: install.sh no longer seeds /etc/...env for you;
# /etc/server-report-script.env still works as a read-only fallback if you
# write it yourself.)
sudo install -d -m 0700 /root/.config/server-report-script
sudo tee /root/.config/server-report-script/.env >/dev/null <<'EOF'
MSMTP_ACCOUNT=default
MSMTP_CONFIG=/etc/msmtprc
EOF
sudo chmod 0600 /root/.config/server-report-script/.env
sudo /usr/local/bin/memory-report.sh --email admin@example.com 4h   # uses env file

# Recipient via env var (set once in cron)
REPORT_EMAIL=ops@example.com sudo ./memory-report.sh 1w

# Mix: default recipient from env + extra CLI recipient + override subject
sudo REPORT_EMAIL=ops@example.com \
    ./auth-report.sh -e sec@example.com \
    -s "[ALERT] daily auth" 1d
```

> **Tip:** when running under `sudo`, `~/.msmtprc` won't be found because `$HOME` becomes `/root` (and the original user's home may not be readable). Always pass `--msmtp-config <path>` (or set `MSMTP_CONFIG`) when invoking with `sudo`. For system-wide installs, point it at a root-readable location such as `/etc/msmtprc` and put that path in `/root/.config/server-report-script/.env` (cron's `$HOME`) so cron / systemd timers pick it up automatically. The legacy `/etc/server-report-script.env` still works as a read-only fallback if you keep using it.

### Configuration via `.env`

A template is provided at [`.env.example`](.env.example). The scripts **auto-load** a `.env` file at startup — no `set -a && source .env` boilerplate needed.

**Search order** (first match wins):

| # | Path |
|---|------|
| 1 | `$REPORT_ENV_FILE` (explicit override) |
| 2 | `$PWD/.env` (project-local — most common) |
| 3 | `$HOME/.config/server-report-script/.env` (per-user) |
| 4 | `/etc/server-report-script.env` (system-wide, **read-only fallback since 2.1.0**) |

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
| `/home/<user>/.config/server-report-script/.env` *(when run via sudo)* | `0700` dir / `0600` file | seeded from `.env.example`, **owned by the invoking user** |
| `/etc/server-report-script.env` *(read-only fallback)* | `0600` | **NOT created by `install.sh` 2.1.0+** — still readable as the last-resort fallback in the `.env` search order, useful for cron / systemd timers running as root |

The `.env` file lands at the **invoking user's XDG path** (`$SUDO_USER`'s
`~/.config/server-report-script/.env`) so the SMTP-adjacent config lives
next to the user's `~/.msmtprc` and stays user-private. `/etc/server-report-script.env`
is preserved as a **last-resort fallback** — picked up by the auto-loader
only when no user-level config exists. This matters for cron / systemd
timers that run as root with no `$SUDO_USER` context: they fall through to
`/etc/...` automatically.

> **Installer change in 2.1.0:** `install.sh` no longer seeds
> `/etc/server-report-script.env`. If you want a fallback there, write
> the file yourself (the installer won't manage it). See
> [RELEASE.md](RELEASE.md) → `2.1.0` for migration notes.

After it finishes, edit the config the installer chose and you're ready:

```bash
# User-level install (run via sudo):
sudo -u <user> $EDITOR /home/<user>/.config/server-report-script/.env
sudo /usr/local/bin/auth-report.sh --help        # smoke-test
sudo REPORT_ENV_DEBUG=1 /usr/local/bin/auth-report.sh --help
# Expected: "🔧 Loading .env from: /home/<user>/.config/server-report-script/.env"
sudo /usr/local/bin/attack-report.sh 5m          # end-to-end run

# System-only fallback (no $SUDO_USER / cron-only setup):
sudo install -d -m 0700 /root/.config/server-report-script
sudo tee /root/.config/server-report-script/.env > /dev/null <<'EOF'
# ...your config...
EOF
sudo chmod 0600 /root/.config/server-report-script/.env
# Expected: "🔧 Loading .env from: /root/.config/server-report-script/.env"
```

#### Installer options

```bash
sudo ./install.sh              # install (or refresh) — env file preserved if present
sudo ./install.sh --force      # overwrite the existing .env (user-level when run via sudo, else /etc)
sudo ./install.sh --dry-run    # show what would happen, change nothing
sudo ./install.sh --uninstall  # remove scripts + lib (leaves any .env in place)
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

# 2.1.0+: install.sh does NOT seed /etc/server-report-script.env.
# Either let install.sh create the user-level XDG seed for you
# (default when run via sudo) or set up your cron config by hand:
sudo -u <user> install -d -m 0700 \
    /home/<user>/.config/server-report-script
sudo -u <user> install -m 0600 .env.example \
    /home/<user>/.config/server-report-script/.env
```
per-user `.env` at
`~/.config/server-report-script/.env`, and reports running on a schedule.
After `sudo ./install.sh` you're already most of the way there — drop your
config into the seeded XDG `.env` (or root's `~/.config/...` for cron) and
schedule the timers.

### Where `.env` should live

The scripts search for `.env` in (first match wins):

| # | Path | When to use |
|---|------|-------------|
| 1 | `$REPORT_ENV_FILE` | One-off override |
| 2 | `$PWD/.env` | Dev work in the repo |
| 3 | `$HOME/.config/server-report-script/.env` | **Default install location** (per-user XDG; `install.sh` seeds here when run via `sudo`). For cron, use `/root/.config/server-report-script/.env`. |
| 4 | `/etc/server-report-script.env` | **Read-only last-resort fallback** (no longer seeded by `install.sh` 2.1.0+). Still useful for crontabs that already use it — write the file by hand. |

**The installer seeds the per-user XDG path** (`$SUDO_USER`'s
`~/.config/server-report-script/.env`, mode `0700` dir + `0600` file,
owned by that user) by default. `/etc/server-report-script.env` is
preserved as a **read-only last-resort fallback** — the auto-loader still
reads it, but the installer doesn't write or manage it. Useful for cron /
systemd timers that run as root with no `$SUDO_USER` context, and for
multi-admin setups that don't map to a single user. Both paths work;
the auto-loader just searches them in order.

If you run cron as a non-root user, point the crontab at the user-level
`.env` directly with `REPORT_ENV_FILE=...` instead of relying on `$HOME`.

Don't put `.env` in `/usr/local/bin/` — it's in `PATH`, gets clobbered by
package updates, and the permissions story is messy.

```bash
# After sudo ./install.sh, edit what was seeded (user-level):
sudo -u <user> $EDITOR /home/<user>/.config/server-report-script/.env

# Or, for system-only / cron-as-root setups, write a root-level XDG .env:
sudo install -d -m 0700 /root/.config/server-report-script
sudo tee /root/.config/server-report-script/.env > /dev/null <<'EOF'
REPORT_EMAIL="admin@example.com,ops@example.com"
REPORT_SENDER="server-reports@example.com"
MSMTP_ACCOUNT="default"
MSMTP_CONFIG=/etc/msmtprc
EOF
sudo chmod 0600 /root/.config/server-report-script/.env    # protect creds
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
# 2.1.0+ — no /etc/server-report-script.env is created here.
# The installer only writes to the user's ~/.config/server-report-script/.env
# (or prints manual instructions when there's no $SUDO_USER).
# /etc/server-report-script.env is only read by the auto-loader as a fallback.
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

After `sudo ./install.sh`, the executables live in `/usr/local/bin/` and
the env config auto-loads from whichever `.env` path the auto-loader
finds first — typically `/root/.config/server-report-script/.env` for
cron / systemd timers, falling back to `/etc/server-report-script.env`
if you've written one there yourself. Both cron and systemd paths
"just work."

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
- Cron does not source your shell rc. The `load_env_file` auto-loader
  reads in order: `$REPORT_ENV_FILE`, `$PWD/.env`,
  `/root/.config/server-report-script/.env` (resolved-`$HOME` for
  cron), then `/etc/server-report-script.env` (last-resort fallback).
  Use whichever path makes sense for your setup.
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