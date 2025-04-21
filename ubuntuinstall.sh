#!/bin/bash
#
# Script to automate Ubuntu setup and hardening based on neohiro/ubuntu
#
# Intended to be run on a fresh Ubuntu installation.  Use with caution.
#
# Author: Bard
# Date: 2024-02-08
#
# Disclaimer: This script may modify system settings.  Review it carefully
#             before running and understand the commands.  Backup your system
#             if possible.  Run at your own risk.
#


# --- Functions ---

# Function to display a message
msg() {
  echo "=> $1"
}

# Function to execute a command and check for errors
run() {
  msg "$1"
  "$@"
  if [ "$?" -ne "0" ]; then
    echo "  [ERROR] Command failed: $*"
  fi
}

# Function to update system and install packages
update_system() {
  msg "Updating system and installing packages..."
  run sudo apt-get update
  run sudo apt-get upgrade -y
  run sudo apt-get install -y \
      apt-transport-https \
      software-properties-common \
      wget \
      curl \
      gnupg \
      lsb-release
}

# Function to setup DNSCrypt
setup_dnscrypt() {
  msg "Setting up DNSCrypt..."
  # Add the DNSCrypt PPA.  This PPA is outdated.  The official way
  # is now via their own debian repo.
  #run sudo add-apt-repository ppa:shevchuk/dnscrypt- стабильный ppa: তালিকман/dnscrypt
  #run sudo apt-get update

  # Install dnscrypt-proxy.
  run sudo apt-get install -y dnscrypt-proxy

  # Configure DNSCrypt (this part needs review, as the original script
  #  has some potential issues and non-standard practices).
  #  The original script had a large block of commented-out configurations.
  #  I'm simplifying to a basic configuration.  The user should
  #  review /etc/dnscrypt-proxy/dnscrypt-proxy.toml and configure
  #  it to their needs.
  run sudo sed -i 's/# listen_addresses = \[\]/listen_addresses = \['\''127.0.2.1:53'\''\]/' /etc/dnscrypt-proxy/dnscrypt-proxy.toml
  run sudo systemctl restart dnscrypt-proxy
  run sudo systemctl enable dnscrypt-proxy

  # IMPORTANT:  The original script contained instructions to edit
  # /etc/resolv.conf.  This is NOT the recommended way to configure DNS
  # on modern Ubuntu systems.  The recommended way is to use netplan.
  #  I am NOT including any changes to resolv.conf in this script.
  #  The user MUST configure their DNS settings correctly, likely
  #  by editing a netplan configuration file.  A common approach is:
  #
  #  1. Edit the appropriate netplan YAML file in /etc/netplan/
  #  2.  Set  nameservers: addresses: [127.0.0.1]
  #  3.  Run sudo netplan apply
  #
  #  See https://ubuntu.com/server/docs/network-configuration for
  #  details on how to configure netplan.
  #
  msg "IMPORTANT:  You MUST configure your system to use 127.0.2.1 as the DNS server."
  msg "  This is typically done by editing a netplan configuration file in /etc/netplan/."
  msg "  See https://ubuntu.com/server/docs/network-configuration for details."


  # Test DNSCrypt.  This is kept as a check.
  run dig +short myip.opendns.com @127.0.2.1
}

# Function to harden SSH
harden_ssh() {
    msg "Hardening SSH..."
    # Disable root login
    run sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    # Change default SSH port
    # Read the current port, and if it is 22, change it.
    CURRENT_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $1}')
    if [ "$CURRENT_PORT" = "Port" ]; then
       run sudo sed -i 's/^Port 22/Port 2222/' /etc/ssh/sshd_config
       msg "SSH Port changed to 2222.  Change it to a random port."
    else
       msg "SSH Port is not 22, not changing it."
    fi
        # Additional hardening options
    run sudo sed -i 's/^#LoginGraceTime 2m/LoginGraceTime 30s/' /etc/ssh/sshd_config
    run sudo sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
    run sudo sed -i 's/^#MaxSessions 10/MaxSessions 2/' /etc/ssh/sshd_config
    run sudo systemctl restart sshd
}

# Function to setup firewall (UFW)
setup_firewall() {
  msg "Setting up firewall (UFW)..."
  run sudo ufw default deny incoming
  run sudo ufw default allow outgoing
  run sudo ufw allow ssh
  run sudo ufw enable
  run sudo ufw status
}

# Function to install and configure Tor
setup_tor() {
  msg "Setting up Tor..."
  #  Tor Browser is the recommended way to use Tor on desktop.
  #  This script installs the Tor daemon, which is useful for
  #  setting up a Tor relay, or for routing specific applications
  #  through Tor.  Most users will want Tor Browser.
  run sudo apt-get install -y tor

  # The original script had commented-out Tor configuration.  If the user
  # wants to *run a Tor relay*, they will need to edit /etc/tor/torrc.
  # That is beyond the scope of a simple setup script.

  msg "Tor daemon installed, please edit /etc/tor/torrc.  If you want to browse with Tor, download Tor Browser."
  msg "  https://www.torproject.org/download/"
}

# Function to disable IPv6
disable_ipv6() {
  msg "Disabling IPv6..."
  # This is a common way to disable IPv6, but it can have unintended
  # consequences.  Modern Ubuntu systems often rely on IPv6.  The user
  # should understand the implications before doing this.
  run sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  run sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
  run sudo sed -i '$a\net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1' /etc/sysctl.conf
  msg "IPv6 disabled.  Reboot may be required for full effect."
}

# Function to set secure permissions
set_secure_permissions() {
  msg "Setting secure permissions..."
  run sudo chmod 750 /root
  run sudo chmod 700 /etc/passwd
  run sudo chmod 644 /etc/shadow
  run sudo chown root:root /etc/passwd
  run sudo chown root:root /etc/shadow
}

# Function to install and configure unattended upgrades
configure_unattended_upgrades() {
    msg "Configuring unattended upgrades..."
    run sudo apt-get install -y unattended-upgrades
    run sudo dpkg-reconfigure --priority=low unattended-upgrades
    # Enable automatic updates
    run sudo sed -i 's/^\/\/Unattended-Upgrade::Allowed-Origins/Unattended-Upgrade::Allowed-Origins/' /etc/apt/apt.conf.d/50unattended-upgrades
    run sudo sed -i 's/^Unattended-Upgrade::Automatic-Update \"0\";/Unattended-Upgrade::Automatic-Update \"1\";/' /etc/apt/apt.conf.d/20auto-upgrades
    msg "Unattended upgrades configured to automatically install security updates."
}
# --- Main Script ---

msg "Starting Ubuntu setup and hardening..."

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script must be run as root."
  exit 1
fi

update_system
setup_dnscrypt
setup_firewall
setup_tor
harden_ssh
set_secure_permissions
configure_unattended_upgrades
disable_ipv6 #  <--  WARNING:  This can break things.

msg "Setup and hardening complete."
msg "  [IMPORTANT]  Review all changes and reboot your system."
msg "  [IMPORTANT]  Configure DNS settings (NetworkManager, netplan or resolv.conf) as described above."

