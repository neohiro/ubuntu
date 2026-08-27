#!/bin/bash
#
# neohiro/ubuntu  -  general interactive setup & hardening script
# Automates the README tutorial with safety prompts.
# Run as root:   sudo bash ubuntuinstall.sh
#

REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/neohiro/ubuntu/main}"
TMP_DIR="$(mktemp -d)"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
ORIG_CWD="$(pwd)"
trap 'rm -rf "$TMP_DIR"' EXIT

ensure_tmux_if_ssh() {
  [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || return 0
  [ -z "${TMUX:-}" ] && [ -z "${STY:-}" ] || return 0
  if ! command -v tmux >/dev/null 2>&1; then
    if [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
      apt-get install -y tmux >/dev/null 2>&1 || sudo apt-get install -y tmux >/dev/null 2>&1 || true
    fi
  fi
  command -v tmux >/dev/null 2>&1 || { warn "tmux unavailable; SSH disconnect may kill the run."; return 0; }
  local RECONNECT="tmux attach -t ubuntu-setup  # or:  ssh user@host 'tmux attach -t ubuntu-setup'"
  bold "SSH session detected. Re-running inside tmux so a disconnect will not abort the script."
  printf "  \033[1;36mCOPY BEFORE ANY DISCONNECT:\033[0m %s\n" "$RECONNECT"
  exec tmux new-session -A -s ubuntu-setup -n setup \
    "REPO_RAW_BASE='$REPO_RAW_BASE' \
     bash -c 'trap \"tmux kill-session -t ubuntu-setup 2>/dev/null\" EXIT; \
              cd \"$ORIG_CWD\" && bash \"$SCRIPT_PATH\" \"\$@\"; rc=\$?; \
              if [ \$rc -eq 0 ]; then tmux kill-session -t ubuntu-setup 2>/dev/null; fi; exit \$rc' -- \"\$@\""
}

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[WARNING]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
info() { printf "  %s\n" "$*"; }

msg() { echo "=> $*"; }

run() {
  msg "$*"
  "$@"
  local rc=$?
  if [ $rc -ne 0 ]; then err "Command failed (exit $rc): $*"; fi
  return 0
}

prompt_yn() {
  local q="$1" def="${2:-N}"
  local hint="[y/N]"; [ "$def" = "y" ] || [ "$def" = "Y" ] && hint="[Y/n]"
  local a
  read -r -p "$q $hint " a
  a="${a:-$def}"
  case "$a" in [Yy]*) return 0;; *) return 1;; esac
}

prompt_choice() {
  local q="$1"; shift
  local opts=("$@")
  local i=1
  echo "$q"
  for o in "${opts[@]}"; do printf "  %d) %s\n" "$i" "$o"; i=$((i+1)); done
  local a
  read -r -p "Choose [1-${#opts[@]}] (default 1): " a
  a="${a:-1}"
  if ! [[ "$a" =~ ^[0-9]+$ ]] || [ "$a" -lt 1 ] || [ "$a" -gt ${#opts[@]} ]; then
    a=1
  fi
  REPLY_CHOICE=$((a-1))
}

run_remote_script() {
  local name="$1"
  local url="${REPO_RAW_BASE}/${name}"
  local dst="${TMP_DIR}/${name}"
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL "$url" -o "$dst"; then err "Failed to fetch $url"; return 1; fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -qO "$dst" "$url"; then err "Failed to fetch $url"; return 1; fi
  else
    err "Neither curl nor wget available; cannot fetch $name"; return 1
  fi
  chmod +x "$dst"
  bash "$dst"
}

ENV_TYPE=""
USE_REMOTE_SSH=""

detect_or_ask_env() {
  if dpkg -l ubuntu-desktop >/dev/null 2>&1 || dpkg -l kubuntu-desktop >/dev/null 2>&1 || dpkg -l xubuntu-desktop >/dev/null 2>&1; then
    ENV_TYPE="desktop"
  elif systemctl list-unit-files 2>/dev/null | grep -qE '^(ssh|sshd)\.service'; then
    ENV_TYPE="server"
  else
    ENV_TYPE=""
  fi

  if [ -n "$ENV_TYPE" ]; then
    info "Detected environment: $ENV_TYPE"
    if ! prompt_yn "Use this environment type?" "y"; then ENV_TYPE=""; fi
  fi
  if [ -z "$ENV_TYPE" ]; then
    prompt_choice "Which environment is this machine?" "Desktop" "Server (headless / VPS)"
    ENV_TYPE="desktop"; [ "$REPLY_CHOICE" -eq 1 ] && ENV_TYPE="server"
  fi

  prompt_choice "Do you use remote SSH to log in to this machine?" "No" "Yes"
  USE_REMOTE_SSH="no"; [ "$REPLY_CHOICE" -eq 1 ] && USE_REMOTE_SSH="yes"
}

ask_profile() {
  prompt_choice "Apply which set of categories?" \
    "Recommended (safe, no SSH-lockout risk)" \
    "Standard (includes SSH hardening, Fail2ban, sysctl, AppArmor)" \
    "Full (includes Tor, IPv6 disable, attack-surface reduction, deep clean)" \
    "Custom (I will be asked per category)"
  REPLY_PROFILE=$REPLY_CHOICE
}

ask_category_enabled() {
  local key="$1" desc="$2" default="$3"
  case "$REPLY_PROFILE" in
    0) [ "$default" = "y" ]; return $?;;
    1) [ "$default" = "y" ] || [ "$key" = "ssh" ] || [ "$key" = "fail2ban" ] || [ "$key" = "sysctl" ] || [ "$key" = "pam" ]; return $?;;
    2) return 0;;
    3) prompt_yn "Run: $desc?" "$default"; return $?;;
  esac
}

