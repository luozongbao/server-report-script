# 🔐 SSH Authentication Analysis Scripts

This repository contains two scripts for analyzing SSH authentication logs using **journalctl** on systemd-based systems:

1. **`auth-summary.sh`** - Detailed authentication summary with full log display including timestamps
2. **`server-attack-report.sh`** - Attack-focused report with top IP addresses and usernames

Both scripts analyze SSH authentication events and report:

- Number of failed SSH logins (Failed password)  
- Number of invalid user attempts (Invalid user)  
- Number of banner exchange errors (bots / port scans with invalid handshake)  
- Top 10 attacker IP addresses  
- Top 10 attacker usernames  
- Latest attack log entries  

## 🚀 Features

### Modern systemd Integration
- **Uses journalctl** instead of reading log files directly
- Automatic handling of log rotation and compression
- Built-in time filtering for better performance
- Works on all systemd-based Linux distributions

### Time Filtering Support
- **Minutes**: `45m` → last 45 minutes
- **Hours**: `12h` → last 12 hours  
- **Days**: `3d` → last 3 days  
- **Weeks**: `2w` → last 2 weeks  
- **Months**: `1M` → last 1 month  

### Enhanced Output
- **Full timestamps** in all log displays (ISO format)
- **English interface** (no Thai text)
- **Detailed breakdowns** by authentication type
- **Real log entries** with complete context  

## 📋 Usage

### Prerequisites
- Linux system with **systemd** (journalctl command)
- **Root or sudo access** (required for journalctl to access SSH logs)

### auth-summary.sh (Detailed Authentication Analysis)
```bash
# Make executable
chmod +x auth-summary.sh

# Time range is REQUIRED
./auth-summary.sh 45m    # Last 45 minutes
./auth-summary.sh 12h    # Last 12 hours  
./auth-summary.sh 3d     # Last 3 days  
./auth-summary.sh 2w     # Last 2 weeks  
./auth-summary.sh 1M     # Last 1 month  
```

### server-attack-report.sh (Attack Summary)
```bash  
# Make executable
chmod +x server-attack-report.sh

# Time range is REQUIRED
./server-attack-report.sh 45m   # Last 45 minutes
./server-attack-report.sh 12h   # Last 12 hours
./server-attack-report.sh 3d    # Last 3 days
./server-attack-report.sh 2w    # Last 2 weeks
./server-attack-report.sh 1M    # Last 1 month
```  

## 📊 Example Output

### auth-summary.sh Output
```
🔹 Authentication summary for last 2h (since 2025-10-04T08:30:45)
---------------------------------------
Password: accepted=12 failed=564
PubKey  : accepted=8 failed=3
Invalid : 548
PAMfail : 2
Noise   : banner=18 preauth=5

✅ Success = 20
❌ Failed  = 1117
⚠️ Noise   = 23
Total=1160

--------------------------------

All Accepted Publickey logs:
2025-10-04T10:30:45+00:00 server sshd[12345]: Accepted publickey for admin from 192.168.1.100 port 22 ssh2
2025-10-04T10:32:15+00:00 server sshd[12389]: Accepted publickey for user from 10.0.0.50 port 22 ssh2

--------------------------------

All Failed Password logs:
2025-10-04T10:25:30+00:00 server sshd[12301]: Failed password for root from 125.17.108.32 port 45234 ssh2
2025-10-04T10:26:45+00:00 server sshd[12315]: Failed password for admin from 111.238.174.6 port 52178 ssh2
```

### server-attack-report.sh Output  
```
🔹 Analyzing logs for the last 2h (since 2025-10-04T08:30:45)
---------------------------------------
1) Number of SSH login failures (Failed password): 564
2) Number of Invalid user attempts: 548  
3) Number of Banner exchange (noise scans): 18

4) Top 10 IP addresses (all types):
48 125.17.108.32
47 111.238.174.6  
46 103.16.202.187
...

5) Top 10 Usernames (from Failed/Invalid):
312 root
249 admin
36 test
33 postgres
...

6) Recent log examples:
2025-10-04T10:53:42+00:00 server sshd[11713]: banner exchange: Connection from 3.130.96.91 port 38490: invalid format
2025-10-04T10:54:56+00:00 server sshd[11725]: Failed password for root from 20.169.104.180 port 57770 ssh2
```  

## 🔧 System Requirements

- **Linux with systemd** (Ubuntu 16.04+, CentOS 7+, Debian 8+, etc.)
- **journalctl command** available
- **Root or sudo privileges** (SSH logs are typically restricted)
- **jq package** (for auth-summary.sh JSON parsing)

### Installation of Dependencies
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install jq

# CentOS/RHEL
sudo yum install jq
# or for newer versions:
sudo dnf install jq
```

## ⚠️ Important Notes

- **These scripts only report attacks; they do not block them**
- **Requires elevated privileges** to access SSH logs via journalctl
- **Time ranges are mandatory** - no default "all logs" option for performance reasons
- **Modern systemd approach** - replaces traditional log file parsing

## 🛡️ Recommended Security Setup

Combine these analysis tools with active protection:

### SSH Hardening
```bash
# /etc/ssh/sshd_config
Port 2222                          # Custom non-standard port
PasswordAuthentication no          # Disable password auth  
PubkeyAuthentication yes          # Enable key-based auth only
PermitRootLogin no                # Disable root login
MaxAuthTries 3                    # Limit auth attempts
```

### Automated Protection
- **Fail2Ban**: Auto-ban IPs after repeated failures
- **UFW/iptables**: Restrict SSH access to trusted networks
- **Key-based authentication**: Eliminate password attacks entirely

## 📈 What's New (v2.0)

✅ **Migrated from file-based to journalctl** (better performance, automatic rotation handling)  
✅ **Added full timestamp support** in all log displays  
✅ **English interface** (replaced Thai text)  
✅ **Enhanced time filtering** (added minutes support: `45m`)  
✅ **Improved error handling** and systemd compatibility  
✅ **Mandatory time ranges** for better performance  

👨‍💻 **Authors**: Atipat Lorwongam with AI assistance  
📅 **Updated**: October 2025  

