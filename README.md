# Linux Ubuntu
Commands after installation:

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
