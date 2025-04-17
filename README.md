# Ubuntu

Linux Ubuntu commands after fresh install. Offers a more secure starting point for any new super user.


```bash
sudo apt update && sudo apt upgrade
```
```bash
sudo update-grub
```
```bash
sudo do-release-upgrade
```

## Firewall

```bash
sudo apt install ufw
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

Go to https://ubuntu.com/pro/dashboard, login with your account and use the cmd to attach.
```bash
sudo apt install ubuntu-advantage-tools
```
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
sudo apt install dnscrypt-proxy
```
usually unnecessary:
```bash
sudo systemctl enable dnscrypt-proxy
```
```bash
sudo systemctl restart dnscrypt-proxy
```
```bash
sudo systemctl restart NetworkManager
```


Set nameserver 127.0.2.1 (in Network Manager and/or add to /etc/resolv.conf)
```
sudo nano /etc/resolv.conf
```
```
nameserver 127.0.2.1
```

## Tor

```bash
sudo apt install tor
```
```bash
sudo systemctl enable tor
```

Add to tor/torrc to route ALL traffic through tor:
```
sudo nano /etc/tor/torrc
```
```
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 9040
DNSPort 53
```
That completes a DNS server on port 53 (if dnscrypt-proxy fails) and Transparent proxy server: 127.0.0.1:9040

```bash
sudo systemctl restart tor
```
Turn proxy settings on.

## Fail2BAN

(only if you use remote ssh)
```bash
sudo apt install fail2ban
```
```bash
sudo systemctl enable fail2ban
```
```bash
sudo systemctl restart fail2ban
```

Check directory for other Linux Ubuntu terminal tutorials
⭐ Stargaze to help others secure their Ubuntu install
 
  
http://frenzypenguin.media