update_system() {
  msg "Updating system and installing base packages..."
  run sudo DEBIAN_FRONTEND=noninteractive apt-get update
  run sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      apt-transport-https software-properties-common \
      wget curl gnupg lsb-release ca-certificates
}

setup_dnscrypt() {
  msg "DNSCrypt (ambiguous: DNS routing method is environment-dependent)"
  prompt_choice "How do you want to point DNS at 127.0.2.1?" \
    "Install dnscrypt-proxy, leave DNS config to me (manual)" \
    "Install dnscrypt-proxy + configure via netplan (server)" \
    "Install dnscrypt-proxy + configure via NetworkManager (desktop)" \
    "Skip - do not install dnscrypt-proxy"
  case "$REPLY_CHOICE" in
    3) info "Skipping dnscrypt-proxy."; return 0;;
  esac
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnscrypt-proxy
  run sudo sed -i "s|# listen_addresses = \[\]|listen_addresses = ['127.0.2.1:53']|" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
  run sudo systemctl restart dnscrypt-proxy
  run sudo systemctl enable dnscrypt-proxy
  case "$REPLY_CHOICE" in
    1) # netplan
      local NP
      NP=$(command -v netplan 2>/dev/null || echo "/usr/sbin/netplan")
      if ! [ -x "$NP" ]; then
        err "netplan not found on this system."
        info "Detected renderer via: networkctl status -a | grep -i network"
        info "To set DNS manually, add 'nameservers [127.0.0.1]' to your /etc/netplan/*.yaml"
        info "or use: sudo nmcli con mod <profile> ipv4.dns '127.0.0.1' && sudo nmcli con up <profile>"
        return 0
      fi
      local iface
      iface=$(ls /etc/netplan/ 2>/dev/null | grep -E '\.ya?ml$' | head -n1)
      if [ -z "$iface" ]; then err "No netplan YAML found in /etc/netplan/."; return 0; fi
      warn "About to edit /etc/netplan/$iface. A timestamped backup will be created."
      run sudo cp "/etc/netplan/$iface" "/etc/netplan/$iface.bak.$(date +%s)"
      run sudo tee "/etc/netplan/99-dnscrypt.yaml" >/dev/null <<'YAML'
network:
  version: 2
  renderer: networkd
  nameservers:
    addresses: [127.0.0.1, 1.1.1.1]
YAML
      warn "If your system uses NetworkManager as the renderer, set 'renderer: NetworkManager' instead."
      if ! "$NP" apply 2>&1; then
        err "'netplan apply' failed. Check /etc/netplan/99-dnscrypt.yaml for YAML errors."
        return 0
      fi
      ;;
    2) # NetworkManager
      warn "NetworkManager will be set to use 127.0.2.1 for DNS on active connections."
      run sudo nmcli -t -f NAME c show --active | while read -r c; do
        [ -z "$c" ] && continue
        run sudo nmcli con mod "$c" ipv4.dns "127.0.2.1"
        run sudo nmcli con up "$c"
      done
      ;;
  esac
  ok "dnscrypt-proxy installed. Test: dig +short myip.opendns.com @127.0.2.1"
}

setup_firewall() {
  msg "Firewall (UFW)"
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
  run sudo ufw default deny incoming
  run sudo ufw default allow outgoing
  if [ "$USE_REMOTE_SSH" = "yes" ] || [ "$ENV_TYPE" = "server" ]; then
    warn "Allowing SSH (22) - required for remote access."
    run sudo ufw allow ssh
  else
    info "Not opening SSH (no remote SSH usage reported)."
  fi
  run sudo ufw --force enable
  run sudo ufw status verbose
}

