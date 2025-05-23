# Ubuntu

Linux Ubuntu commands after fresh install, automated in attached shell files (with extra hardening, please go through the shell). Offers a more secure starting point for any new super user.

```bash
sudo passwd root
```
```bash
sudo apt update && sudo apt upgrade
```
```bash
sudo apt-get update && sudo apt-get upgrade
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
That completes a DNS server on port 53 (for dnscrypt-proxy or dnsproxy) and Transparent proxy server: 127.0.0.1:9040

```bash
sudo systemctl restart tor
```

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
##
```bash
reboot
```

Check directory for other Linux Ubuntu terminal tutorials
⭐ Stargaze to help others secure their Ubuntu install
 
  
http://frenzypenguin.media
