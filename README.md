# Ubuntu

Linux Ubuntu start commands after fresh install. Offers a more secure starting point for any new super user.

## Firewall

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
go through updates setup & get Ubuntu Pro.

## DNSCRYPT

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
sudo apt enable dnscrypt-proxy
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
```bash
sudo systemctl restart tor
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
That completes the setup of a DNS server on port 53 (if dnscrypt-proxy fails) and Transparent proxy server: 127.0.0.1:9040

Turn proxy settings on (!)

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
