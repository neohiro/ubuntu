# ShadowSocks

```bash
sudo apt update && sudo apt upgrade
```
```bash
sudo apt install python3 python3-pip -y
```
```bash
sudo pip3 install shadowsocks
```
```bash
sudo mkdir -p /etc/shadowsocks
```
```bash
sudo nano /etc/shadowsocks/config.json
```
```json
{
"server": "0.0.0.0",
"server_port": 8888,
"password": "PASSWORD",
"method": "aes-256-gcm",
"timeout": 300
#"plugin": "obfs-server",
#"plugin_opts": "obfs=http"
}
```
```bash
sudo nano /etc/systemd/system/shadowsocks.service
```
```bash
[Unit]
Description=Shadowsocks Proxy Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl enable shadowsocks
```
```bash
sudo systemctl start shadowsocks
```
Check the status of shadowsocks:
```bash
sudo systemctl status shadowsocks
```
```bash
sudo ufw allow 8888
```
Set up Shadowsocks client and optionally set up obfuscation (remove 2x '#' in json above):
```bash
sudo apt install simple-obfs
```
