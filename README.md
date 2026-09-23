# 🛡️ Server Report Scripts

A small collection of Bash scripts for **analyzing SSH and memory pressure** on systemd-based Linux servers. All scripts use `journalctl` for log retrieval, share the same time-range argument convention, and auto-disable color output when piped.

## 📦 Scripts

| Script | Purpose |
|--------|---------|
| [`auth-summary.sh`](auth-summary.sh) | Detailed SSH authentication breakdown by category, with full per-category log listings |
| [`server-attack-report.sh`](server-attack-report.sh) | Attack-focused SSH summary: top IPs, top usernames, recent events |
| [`server-memory-report.sh`](server-memory-report.sh) | Memory pressure: OOM kills, low-memory warnings, swap activity, current snapshot |

## 🚀 Features

- **Shared library** (`lib/common.sh`) — time parser, journalctl wrapper, helpers reused across scripts
- **Time-range argument required** — `Nm` `Nh` `Nd` `Nw` `NM` (minutes, hours, days, weeks, months)
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

./auth-summary.sh --help        # shows usage
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