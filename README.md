# ubuntu
Linux Ubuntu Start Commands

```bash
sudo ufw allow ssh
```
and/or
```bash
sudo ufw default deny incoming
```
```bash
sudo ufw enable
```

```bash
sudo apt update
```
```bash
sudo apt upgrade
```
```bash
sudo apt install dnscrypt-proxy
```
```bash
sudo systemctl restart dnscrypt-proxy
```
```bash
sudo systemctl restart NetworkManager
```

Set nameserver 127.0.2.1 (in NetworkManager or in /etc/resolv.conf)
Add to your /etc/resolv.conf

```
nameserver 127.0.2.1
```


```bash
sudo apt install tor
```
```bash
sudo systemctl enable tor
```

Add to your tor/torrc to route ALL traffic through tor:

```
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 9040
DNSPort 53
```

This way you setup DNS server on your Ubuntu on port 53 and Transparent proxy: 127.0.0.1:9040 (if dnscrypt-proxy fails)

```bash
sudo apt install fail2ban
```

Optional security policy hardening 

(FOR GUI which already uses AppArmor):

```bash
sudo systemctl stop apparmor
```
```bash
sudo systemctl disable apparmor
```
```bash
sudo nano /etc/default/grub
```

GRUB_CMDLINE_LINUX="apparmor=0" (or with space after other params)

```bash
sudo update-grub
```
```bash
sudo apt install policycoreutils selinux-utils selinux-basics
```
```bash
sudo selinux-config-enforcing
```
or
```bash
sudo setenforce 0 
```
or 
```bash
enforcing=0
```
```bash
sudo selinux-activate
