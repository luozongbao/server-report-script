# 🔐 SSH Attack Report Script

This script analyzes SSH brute force attempts from `/var/log/auth.log` (and rotated log files) and reports:

- Number of failed SSH logins (Failed password)  
- Number of invalid user attempts (Invalid user)  
- Number of banner exchange errors (bots / port scans with invalid handshake)  
- Top 10 attacker IP addresses  
- Top 10 attacker usernames  
- Latest attack log entries  

## 🚀 Features
- Supports time filtering with arguments (Nh, Nd, Nw, Nm)  
  • 12h → last 12 hours  
  • 3d → last 3 days  
  • 2w → last 2 weeks  
  • 1m → last 1 month  

- Supports rotated log files (auth.log, auth.log.1, auth.log.*.gz)  
- Works with ISO8601 log format (systemd-journald style with timestamps like 2025-09-26T19:46:05+07:00)  
- Easy to run, no dependencies beyond bash, awk, zcat  

## 📋 Usage
1. Save the script as: ssh-attack-report.sh  
2. Make it executable: chmod +x ssh-attack-report.sh  
3. Run it:  

   • Analyze all logs  
     ./ssh-attack-report.sh  

   • Analyze logs from the last 12 hours  
     ./ssh-attack-report.sh 12h  

   • Analyze logs from the last 3 days  
     ./ssh-attack-report.sh 3d  

   • Analyze logs from the last 2 weeks  
     ./ssh-attack-report.sh 2w  

   • Analyze logs from the last 1 month  
     ./ssh-attack-report.sh 1m  

## 📊 Example Output
🔹 กำลังวิเคราะห์ log ย้อนหลัง 2h  
---------------------------------------  
1) จำนวน ssh login ล้มเหลว (Failed password): 564  
2) จำนวน Invalid user attempts: 548  
3) จำนวน Banner exchange (noise scans): 18  

4) Top 10 IP (ทุกประเภท):  
48 125.17.108.32  
47 111.238.174.6  
46 103.16.202.187  
...  

5) Top 10 Username (จาก Failed/Invalid):  
312 invalid  
249 root  
36 test  
33 admin  
24 postgres  
...  

6) ตัวอย่าง log ล่าสุด:  
2025-09-26T19:53:42+07:00 brk sshd[11713]: banner exchange: Connection from 3.130.96.91 port 38490: invalid format  
2025-09-26T19:54:56+07:00 brk sshd[11725]: banner exchange: Connection from 20.169.104.180 port 57770: invalid format  

## ⚠️ Notes
- This script only reports attacks; it does not block them.  
- For actual mitigation, combine with:  
  • Fail2Ban (auto ban IPs after repeated failures)  
  • UFW / iptables (restrict SSH port access)  
  • Public key authentication only (disable passwords)  

## 🛡️ Recommended Setup
- Run SSH on a custom non-standard port (e.g., 34567)  
- Disable password authentication:  
  PasswordAuthentication no  
  PubkeyAuthentication yes  
- Enable Fail2Ban to auto-block bots  

👨‍💻 Author: Atipat Lorwongam with AI  
📅 Updated: 2025-09-26  

