# ShadowSocks

```bash
sudo apt update && sudo apt upgrade
```
```bash
sudo apt install shadowsocks-libev
```
```bash
sudo nano /etc/shadowsocks-libev/config.json
```
```json
{
    "server":["::0", "0.0.0.0"],
    "mode":"tcp_and_udp",
    "server_port":8888,
    "local_port":1080,
    "password":"PWRD<<<<<<<<<<<<<",
    "timeout":300,
    "method":"xchacha20-ietf-poly1305"
    #"plugin": "obfs-server",
    #"plugin_opts": "obfs=http"
}
```
```bash
sudo systemctl restart shadowsocks-libev.service
```
```bash
systemctl status shadowsocks-libev.service
```

```bash
sudo iptables -I INPUT -p tcp --dport 8888 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 8888 -j ACCEPT
```
```bash
sudo ufw allow 8888
```
Set up Shadowsocks client and optionally set up obfuscation (remove 2x '#' in json above):
```bash
sudo apt install simple-obfs
```

Or a docker install via [https://github.com/teddysun/shadowsocks_install/blob/master/docker/shadowsocks-libev/README.md]
