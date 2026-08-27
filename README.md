# Ubuntu
[![Platform](https://img.shields.io/badge/platform-Linux-lightgray.svg)](https://github.com/)
[![Build Status](https://github.com/neohiro/ubuntu/actions/workflows/release.yml/badge.svg)](https://github.com/neohiro/ubuntu/actions)

Linux Ubuntu commands after fresh install, automated in attached shell files (with extra hardening, please go through the shell). Offers a more secure starting point for any new super user.

```bash
sudo passwd root
```
```bash
sudo apt update && sudo apt upgrade -y
```
```bash
sudo apt-get update && sudo apt-get upgrade -y
```
```bash
sudo update-grub
```
```bash
sudo do-release-upgrade
```

## Firewall

```bash
sudo apt install ufw -y
```
(for servers)
```bash
sudo ufw allow ssh
```
and/or (for clients)
```bash
sudo ufw default deny incoming
```
```bash
sudo ufw enable
```
Check software download server addresses to all be https;
go through updates setup & install Ubuntu Pro.

## PRO
```bash
sudo apt install ubuntu-advantage-tools -y
```

Go to https://ubuntu.com/pro/dashboard, login with your account and use the cmd to attach.
```bash
sudo pro attach <key>
```
OR USE
```bash
sudo pro attach
```

```bash
sudo pro status
```
```bash
sudo pro enable <service>
```

## DNSCRYPT

```bash
sudo apt install dnscrypt-proxy -y
```
usually unnecessary:
```bash
sudo systemctl enable dnscrypt-proxy
```

Set nameserver 127.0.2.1 (in Network Manager and/or add to /etc/resolv.conf)
```
sudo nano /etc/resolv.conf
```
```
nameserver 127.0.2.1
```

```bash
sudo systemctl restart dnscrypt-proxy
```
```bash
sudo systemctl restart NetworkManager
```


## Tor

```bash
sudo apt install tor -y
```
```bash
sudo systemctl enable tor
```

Add to tor/torrc to route ALL possible traffic through tor:
```
sudo nano /etc/tor/torrc
```
```
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 9040
DNSPort 53
```
Restrict outbound traffic with iptables to **only** Tor (warning, some updates will not work):
```bash
sudo iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 9040
sudo iptables -t nat -A OUTPUT -p udp --dport 80 -j REDIRECT --to-ports 9040
sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 9040
sudo iptables -t nat -A OUTPUT -p udp --dport 443 -j REDIRECT --to-ports 9040
```
```
sudo apt-get install iptables-persistent
```
```
sudo netfilter-persistent save
```
That completes a DNS server on port 53 (for dnscrypt-proxy or dnsproxy) and Transparent proxy server: 127.0.0.1:9040

```bash
sudo systemctl restart tor
```
## System Logging

To limit system file growth on Linux & if your drive is already getting full, run this script: [DeepClean](https://github.com/neohiro/ubuntu/blob/main/DeepClean.sh)

## Fail2BAN

(only if you use remote ssh)
```bash
sudo apt install fail2ban -y
```
```bash
sudo systemctl enable fail2ban
```
```bash
sudo systemctl restart fail2ban
```

## Automatic Security Updates

Critical patches should never wait for you to remember them:
```bash
sudo apt install unattended-upgrades -y
```
```bash
sudo dpkg-reconfigure --priority=low unattended-upgrades
```
Choose **Yes** when asked.

## Firmware, Secure Boot & Disk Encryption

Update device firmware and confirm Secure Boot is active:
```bash
sudo fwupdmgr refresh && sudo fwupdmgr update
```
```bash
mokutil --sb-state
```
Full-disk encryption (**LUKS**) must be chosen at install time — on the next reinstall tick it; it protects all data when the machine is powered off or stolen. Verify clock sync while you are at it:
```bash
timedatectl status
```

## Kernel Hardening (sysctl)

Save as `/etc/sysctl.d/99-hardening.conf`:
```
# information disclosure
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
kernel.yama.ptrace_scope=1
kernel.kexec_load_disabled=1
kernel.sysrq=0
kernel.randomize_va_space=2
fs.suid_dumpable=0
fs.protected_symlinks=1
fs.protected_hardlinks=1
fs.protected_fifos=2
fs.protected_regular=2

# network stack
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.tcp_syncookies=1
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
```
Apply it:
```bash
sudo sysctl --system
```

## AppArmor (Mandatory Access Control)

```bash
sudo apt install apparmor apparmor-utils -y
```
```bash
sudo systemctl enable --now apparmor
```
Check profiles are loaded and switch individual ones to enforce mode:
```bash
sudo aa-status
```
```bash
sudo aa-enforce /etc/apparmor.d/<profile>
```

## SSH Hardening

(only if you use remote ssh) Prefer keys over passwords:
```bash
ssh-keygen -t ed25519
```
Then set in `/etc/ssh/sshd_config`:
```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowUsers <youruser>
```
Validate before you disconnect:
```bash
sudo sshd -t && sudo systemctl restart ssh
```

## Passwords, Lockouts & Sessions

Stronger password quality checks:
```bash
sudo apt install libpam-pwquality -y
```
In `/etc/security/pwquality.conf`:
```
minlen = 14
minclass = 3
maxrepeat = 3
```
Lock accounts after failed logins — in `/etc/security/faillock.conf`:
```
deny = 5
unlock_time = 900
```
Auto-close idle shells — `/etc/profile.d/99-tmout.sh`:
```bash
TMOUT=900; readonly TMOUT; export TMOUT
```
Tighten default umask (`UMASK 027` in `/etc/login.defs`) and forbid core dumps — add to `/etc/security/limits.conf`:
```
* hard core 0
```

## Reduce The Attack Surface

See what is listening and decide whether it should be:
```bash
ss -tulnp
```
Disable daemons a desktop rarely needs (skip this on servers using them):

Run this script to reduce surface attack and optimize linux: [OptimizeLinuxASR](https://github.com/neohiro/ubuntu/blob/main/OptimizeLinuxASR.sh)

Only allow listed users to schedule jobs:
```bash
sudo touch /etc/cron.allow && echo "$USER" | sudo tee /etc/cron.allow
```
Mask Ctrl+Alt+Del (physical reboot trigger):
```bash
sudo systemctl mask ctrl-alt-del.target
```

## Verify & Maintain

```bash
sudo ufw status verbose
```
Rootkit sweep:
```bash
sudo apt install rkhunter -y && sudo rkhunter --check
```
For file-integrity baselining consider AIDE (`sudo apt install aide && sudo aideinit`). Re-check `ss -tulnp` after installing new software — every listener is another door.

##
```bash
reboot
```

Check directory for other Linux Ubuntu terminal tutorials

⭐ Stargaze to help others secure their Ubuntu install

🔗 [frenzypenguin.media](https://linktr.ee/frenzypenguin.media)

---

<p align="center">
  <a href="https://github.com/sponsors/neohiro"><img src="https://img.shields.io/badge/Sponsor%20on%20GitHub-%E2%9D%A4-EA4AAA?logo=githubsponsors&style=for-the-badge" alt="GitHub Sponsors"></a>&nbsp;&nbsp;
  <a href="https://www.patreon.com/frenzypenguin_media"><img src="https://img.shields.io/badge/Patreon-frenzypenguin__media-F96854?logo=patreon&style=for-the-badge" alt="Support on Patreon"></a>
</p>