setup_tor() {
  msg "Tor daemon (user-case dependent)"
  if ! prompt_yn "Install the Tor daemon? (For Tor Browser, get it from torproject.org)" "n"; then
    info "Skipping Tor."; return 0
  fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tor
  warn "Tor is installed but /etc/tor/torrc is left untouched. Edit it for relay/transparent-proxy use."
  ok "Tor daemon installed."
}

disable_ipv6() {
  msg "IPv6 disable (ambiguous - can break some networks/services)"
  if ! prompt_yn "Really disable IPv6? (This is risky on modern networks)" "n"; then
    info "Keeping IPv6 enabled."; return 0
  fi
  if ! prompt_yn "Type 'yes' to confirm you understand network breakage" "no"; then
    info "Aborted IPv6 disable."; return 0
  fi
  run sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  run sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
  run sudo sed -i '$a\net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1' /etc/sysctl.conf
  warn "Reboot may be required for full effect."
}

harden_ssh() {
  if [ "$USE_REMOTE_SSH" != "yes" ]; then
    info "Skipping SSH hardening (you said you don't use remote SSH)."
    return 0
  fi
  msg "SSH hardening (LOCKOUT-PRONE - each step will be confirmed)"
  if ! command -v sshd >/dev/null 2>&1; then
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
    if ! command -v sshd >/dev/null 2>&1; then
      err "openssh-server install failed; cannot proceed with SSH hardening."; return 1
    fi
  fi

  local SSHCFG="/etc/ssh/sshd_config"
  local BACKUP="${SSHCFG}.bak.$(date +%s)"
  run sudo cp "$SSHCFG" "$BACKUP"

  if prompt_yn "Set PermitRootLogin no?" "y"; then
    run sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHCFG"
  fi

  if prompt_yn "Reduce LoginGraceTime to 30s and MaxAuthTries to 3?" "y"; then
    run sudo sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 30s/' "$SSHCFG"
    run sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHCFG"
    run sudo sed -i 's/^#\?MaxSessions.*/MaxSessions 2/' "$SSHCFG"
  fi

  if prompt_yn "Change SSH port from 22 to 2222? (can lock you out if firewall not updated)" "n"; then
    run sudo sed -i 's/^#\?Port 22$/Port 2222/' "$SSHCFG"
    run sudo ufw allow 2222/tcp
  fi

  if prompt_yn "Disable password authentication (PubKey only)? THIS CAN LOCK YOU OUT" "n"; then
    local keyfile="/root/.ssh/authorized_keys"
    [ -s "$keyfile" ] || keyfile="$HOME/.ssh/authorized_keys"
    if [ ! -s "$keyfile" ]; then
      err "No authorized_keys found at $keyfile or /root/.ssh/authorized_keys."
      if ! prompt_yn "I have added a public key - proceed anyway? (type yes)" "no"; then
        warn "Skipping PasswordAuthentication change to avoid lockout."
      else
        run sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHCFG"
      fi
    else
      ok "Pubkey found - disabling password auth."
      run sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHCFG"
    fi
  fi

  if ! sudo sshd -t -f "$SSHCFG"; then
    err "sshd config is INVALID - reverting backup and NOT restarting."
    run sudo cp -f "$BACKUP" "$SSHCFG"
    return 1
  fi
  run sudo systemctl restart ssh
  ok "SSH hardened and restarted."
}

setup_fail2ban() {
  if [ "$USE_REMOTE_SSH" != "yes" ] && [ "$ENV_TYPE" != "server" ]; then
    info "Skipping Fail2ban (no remote SSH and not a server)."; return 0
  fi
  msg "Fail2ban"
  if ! prompt_yn "Install & enable Fail2ban with the sshd jail?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
  if [ ! -f /etc/fail2ban/jail.local ]; then
    run sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
  fi
  if ! grep -qE '^\[sshd\]' /etc/fail2ban/jail.local; then
    run sudo tee -a /etc/fail2ban/jail.local >/dev/null <<'JAIL'

[sshd]
enabled = true
JAIL
  else
    run sudo sed -i '/^\[sshd\]/,/^\[/ { /^\[sshd\]/b; /^\[/b; s/^enabled[[:space:]]*=.*/enabled = true/; }' /etc/fail2ban/jail.local
  fi
  run sudo systemctl enable --now fail2ban
}

configure_unattended_upgrades() {
  msg "Unattended security upgrades"
  if ! prompt_yn "Enable automatic security updates?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
  run sudo sed -i 's|//\s*Unattended-Upgrade::Allowed-Origins|Unattended-Upgrade::Allowed-Origins|' /etc/apt/apt.conf.d/50unattended-upgrades || true
  run sudo sed -i 's|Unattended-Upgrade::Automatic-Reboot "false"|Unattended-Upgrade::Automatic-Reboot "true"|' /etc/apt/apt.conf.d/50unattended-upgrades || true
  ok "Unattended upgrades enabled."
}

