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
