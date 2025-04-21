#!/bin/bash
#
# Script to install Shadowsocks-libev on Ubuntu
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
    exit 1
  fi
}

# Function to install Shadowsocks-libev
install_shadowsocks() {
  msg "Installing Shadowsocks-libev..."

  # Update the system
  run sudo apt-get update
  run sudo apt-get upgrade -y

  # Install Shadowsocks-libev
  run sudo apt-get install -y shadowsocks-libev

  msg "Shadowsocks-libev installed."
}

# Function to configure Shadowsocks-libev
configure_shadowsocks() {
  msg "Configuring Shadowsocks-libev..."

  # Create the configuration file directory
  run sudo mkdir -p /etc/shadowsocks-libev

  # Generate a random password
  PASSWORD=$(openssl rand -base64 16)
  echo "Generated password: $PASSWORD"

  # Create the configuration file
  cat <<EOF | sudo tee /etc/shadowsocks-libev/config.json
{
    "server":"0.0.0.0",
    "server_port":8388,
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"$PASSWORD",
    "timeout":300,
    "method":"aes-256-gcm",
    "fast_open":true
}
EOF

  msg "Shadowsocks-libev configuration file created at /etc/shadowsocks-libev/config.json"
  msg "  Please ensure the settings are correct, especially the password and encryption method."

  # Enable and start the service
  run sudo systemctl enable shadowsocks-libev
  run sudo systemctl start shadowsocks-libev

  msg "Shadowsocks-libev service enabled and started."
}

# --- Main Script ---

msg "Starting Shadowsocks-libev installation and configuration..."

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script must be run as root."
  exit 1
fi

install_shadowsocks
configure_shadowsocks

msg "Shadowsocks-libev installation and configuration complete."
msg "  [IMPORTANT]  Review the configuration in /etc/shadowsocks-libev/config.json."
msg "  [IMPORTANT]  Ensure your firewall allows traffic on port 8388 (or the port you configured)."
msg "  [IMPORTANT]  You may need to configure your client (e.g., on your PC or phone) to connect to this server."