harden_sysctl() {
  msg "Kernel/network hardening via sysctl"
  if ! prompt_yn "Apply the 99-hardening.conf sysctl profile from the README?" "y"; then return 0; fi
  local f="/etc/sysctl.d/99-hardening.conf"
  run sudo tee "$f" >/dev/null <<'EOF'
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
kernel.yama.ptrace_scope=1
kernel.kexec_load_disabled=1
kernel.sysrq=0
kernel.randomize_va_space=2
fs.suid_dumpable=0
fs.protected_symlinks=1
fs.protected_hardlinks=1
fs.protected_fifos=2
fs.protected_regular=2
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.tcp_syncookies=1
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
EOF
  run sudo sysctl --system
}

setup_apparmor() {
  msg "AppArmor (MAC)"
  if ! prompt_yn "Install & enable AppArmor?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils
  run sudo systemctl enable --now apparmor
  run sudo aa-status || true
}

harden_passwords() {
  msg "Password & lockout policy"
  if ! prompt_yn "Install libpam-pwquality and set minlen=14?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libpam-pwquality
  declare -A pwq_vals=( [minlen]=14 [minclass]=3 [maxrepeat]=3 )
  for kw in "${!pwq_vals[@]}"; do
    grep -q "^$kw[[:space:]]*=" /etc/security/pwquality.conf 2>/dev/null || \
      echo "$kw = ${pwq_vals[$kw]}" | sudo tee -a /etc/security/pwquality.conf >/dev/null
  done
  run sudo tee /etc/security/faillock.conf >/dev/null <<'EOF'
deny = 5
unlock_time = 900
EOF
  run sudo tee /etc/profile.d/99-tmout.sh >/dev/null <<'EOF'
TMOUT=900; readonly TMOUT; export TMOUT
EOF
  run sudo chmod 644 /etc/profile.d/99-tmout.sh
  ok "Password/lockout policy set. Note: 'core 0' in /etc/security/limits.conf is recommended."
}

run_optimize_asr() {
  msg "Attack-surface reduction (OptimizeLinuxASR.sh from the repo)"
  if ! prompt_yn "Run the interactive OptimizeLinuxASR script (service-by-service prompts)?" "n"; then return 0; fi
  run_remote_script "OptimizeLinuxASR.sh"
}

run_deepclean() {
  msg "Deep clean (DeepClean.sh from the repo)"
  if ! prompt_yn "Run the DeepClean cleanup + auto-prune config now?" "n"; then return 0; fi
  run_remote_script "DeepClean.sh"
}

ask_other_scripts() {
  msg "Other helpers in the repo (optional)"
  if prompt_yn "Run ubuntusocks.sh (Shadowsocks-libev install)?" "n"; then
    run_remote_script "ubuntusocks.sh"
  fi
  if [ "$ENV_TYPE" = "server" ] && prompt_yn "Also run ubuntuinstallserver.sh (server-specific extras)?" "n"; then
    run_remote_script "ubuntuinstallserver.sh"
  fi
}

main() {
  bold "neohiro/ubuntu - general setup & hardening (interactive)"
  if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (use sudo)."; exit 1
  fi
  ensure_tmux_if_ssh

  detect_or_ask_env
  ask_profile

  ask_category_enabled "system"      "System update + base packages" "y" && update_system
  ask_category_enabled "dns"         "DNSCrypt (DNS method is ambiguous - you'll be asked)" "n" && setup_dnscrypt
  ask_category_enabled "firewall"    "Firewall (UFW)" "y" && setup_firewall
  ask_category_enabled "tor"         "Tor daemon" "n" && setup_tor
  ask_category_enabled "ssh"         "SSH hardening (LOCKOUT PRONE)" "n" && harden_ssh
  ask_category_enabled "fail2ban"    "Fail2ban" "n" && setup_fail2ban
  ask_category_enabled "unattended"  "Unattended security upgrades" "y" && configure_unattended_upgrades
  ask_category_enabled "ipv6"        "Disable IPv6 (risky)" "n" && disable_ipv6
  ask_category_enabled "sysctl"      "Kernel/sysctl hardening profile" "n" && harden_sysctl
  ask_category_enabled "apparmor"    "AppArmor" "n" && setup_apparmor
  ask_category_enabled "pam"         "Password & lockout policy" "n" && harden_passwords
  ask_category_enabled "optimize"    "Run OptimizeLinuxASR.sh (new helper)" "n" && run_optimize_asr
  ask_category_enabled "deepclean"   "Run DeepClean.sh (new helper)" "n" && run_deepclean

  ask_other_scripts

  bold "Done."
  info "Review changes. Reboot when ready: sudo reboot"
  if [ "$USE_REMOTE_SSH" = "yes" ]; then
    info "Because SSH was changed, verify a SECOND session can log in BEFORE closing this one."
  fi
}

main "$@"
