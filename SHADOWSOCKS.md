# ShadowSocks

```bash
sudo apt update && sudo apt upgrade
```
```bash
sudo apt install python && sudo apt install pip
```
```bash
sudo pip install shadowsocks
```
```bash
sudo nano /etc/config.json
```
```json
{
"server": "0.0.0.0",
"server_port": 1080,
"password": "your_password_here",
"method": "aes-256-cfb",
"timeout": 300
"plugin": "obfs-server",
"plugin_opts": "obfs=http"
}
```
```bash
sudo sslocal -c /etc/config.json
```
```bash
sudo ufw allow 1080
```
Set up your Shadowsocks client and set up obfuscation:

```bash
sudo apt install simple-obfs
```
```bash
sudo systemctl enable shadowsocks-libev
```
