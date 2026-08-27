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

RECOVERY_CMD="tmux attach -t ubuntu-setup   # reconnect after SSH disconnect"
ROLLBACK_LOG="/var/log/ubuntu-install-rollback.log"

# Append a backup-file line to a single rollback log so the user has one place
# to find every file we modified and the backup we made before modifying it.
record_backup() {
  local original="$1" backup="$2"
  [ -n "$original" ] && [ -n "$backup" ] || return 0
  local line
  line="$(printf '%s\t%s\n' "$original" "$backup")"
  # As root without sudo: write directly. Otherwise: sudo tee so the log
  # remains root-owned in /var/log.
  if [ "$EUID" -eq 0 ] && ! command -v sudo >/dev/null 2>&1; then
    printf '%s' "$line" >> "$ROLLBACK_LOG" 2>/dev/null || true
  else
    printf '%s' "$line" | sudo tee -a "$ROLLBACK_LOG" >/dev/null 2>&1 || true
  fi
  metrics_add configs_backed_up 1
  metrics_add rollback_logged 1
}

print_recovery_cmd() {
  printf "\033[1;33m──────────────────────────────────────────────────────────────────────\033[0m\n"
  printf "\033[1;33m│  RECOVERY COMMAND — copy this BEFORE anything that might disconnect:  \033[0m\n"
  printf "\033[1;33m│\033[0m                                                                      \033[1;36m%s\033[0m\n" "$RECOVERY_CMD"
  printf "\033[1;33m──────────────────────────────────────────────────────────────────────\033[0m\n"
  printf "  After reconnecting over SSH, run the command above to resume the run.\n\n"
}

_warn_if_not_tmux() {
  [ -n "${TMUX:-}" ] || [ -n "${STY:-}" ] && return 0
  print_recovery_cmd
}

print_recovery_if_ssh() {
  [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || return 0
  print_recovery_cmd
}

ensure_tmux_if_ssh() {
  [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || return 0
  [ -z "${TMUX:-}" ] && [ -z "${STY:-}" ] || return 0
  if ! command -v tmux >/dev/null 2>&1; then
    if [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1 || \
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1 || true
    fi
  fi
  command -v tmux >/dev/null 2>&1 || {
    warn "tmux unavailable; SSH disconnect may kill the run. ${RECOVERY_CMD} will NOT exist - run the script from a local terminal instead."
    return 0
  }
  [ -n "$SCRIPT_PATH" ] || { warn "SCRIPT_PATH is empty; cannot re-exec inside tmux."; return 0; }
  bold "SSH session detected. Wrapping this run in a tmux session so disconnects do not abort it."
  # Quote everything via env+args (no string interpolation) so paths with spaces
  # or shell metacharacters survive. The inner bash re-execs the same script
  # by absolute path; on clean exit it tears the tmux session down.
  local inner
  inner=$(cat <<'INNER_EOF'
trap 'tmux kill-session -t ubuntu-setup 2>/dev/null' EXIT
cd "$1" && shift
bash "$1" "$@"
rc=$?
if [ "$rc" -eq 0 ]; then
  tmux kill-session -t ubuntu-setup 2>/dev/null
fi
exit "$rc"
INNER_EOF
)
  exec env REPO_RAW_BASE="$REPO_RAW_BASE" \
       tmux new-session -A -s ubuntu-setup -n setup \
         "env REPO_RAW_BASE='$REPO_RAW_BASE' bash -c $(printf '%q' "$inner") -- $(printf '%q' "$ORIG_CWD") $(printf '%q' "$SCRIPT_PATH")"
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
  if [ -t 0 ]; then
    read -r -p "$q $hint " a
  elif [ -e /dev/tty ] && [ -r /dev/tty ]; then
    printf '%s %s ' "$q" "$hint" >/dev/tty
    read -r a </dev/tty
  else
    # No interactive terminal available - use the default and warn.
    warn "stdin is not a TTY and /dev/tty is unavailable; defaulting to '$def' for: $q"
    a="$def"
  fi
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
  if [ -t 0 ]; then
    read -r -p "Choose [1-${#opts[@]}] (default 1): " a
  elif [ -e /dev/tty ] && [ -r /dev/tty ]; then
    printf 'Choose [1-%d] (default 1): ' "${#opts[@]}" >/dev/tty
    read -r a </dev/tty
  else
    warn "stdin is not a TTY and /dev/tty is unavailable; defaulting to 1 for: $q"
    a=1
  fi
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

# --- metrics & run summary (shown at the end with a bar chart) ---
declare -A METRICS=(
  [pkgs_upgraded]=0
  [pkgs_installed]=0
  [services_stopped]=0
  [services_hardened]=0
  [sysctls_applied]=0
  [fw_rules_added]=0
  [configs_backed_up]=0
  [tor_services_enabled]=0
  [auth_keys_added]=0
  [rollback_logged]=0
)
METRICS_START_DISK_KB=$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)

metrics_add() {
  local key="$1" delta="${2:-1}"
  METRICS[$key]=$(( ${METRICS[$key]:-0} + delta ))
}

_metrics_bar() {
  local label="$1" value="$2" max="$3" width="${4:-40}"
  [ "$max" -eq 0 ] 2>/dev/null && max=1
  [ "$value" -gt "$max" ] 2>/dev/null && value="$max"
  local filled=$(( value * width / max ))
  local empty=$(( width - filled ))
  local bar empty_str
  bar="$(printf '%*s' "$filled" '' | tr ' ' '█')"
  empty_str="$(printf '%*s' "$empty" '' | tr ' ' '░')"
  printf '  %-28s \033[1;32m%s\033[0m\033[1;30m%s\033[0m  %d\n' "$label" "$bar" "$empty_str" "$value"
}

print_metrics_summary() {
  local end_disk_kb
  end_disk_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
  local disk_delta=$(( end_disk_kb - METRICS_START_DISK_KB ))
  local disk_freed_str
  if [ "$disk_delta" -gt 0 ]; then
    disk_freed_str="$(numfmt --to=iec-i --suffix=B "$(( disk_delta * 1024 ))" 2>/dev/null || echo "${disk_delta} KB freed")"
  else
    disk_freed_str="N/A (run as root to measure)"
  fi

  local max_val=1
  for v in "${METRICS[@]}"; do
    [ "$v" -gt "$max_val" ] 2>/dev/null && max_val="$v"
  done

  printf '\n\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '\033[1;36m  RUN SUMMARY  \033[0m'
  [ "$USE_REMOTE_SSH" = "yes" ] && printf ' \033[1;33m[SSH HARDENED]\033[0m'
  [ "$ENV_TYPE" = "server" ]  && printf ' \033[1;35m[SERVER MODE]\033[0m'
  printf '\n'
  printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '\n'
  printf '  \033[1;37mPACKAGES\033[0m\n'
  _metrics_bar "  Packages upgraded"   "${METRICS[pkgs_upgraded]}"   "$max_val"
  _metrics_bar "  Packages installed"  "${METRICS[pkgs_installed]}"  "$max_val"
  printf '\n'
  printf '  \033[1;37mSECURITY\033[0m\n'
  _metrics_bar "  Services hardened"  "${METRICS[services_hardened]}" "$max_val"
  _metrics_bar "  Services stopped"   "${METRICS[services_stopped]}"  "$max_val"
  _metrics_bar "  sysctls applied"     "${METRICS[sysctls_applied]}"  "$max_val"
  _metrics_bar "  Firewall rules added" "${METRICS[fw_rules_added]}" "$max_val"
  printf '\n'
  printf '  \033[1;37mSSH & AUTHENTICATION\033[0m\n'
  _metrics_bar "  Auth keys added"     "${METRICS[auth_keys_added]}"   "$max_val"
  printf '\n'
  printf '  \033[1;37mTOR\033[0m\n'
  _metrics_bar "  Tor services enabled" "${METRICS[tor_services_enabled]}" "$max_val"
  printf '\n'
  printf '  \033[1;37mBACKUPS & ROLLBACK\033[0m\n'
  _metrics_bar "  Config files backed up" "${METRICS[configs_backed_up]}" "$max_val"
  _metrics_bar "  Rollback entries logged" "${METRICS[rollback_logged]}" "$max_val"
  printf '\n'
  printf '  \033[1;37mSTORAGE\033[0m\n'
  printf '  %-28s %s\n' "  Disk freed (approximate)" "$disk_freed_str"
  printf '\n'
  if [ "${METRICS[configs_backed_up]}" -gt 0 ]; then
    printf '  \033[1;33m⚠ Rollback log:\033[0m %s\n' "$ROLLBACK_LOG"
    printf '  \033[1;30m  Format: original_path    backup_path\033[0m\n'
    printf '  \033[1;30m  To restore: sudo cp backup_path original_path\033[0m\n'
  fi
  printf '\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
}

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
  _warn_if_not_tmux
  local upgradable
  upgradable=$(apt list --upgradable 2>/dev/null | grep -c '/') || upgradable=0
  run sudo DEBIAN_FRONTEND=noninteractive apt-get update
  run sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  metrics_add pkgs_upgraded "$upgradable"
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      apt-transport-https software-properties-common \
      wget curl gnupg lsb-release ca-certificates
  metrics_add pkgs_installed 8
}

apply_dns_via_nmcli() {
  local DNS_PRIMARY="${1:-127.0.0.1}" DNS_FALLBACK="${2:-1.1.1.1}"
  _warn_if_not_tmux
  info "Setting DNS on active NetworkManager connections..."
  local conn
  local active_count=0
  while IFS= read -r conn; do
    [ -z "$conn" ] && continue
    active_count=$((active_count + 1))
    run sudo nmcli con mod "$conn" ipv4.dns "$DNS_PRIMARY $DNS_FALLBACK"
    run sudo nmcli con mod "$conn" ipv4.ignore-auto-dns yes
    run sudo nmcli con up "$conn"
  done < <(sudo nmcli -t -f NAME c show --active)
  if [ "$active_count" -eq 0 ]; then
    warn "No active NetworkManager connections found; DNS not changed."
    info "Activate a connection first, then re-run, or edit /etc/resolv.conf manually."
  fi
}

apply_dns_via_netplan() {
  local DNS_PRIMARY="${1:-127.0.0.1}" DNS_FALLBACK="${2:-1.1.1.1}"
  _warn_if_not_tmux
  info "Applying DNS via netplan..."
  local NP f
  NP="$(command -v netplan 2>/dev/null || true)"
  [ -n "$NP" ] || NP="/usr/sbin/netplan"
  [ -x "$NP" ] || { err "netplan not found."; return 0; }
  f=""
  for candidate in /etc/netplan/*.yaml /etc/netplan/*.yml; do
    if [ -f "$candidate" ]; then
      f="$candidate"
      break
    fi
  done
  [ -n "$f" ] || { err "No netplan YAML in /etc/netplan/."; return 0; }
  local bak
  bak="${f}.bak.$(date +%s)"
  run sudo cp "$f" "$bak"
  record_backup "$f" "$bak"
  run sudo tee /etc/netplan/99-dnscrypt.yaml >/dev/null <<EOF
network:
  version: 2
  nameservers:
    addresses: [$DNS_PRIMARY, $DNS_FALLBACK]
EOF
  warn "Applying netplan (60s timeout) - if SSH drops, recovery console + 'sudo netplan apply' restores."
  if ! timeout 60 "$NP" apply 2>&1; then
    err "netplan apply failed or timed out. Original config preserved at $bak."
    return 0
  fi
}

apply_dns_via_systemd_networkd() {
  local DNS_PRIMARY="${1:-127.0.0.1}" DNS_FALLBACK="${2:-1.1.1.1}"
  _warn_if_not_tmux
  # Restarting systemd-networkd on the active SSH interface can drop the
  # connection. Detect the interface this SSH session came in on and skip
  # the restart if it is the one we would touch.
  local active_if
  active_if="$(ip -o route show default 2>/dev/null | awk '{print $5}' | head -n1)"
  if [ -n "$active_if" ] && [ -f "/etc/systemd/network/10-$active_if.network" ] && systemctl is-active --quiet systemd-networkd; then
    warn "Active SSH interface ($active_if) is managed by systemd-networkd."
    if ! prompt_yn "Apply DNS via systemd-networkd and restart (may drop SSH - are you in tmux?)" "n"; then
      info "Skipped systemd-networkd DNS change. Write /etc/systemd/network/99-dnscrypt.network manually."
      return 0
    fi
  fi
  info "Applying DNS via systemd-networkd..."
  run sudo mkdir -p /etc/systemd/network
  local f="/etc/systemd/network/99-dnscrypt.network"
  local bak
  if [ -f "$f" ]; then
    bak="${f}.bak.$(date +%s)"
    run sudo cp "$f" "$bak"
    record_backup "$f" "$bak"
  fi
  run sudo tee "$f" >/dev/null <<EOF
[Match]
Name=*

[Network]
DNS=$DNS_PRIMARY
DNS=$DNS_FALLBACK
EOF
  run sudo systemctl restart systemd-networkd
}

_apply_dns_127_0_0_1() {
  local DNS_PRIMARY="127.0.0.1" DNS_FALLBACK="1.1.1.1"

  if [ -x /usr/sbin/netplan ]; then
    local np_yaml
    for np_yaml in /etc/netplan/*.yaml /etc/netplan/*.yml; do
      if [ -f "$np_yaml" ]; then
        apply_dns_via_netplan "$DNS_PRIMARY" "$DNS_FALLBACK"; return 0
      fi
    done
  fi

  if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager 2>/dev/null; then
    apply_dns_via_nmcli "$DNS_PRIMARY" "$DNS_FALLBACK"; return 0
  fi

  if command -v networkctl >/dev/null 2>&1; then
    apply_dns_via_systemd_networkd "$DNS_PRIMARY" "$DNS_FALLBACK"; return 0
  fi

  err "No supported DNS renderer found."
  info "Manual fallback: echo 'nameserver $DNS_PRIMARY' | sudo tee /etc/resolv.conf"
  info "or: sudo systemd-resolve --interface=lo --set-dns=$DNS_PRIMARY"
}

setup_dnscrypt() {
  msg "DNSCrypt (ambiguous: DNS routing method is environment-dependent)"
  prompt_choice "Apply DNS change to point at 127.0.0.1?" \
    "Auto-detect (netplan / NetworkManager / systemd-networkd - applies automatically)" \
    "Skip - do not apply DNS change"
  if [ "$REPLY_CHOICE" -eq 1 ]; then
    info "Skipping dnscrypt-proxy."
    return 0
  fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnscrypt-proxy
  if [ ! -f /etc/dnscrypt-proxy/dnscrypt-proxy.toml ]; then
    err "dnscrypt-proxy.toml not found after install - cannot configure."
    return 0
  fi
  if [ ! -f /var/backups/dnscrypt-proxy.toml.bak ] && [ -f /etc/dnscrypt-proxy/dnscrypt-proxy.toml ]; then
    run sudo cp /etc/dnscrypt-proxy/dnscrypt-proxy.toml /var/backups/dnscrypt-proxy.toml.bak
    record_backup /etc/dnscrypt-proxy/dnscrypt-proxy.toml /var/backups/dnscrypt-proxy.toml.bak
  fi
  if ! grep -qE "listen_addresses = \['127.0.0.2:53'\]" /etc/dnscrypt-proxy/dnscrypt-proxy.toml 2>/dev/null; then
    run sudo sed -i "s|# listen_addresses = \[\]|listen_addresses = ['127.0.0.2:53']|" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
  fi
  run sudo systemctl restart dnscrypt-proxy
  run sudo systemctl enable dnscrypt-proxy
  _apply_dns_127_0_0_1
  ok "dnscrypt-proxy installed. Test: dig +short myip.opendns.com @127.0.0.2"
  metrics_add services_hardened 1
  metrics_add pkgs_installed 1
}

setup_firewall() {
  msg "Firewall (UFW)"
  if sudo ufw status | grep -q '^Status: active'; then
    ok "UFW is already active - skipping enable."
    sudo ufw status verbose
    return 0
  fi
  _warn_if_not_tmux
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
  run sudo ufw default deny incoming
  run sudo ufw default allow outgoing
  if [ "$USE_REMOTE_SSH" = "yes" ] || [ "$ENV_TYPE" = "server" ]; then
    warn "Allowing SSH (22) - required for remote access."
    run sudo ufw allow ssh
    metrics_add fw_rules_added 1
  else
    info "Not opening SSH (no remote SSH usage reported)."
  fi
  run sudo ufw --force enable
  metrics_add fw_rules_added 2   # default deny + default allow
  metrics_add services_hardened 1
  run sudo ufw status verbose
}

setup_tor() {
  msg "Tor daemon (user-case dependent)"
  if ! prompt_yn "Install the Tor daemon? (For Tor Browser, get it from torproject.org)" "n"; then
    info "Skipping Tor."; return 0
  fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tor
  metrics_add pkgs_installed 1

  if [ "$ENV_TYPE" = "server" ]; then
    prompt_choice "Auto-configure Tor (server mode)?" \
      "Transparent proxy only (route this host's traffic through Tor)" \
      "Relay only (middle / exit / bridge - help other Tor users)" \
      "Both: private transparent proxy AND a relay (combined)" \
      "Leave /etc/tor/torrc untouched"
    case "$REPLY_CHOICE" in
      0) configure_tor_transparent_proxy; metrics_add tor_services_enabled 1 ;;
      1) configure_tor_relay; metrics_add tor_services_enabled 1 ;;
      2) configure_tor_combined; metrics_add tor_services_enabled 2 ;;
      3) warn "Tor installed but /etc/tor/torrc left untouched. Edit manually for relay/transparent-proxy use." ;;
    esac
  else
    if prompt_yn "Set up a minimal Tor relay/middle relay? (no transparent proxy, just relay traffic)" "n"; then
      configure_tor_relay
      metrics_add tor_services_enabled 1
    else
      warn "Tor installed but /etc/tor/torrc left untouched. Edit manually for relay/transparent-proxy use."
    fi
  fi
  ok "Tor daemon installed."
  metrics_add services_hardened 1
}

configure_tor_combined_apply() {
local CONF="$1" ROLE="$2" OR_PORT="$3" DIR_PORT="$4" NICK="$5" CONTACT="$6"
local BW_RATE="${TOR_BANDWIDTH_RATE:-10}" BW_BURST="${TOR_BANDWIDTH_BURST:-20}"
local ACCT_MAX="${TOR_ACCOUNTING_MAX:-200 GBytes}"
local RELAYDIR="/var/lib/tor-relay" RELAYLOG="/var/log/tor/relay-notices.log"
run sudo mkdir -p "$RELAYDIR" "/var/log/tor"
run sudo tee "$CONF" >/dev/null <<CONFEOF
ORPort $OR_PORT
DirPort $DIR_PORT
Nickname $NICK
ContactInfo $CONTACT
DataDirectory $RELAYDIR
Log notice file $RELAYLOG

BandwidthRate ${BW_RATE} MBytes
BandwidthBurst ${BW_BURST} MBytes
AccountingMax $ACCT_MAX
AccountingStart day 1 00:00

AvoidDiskWrites 1
DisableAllSwap 1
DisableDebuggerAttachment 1
CloseUnknownConnection 1

ConnLimit 512
MaxCircuitDirtiness 10 minutes
NumEntryGuards 6
SafeLogging 1

CONFEOF
case "$ROLE" in
  0) run sudo tee -a "$CONF" >/dev/null <<'EXITEOF'
ExitPolicy reject *:*
EXITEOF
    ;;
  1) run sudo tee -a "$CONF" >/dev/null <<'EXITEOF'
ExitPolicy accept *:25
ExitPolicy accept *:587
ExitPolicy accept *:465
ExitPolicy accept *:993
ExitPolicy accept *:995
ExitPolicy accept *:143
ExitPolicy accept *:110
ExitPolicy accept *:443
ExitPolicy accept *:80
ExitPolicy accept *:53
ExitPolicy accept *:22
ExitPolicy accept *:1-19,20-52,54-79,81-442,444-1023,1025-65535
ExitPolicy reject *:*
EXITEOF
    warn "Exit relay: only listed ports are allowed outbound. Check local laws."
    ;;
  2) run sudo tee -a "$CONF" >/dev/null <<'EXITEOF'
ExitPolicy reject *:*
BridgeRelay 1
ServerTransportListenAddr 0.0.0.0:$OR_PORT
ExtORPort auto
EXITEOF
    ;;
esac
}

configure_tor_combined() {
msg "Combined: transparent proxy + relay (single host, two tor processes)"
local NICK OR_PORT DIR_PORT CONTACT ROLE
local BW_RATE="${TOR_BANDWIDTH_RATE:-10}" BW_BURST="${TOR_BANDWIDTH_BURST:-20}"
local ACCT_MAX="${TOR_ACCOUNTING_MAX:-200 GBytes}"
prompt_choice "Pick a relay role to run alongside the transparent proxy" \
  "Middle relay (default, recommended for first-time)" \
  "Exit relay (only on a server you own and trust - legal implications)" \
  "Bridge relay (helps censored users)"
ROLE=$REPLY_CHOICE
case "$ROLE" in
  0) OR_PORT="9001"; DIR_PORT="9030";;
  1) OR_PORT="443";   DIR_PORT="80";  warn "Exit relay exposes your IP for other users' traffic.";;
  2) OR_PORT="9001";  DIR_PORT="9030";;
esac
NICK="${TOR_NICK:-UbuntuServer$(hostname -s 2>/dev/null | tr -dc 'A-Za-z0-9' || echo relay)}"
CONTACT="${TOR_CONTACT:-you@example.com}"

local RELAYCONF="/etc/tor/torrc.relay"
local TORSYSTEMD="/etc/systemd/system/tor-relay.service"

  msg "Configuring primary tor (transparent proxy role)"
  local TORRC="/etc/tor/torrc"
  if [ -f "$TORRC" ]; then
    local TORBAK
    TORBAK="${TORRC}.bak.$(date +%s)"
    run sudo cp "$TORRC" "$TORBAK"
    record_backup "$TORRC" "$TORBAK"
  fi
  run sudo tee "$TORRC" >/dev/null <<'EOF'
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
AutomapHostsSuffixes .onion,.exit
TransPort 127.0.0.1:9040 IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort
DNSPort 127.0.0.2:53
Log notice file /var/log/tor/notices.log
ORPort 0
DirPort 0
EOF
_warn_if_not_tmux
run sudo systemctl restart tor
if ! sudo systemctl is-active --quiet tor; then
  err "Primary tor failed - restoring torrc and aborting combined setup."
  run sudo cp -f "${TORRC}.bak."* "$TORRC"
  return 1
fi
ok "Primary tor (transparent proxy) active."

  msg "Configuring relay companion ($ROLE)"
  if [ -f "$RELAYCONF" ] && ! compgen -G "${RELAYCONF}.bak.*" >/dev/null 2>&1; then
    local RELAYBAK
    RELAYBAK="${RELAYCONF}.bak.$(date +%s)"
    run sudo cp "$RELAYCONF" "$RELAYBAK"
    record_backup "$RELAYCONF" "$RELAYBAK"
  fi
  if [ -f "$TORSYSTEMD" ] && ! compgen -G "${TORSYSTEMD}.bak.*" >/dev/null 2>&1; then
    local UNITBAK
    UNITBAK="${TORSYSTEMD}.bak.$(date +%s)"
    run sudo cp "$TORSYSTEMD" "$UNITBAK"
    record_backup "$TORSYSTEMD" "$UNITBAK"
  fi
  configure_tor_combined_apply "$RELAYCONF" "$ROLE" "$OR_PORT" "$DIR_PORT" "$NICK" "$CONTACT"
run sudo chown -R debian-tor:debian-tor "$RELAYDIR"
  run sudo tee "$TORSYSTEMD" >/dev/null <<EOF
[Unit]
Description=Tor relay (companion to local transparent proxy)
After=network-online.target nss-lookup.target tor.service
Wants=network-online.target tor.service

[Service]
Type=simple
ExecStart=/usr/bin/tor -f $RELAYCONF
User=debian-tor
Group=debian-tor
Restart=on-failure
RestartSec=10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
run sudo systemctl daemon-reload
run sudo systemctl enable --now tor-relay.service
if ! sudo systemctl is-active --quiet tor-relay.service; then
  err "tor-relay failed - check: sudo journalctl -u tor-relay --no-pager | tail -30"
else
  ok "tor-relay active on ORPort=$OR_PORT DirPort=$DIR_PORT."
fi

run sudo ufw allow "$OR_PORT"/tcp
run sudo ufw allow "$DIR_PORT"/tcp

_warn_if_not_tmux
run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
local cmds=(
  "iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN"
  "iptables -t nat -A OUTPUT -d 192.168.0.0/16 -j RETURN"
  "iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN"
  "iptables -t nat -A OUTPUT -d 10.0.0.0/8 -j RETURN"
  "iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p udp --dport 80 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p udp --dport 443 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p tcp --dport $OR_PORT -j RETURN"
  "iptables -t nat -A OUTPUT -p tcp --dport $DIR_PORT -j RETURN"
)
for c in "${cmds[@]}"; do
  run sudo $c
done
run sudo netfilter-persistent save

ok "Transparent proxy + $ROLE active. Bandwidth capped at ${BW_RATE} MB/s sustained, ${BW_BURST} MB/s burst."
info "Monthly accounting limit: $ACCT_MAX"
info "Verify exit:   curl --max-time 10 https://check.torproject.org/api/ip"
info "Verify relay:  https://metrics.torproject.org/rs.html (search: $NICK)"
info "Bridge (if bridge role):  provide this line to users: $(grep -E '^Bridge ' "$RELAYCONF" 2>/dev/null || echo 'not yet published')"
warn "apt updates slow. Revert iptables: sudo iptables -t nat -F OUTPUT"
}

configure_tor_transparent_proxy() {
local TORRC="/etc/tor/torrc"
if [ -f "$TORRC" ]; then
  local TORBAK
  TORBAK="${TORRC}.bak.$(date +%s)"
  run sudo cp "$TORRC" "$TORBAK"
  record_backup "$TORRC" "$TORBAK"
fi
run sudo tee "$TORRC" >/dev/null <<'EOF'
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 127.0.0.1:9040 IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort
DNSPort 127.0.0.2:53
AutomapHostsSuffixes .onion,.exit
Log notice file /var/log/tor/notices.log
EOF
_warn_if_not_tmux
run sudo systemctl restart tor
run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
local cmds=(
  "iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN"
  "iptables -t nat -A OUTPUT -d 192.168.0.0/16 -j RETURN"
  "iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN"
  "iptables -t nat -A OUTPUT -d 10.0.0.0/8 -j RETURN"
  "iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p udp --dport 80 -j REDIRECT --to-ports 9040"
  "iptables -t nat -A OUTPUT -p udp --dport 443 -j REDIRECT --to-ports 9040"
)
for c in "${cmds[@]}"; do
  run sudo $c
done
run sudo netfilter-persistent save
ok "Tor transparent proxy active. Verify: curl --max-time 10 https://check.torproject.org/api/ip"
warn "apt updates will be much slower; consider 'sudo iptables -t nat -F OUTPUT' to revert."
}

configure_tor_relay() {
local NICK OR_PORT DIR_PORT CONTACT ROLE
local BW_RATE="${TOR_BANDWIDTH_RATE:-10}"
local BW_BURST="${TOR_BANDWIDTH_BURST:-20}"
local ACCT_MAX="${TOR_ACCOUNTING_MAX:-200 GBytes}"
prompt_choice "Pick a relay role" "Middle relay (default, recommended for first-time)" "Exit relay (only on a server you own and trust)" "Bridge relay (helps censored users)"
ROLE=$REPLY_CHOICE
case "$ROLE" in
  0) OR_PORT="auto"; DIR_PORT="auto";;
  1) OR_PORT="443";   DIR_PORT="80";   warn "Exit relay exposes your IP for other users' traffic - operate only on infrastructure you own.";;
  2) OR_PORT="auto";  DIR_PORT="auto";;
esac
NICK="${TOR_NICK:-UbuntuServer$(hostname -s 2>/dev/null | tr -dc 'A-Za-z0-9' || echo relay)}"
CONTACT="${TOR_CONTACT:-you@example.com}"

  local TORRC="/etc/tor/torrc"
  local TORBAK
  TORBAK="${TORRC}.bak.$(date +%s)"
  run sudo cp "$TORRC" "$TORBAK"
  record_backup "$TORRC" "$TORBAK"
  run sudo tee "$TORRC" >/dev/null <<EOF
ORPort $OR_PORT
DirPort $DIR_PORT
Nickname $NICK
ContactInfo $CONTACT
Log notice file /var/log/tor/notices.log

BandwidthRate ${BW_RATE} MBytes
BandwidthBurst ${BW_BURST} MBytes
AccountingMax $ACCT_MAX
AccountingStart day 1 00:00

AvoidDiskWrites 1
DisableAllSwap 1
DisableDebuggerAttachment 1
CloseUnknownConnection 1
SafeLogging 1

EOF
case "$ROLE" in
  0)
    run sudo tee -a "$TORRC" >/dev/null <<'EXITEOF'
ExitPolicy reject *:*
ConnLimit 512
MaxCircuitDirtiness 10 minutes
NumEntryGuards 6
EXITEOF
    ;;
  1)
    warn "Exit relay: listing common safe ports. Check local laws before running."
    run sudo tee -a "$TORRC" >/dev/null <<'EXITEOF'
ExitPolicy accept *:25,465,587,993,995,143,110,443,80,53,22
ExitPolicy reject *:*
EXITEOF
    ;;
  2)
    run sudo tee -a "$TORRC" >/dev/null <<'EXITEOF'
ExitPolicy reject *:*
BridgeRelay 1
ExtORPort auto
EXITEOF
    ;;
esac
_warn_if_not_tmux
run sudo ufw allow "$OR_PORT"/tcp 2>/dev/null || true
run sudo ufw allow "$DIR_PORT"/tcp 2>/dev/null || true
run sudo systemctl restart tor
if ! sudo systemctl is-active --quiet tor; then
  err "tor failed - restoring torrc."
  run sudo cp -f "${TORRC}.bak."* "$TORRC" 2>/dev/null
  return 1
fi
ok "Tor relay starting on ORPort=$OR_PORT DirPort=$DIR_PORT. Bandwidth: ${BW_RATE} MB/s, accounting: $ACCT_MAX"
info "Check reachability at https://metrics.torproject.org/rs.html (search your nickname)."
info "First sync with other relays can take 20-60 minutes."
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
  if [ -f /etc/sysctl.conf ] && [ ! -f /var/backups/sysctl.conf.bak ]; then
    run sudo cp /etc/sysctl.conf /var/backups/sysctl.conf.bak
    record_backup /etc/sysctl.conf /var/backups/sysctl.conf.bak
  fi
  # Ensure sysctl.conf ends in a newline, then append. If the last byte is
  # already \n, the shell's >> append starts a fresh line automatically.
  run sudo bash -c 'last=$(tail -c1 /etc/sysctl.conf); [ "$last" != "" ] && [ "$last" != $'"'"'\n'"'"' ] && printf "\n" >> /etc/sysctl.conf'
  run sudo tee -a /etc/sysctl.conf >/dev/null <<'EOF'

# disabled by ubuntuinstall.sh
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
  warn "Reboot may be required for full effect."
}

# Helper: set a directive in sshd_config to a value, or append it if absent.
# Looks in the main file AND the drop-ins so a directive that was set via
# /etc/ssh/sshd_config.d/*.conf is correctly rewritten.
_set_or_append_sshd_config() {
  local param="$1" value="$2" cfg="$3"
  if grep -qE "^#?${param}" "$cfg" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
    run sudo sed -i "s/^#\?${param}.*/${param} ${value}/" "$cfg"
  else
    printf '%s %s\n' "$param" "$value" | run sudo tee -a "$cfg" >/dev/null
  fi
}

backup_and_report_authorized_keys() {
  local bakdir="/var/backups/ubuntu-install-ssh"
  run sudo mkdir -p "$bakdir"
  local f count
  for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [ -f "$f" ] || continue
    count=$(grep -cE '^(ssh-|ecdsa-)' "$f" 2>/dev/null || echo 0)
    [ "$count" -eq 0 ] && continue
    run sudo cp -a "$f" "$bakdir/$(echo "$f" | tr '/' '_').bak.$(date +%s)"
    info "Preserved $f ($count keys) -> $bakdir/$(basename "$f").bak.*"
  done
}

audit_authorized_keys() {
  msg "Audit of existing SSH keys (before any changes)"
  local f count total=0
  for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [ -f "$f" ] || { info "  (none)  $f"; continue; }
    count=$(grep -cE '^(ssh-|ecdsa-)' "$f" 2>/dev/null || echo 0)
    info "  $count key(s) in $f"
    total=$((total + count))
    grep -E '^(ssh-|ecdsa-)' "$f" 2>/dev/null | while IFS= read -r k; do
      printf "    %s  %s\n" "$(echo "$k" | awk '{print $1, $2}' | head -c 50)..." "$(echo "$k" | awk '{print $NF}')"
    done
  done
  info "Total keys across all authorized_keys files: $total"
  printf "  Current sshd_config PasswordAuthentication: "
  grep -E '^#?\s*PasswordAuthentication' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | head -3
}

setup_authorized_keys_with_validation() {
  local target_user target_home target_ak
  target_user="${SUDO_USER:-$USER}"
  if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
    target_user="$(logname 2>/dev/null || whoami)"
  fi
  target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
  [ -n "$target_home" ] || target_home="/root"
  target_ak="$target_home/.ssh/authorized_keys"

  msg "Setting up authorized_keys for user: $target_user (home: $target_home)"

  sudo -u "$target_user" mkdir -p "$target_home/.ssh"
  sudo -u "$target_user" chmod 700 "$target_home/.ssh"
  sudo -u "$target_user" touch "$target_ak"
  sudo -u "$target_user" chmod 600 "$target_ak"

  local recovery_key="$target_home/.ssh/id_ed25519_recovery"
  # The key is owned by $target_user with mode 600; root can stat but the
  # test below runs as the OUTER shell, not as $target_user, so an
  # unreadable-by-root mode would trigger spurious regeneration. Use
  # sudo -u so the file lookup matches the owner.
  if ! sudo -u "$target_user" test -f "$recovery_key"; then
    info "Generating a server-side recovery key (ed25519) at $recovery_key"
    if ! sudo -u "$target_user" ssh-keygen -t ed25519 -N "" -f "$recovery_key" -C "ubuntu-install-recovery@$(hostname)" 2>/dev/null; then
      err "Could not generate recovery key."
    else
      printf "\n\033[1;33m[!] EMERGENCY RECOVERY KEY\033[0m (printed in case you get locked out):\n"
      printf "  Path on server: %s\n" "$recovery_key"
      printf "  Copy it to your laptop now:  scp %s@%s:%s ~/\n" "$target_user" "$(hostname)" "$recovery_key"
      printf "  Then 'ssh-add ~/id_ed25519_recovery' before disconnecting.\n"
      printf "  Public:\n"
      sudo -u "$target_user" cat "$recovery_key.pub"
      printf "  (already added to %s)\n\n" "$target_ak"
    fi
  fi

  if ! grep -qF "$(sudo -u "$target_user" cat "$recovery_key.pub" 2>/dev/null)" "$target_ak" 2>/dev/null; then
    sudo -u "$target_user" tee -a "$target_ak" >/dev/null < "$recovery_key.pub"
  fi

  if [ ! -t 0 ]; then
    err "stdin is not a TTY - cannot paste a public key safely."
    info "Re-run this script interactively (terminal attached) to set up a key."
    return 1
  fi

  printf "\033[1;33m──────────────────────────────────────────────────────────────────────\033[0m\n"
  printf "\033[1;33m│  PASTE YOUR LAPTOP'S PUBLIC SSH KEY BELOW.\033[0m\n"
  printf "\033[1;33m│  Format: ssh-ed25519 AAAA... user@host  OR  ssh-rsa AAAA... user@host\033[0m\n"
  printf "\033[1;33m│  Press Enter on an empty line when done, or type 'skip' to abort.\033[0m\n"
  printf "\033[1;33m──────────────────────────────────────────────────────────────────────\033[0m"
  printf "> "

  local pasted_key="" line
  while IFS= read -r line; do
    [ -z "$line" ] && break
    if [ "$line" = "skip" ]; then pasted_key=""; break; fi
    pasted_key="$line"
    break
  done

  if [ -z "$pasted_key" ]; then
    err "No public key pasted."
    return 1
  fi

  if ! echo "$pasted_key" | grep -qE '^(ssh-(ed25519|rsa|dss|ecdsa)|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/=]+( .+)?$'; then
    err "Pasted value does not look like a valid SSH public key."
    return 1
  fi

  if grep -qF "$pasted_key" "$target_ak"; then
    ok "Public key already in authorized_keys."
  else
    echo "$pasted_key" | sudo -u "$target_user" tee -a "$target_ak" >/dev/null
    sudo -u "$target_user" chmod 600 "$target_ak"
    ok "Public key added to $target_ak"
  fi

  if ! prompt_yn "Have you VERIFIED that this public key works (e.g., you can SSH from your laptop with it)?" "n"; then
    warn "Skipping PasswordAuthentication change - pubkey not confirmed working."
    return 1
  fi

  return 0
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

  backup_and_report_authorized_keys
  audit_authorized_keys

  local SSHCFG="/etc/ssh/sshd_config"
  local BACKUP
  BACKUP="${SSHCFG}.bak.$(date +%s)"
  run sudo cp "$SSHCFG" "$BACKUP"
  record_backup "$SSHCFG" "$BACKUP"

  if prompt_yn "Set PermitRootLogin no?" "y"; then
    if grep -qE '^PermitRootLogin' "$SSHCFG" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
      run sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHCFG"
    else
      run sudo tee -a "$SSHCFG" >/dev/null <<'SSHEOF'
PermitRootLogin no
SSHEOF
    fi
    metrics_add services_hardened 1
  fi

  if prompt_yn "Reduce LoginGraceTime to 30s and MaxAuthTries to 3?" "y"; then
    for param in LoginGraceTime MaxAuthTries MaxSessions; do
      if grep -qE "^${param}" "$SSHCFG" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
        case "$param" in
          LoginGraceTime) run sudo sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 30s/' "$SSHCFG" ;;
          MaxAuthTries)  run sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHCFG" ;;
          MaxSessions)    run sudo sed -i 's/^#\?MaxSessions.*/MaxSessions 2/' "$SSHCFG" ;;
        esac
      else
        printf '%s %s\n' "$param" \
          "$(case "$param" in LoginGraceTime) echo "30s";; MaxAuthTries) echo "3";; MaxSessions) echo "2";; esac)" \
          | run sudo tee -a "$SSHCFG" >/dev/null
      fi
    done
    metrics_add services_hardened 1
  fi

  if prompt_yn "Change SSH port from 22 to 2222? (can lock you out if firewall not updated)" "n"; then
    _warn_if_not_tmux
    printf "\033[1;31m[!] SSH port change — losing connection?\033[0m  Reconnect with:\n"
    printf "  \033[1;36mssh -p 2222 %s@%s\033[0m\n" "$USER" "$(hostname -I 2>/dev/null | awk '{print $1}')"
    read -r -p "Press Enter to continue, or Ctrl-C to abort... " _
    if grep -qE '^Port' "$SSHCFG" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
      run sudo sed -i 's/^#\?Port 22$/Port 2222/' "$SSHCFG"
    else
      run sudo tee -a "$SSHCFG" >/dev/null <<'SSHEOF'
Port 2222
SSHEOF
    fi
    run sudo ufw allow 2222/tcp
    metrics_add fw_rules_added 1
  fi

  if prompt_yn "Disable password authentication (PubKey only)? THIS CAN LOCK YOU OUT" "n"; then
    local ak_count=0 f c
    for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
      [ -f "$f" ] || continue
      c=$(grep -cE '^(ssh-|ecdsa-)' "$f" 2>/dev/null) || c=0
      ak_count=$((ak_count + c))
    done
    if [ "$ak_count" -eq 0 ]; then
      warn "No public keys found in any authorized_keys. Helping you set one up safely."
      if ! setup_authorized_keys_with_validation; then
        err "No working pubkey validated. Leaving PasswordAuthentication unchanged."
        if prompt_yn "Re-enable PasswordAuthentication explicitly (yes)?" "y"; then
          _set_or_append_sshd_config "PasswordAuthentication" "yes" "$SSHCFG"
        fi
      else
        ok "Pubkey validated. Disabling password auth."
        _set_or_append_sshd_config "PasswordAuthentication" "no" "$SSHCFG"
        metrics_add services_hardened 1
        metrics_add auth_keys_added 1
      fi
    else
      printf "\033[1;33m──────────────────────────────────────────────────────────────────────\033[0m\n"
      printf "\033[1;33m│  Confirm your pubkey is one of the $ak_count listed above.         \033[0m\n"
      printf "\033[1;33m│  If you are NOT sure, type 'no' to keep password auth enabled.     \033[0m\n"
      printf "\033[1;33m──────────────────────────────────────────────────────────────────────\033[0m\n"
      if ! prompt_yn "Disable PasswordAuthentication? (type 'yes' to confirm)" "no"; then
        warn "Leaving PasswordAuthentication unchanged."
      else
        _set_or_append_sshd_config "PasswordAuthentication" "no" "$SSHCFG"
        metrics_add services_hardened 1
      fi
    fi
  fi

  # Validate using sshd -t with the REAL config (not -f, which excludes
  # /etc/ssh/sshd_config.d/*.conf drop-ins). Capture stderr so we can
  # show the user the actual error.
  local sshd_check_err
  if ! sshd_check_err="$(sudo sshd -t 2>&1)"; then
    err "sshd config is INVALID: $sshd_check_err"
    err "Reverting backup and NOT restarting."
    run sudo cp -f "$BACKUP" "$SSHCFG"
    return 1
  fi
  _warn_if_not_tmux
  run sudo systemctl restart ssh
  ok "SSH hardened and restarted. Verify in a SECOND session before closing this one."
}

setup_fail2ban() {
  if [ "$USE_REMOTE_SSH" != "yes" ] && [ "$ENV_TYPE" != "server" ]; then
    info "Skipping Fail2ban (no remote SSH and not a server)."; return 0
  fi
  msg "Fail2ban"
  if ! prompt_yn "Install & enable Fail2ban with the sshd jail?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
  if [ ! -f /etc/fail2ban/jail.local ]; then
    local JAILBAK
    JAILBAK="/etc/fail2ban/jail.local.bak.$(date +%s)"
    run sudo cp /etc/fail2ban/jail.conf "$JAILBAK"
    record_backup /etc/fail2ban/jail.conf "$JAILBAK"
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
  metrics_add services_hardened 1
}

configure_unattended_upgrades() {
  msg "Unattended security upgrades"
  if ! prompt_yn "Enable automatic security updates?" "y"; then return 0; fi
  if grep -qE '^Unattended-Upgrade::Allowed-Origins' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null; then
    ok "Unattended upgrades already configured."
    return 0
  fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
  if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ] && [ ! -f /var/backups/50unattended-upgrades.bak ]; then
    run sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /var/backups/50unattended-upgrades.bak
    record_backup /etc/apt/apt.conf.d/50unattended-upgrades /var/backups/50unattended-upgrades.bak
  fi
  run sudo sed -i 's|//\s*Unattended-Upgrade::Allowed-Origins|Unattended-Upgrade::Allowed-Origins|' /etc/apt/apt.conf.d/50unattended-upgrades || true
  run sudo sed -i 's|Unattended-Upgrade::Automatic-Reboot "false"|Unattended-Upgrade::Automatic-Reboot "true"|' /etc/apt/apt.conf.d/50unattended-upgrades || true
  ok "Unattended upgrades enabled."
}

harden_sysctl() {
  msg "Kernel/network hardening via sysctl"
  if ! prompt_yn "Apply the 99-hardening.conf sysctl profile from the README?" "y"; then return 0; fi
  local f="/etc/sysctl.d/99-hardening.conf"
  if [ -f "$f" ] && [ ! -f /var/backups/99-hardening.conf.bak ]; then
    run sudo cp "$f" /var/backups/99-hardening.conf.bak
    record_backup "$f" /var/backups/99-hardening.conf.bak
  fi
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
  metrics_add sysctls_applied 22
  metrics_add services_hardened 1
}

setup_apparmor() {
  msg "AppArmor (MAC)"
  if ! prompt_yn "Install & enable AppArmor?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils
  run sudo systemctl enable --now apparmor
  metrics_add services_hardened 1
  run sudo aa-status || true
}

harden_passwords() {
  msg "Password & lockout policy"
  if ! prompt_yn "Install libpam-pwquality and set minlen=14?" "y"; then return 0; fi
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libpam-pwquality
  if [ -f /etc/security/pwquality.conf ] && [ ! -f /var/backups/pwquality.conf.bak ]; then
    run sudo cp /etc/security/pwquality.conf /var/backups/pwquality.conf.bak
    record_backup /etc/security/pwquality.conf /var/backups/pwquality.conf.bak
  fi
  declare -A pwq_vals=( [minlen]=14 [minclass]=3 [maxrepeat]=3 )
  for kw in "${!pwq_vals[@]}"; do
    grep -q "^${kw}[[:space:]]*=" /etc/security/pwquality.conf 2>/dev/null || \
      echo "${kw} = ${pwq_vals[${kw}]}" | sudo tee -a /etc/security/pwquality.conf >/dev/null
  done
  if [ -f /etc/security/faillock.conf ] && [ ! -f /var/backups/faillock.conf.bak ]; then
    run sudo cp /etc/security/faillock.conf /var/backups/faillock.conf.bak
    record_backup /etc/security/faillock.conf /var/backups/faillock.conf.bak
  fi
  run sudo tee /etc/security/faillock.conf >/dev/null <<'EOF'
deny = 5
unlock_time = 900
EOF
  if grep -qE '^TMOUT=900; readonly TMOUT; export TMOUT' /etc/profile.d/99-tmout.sh 2>/dev/null; then
    ok "Password/lockout policy already applied."
    return 0
  fi
  if [ -f /etc/profile.d/99-tmout.sh ] && [ ! -f /var/backups/99-tmout.sh.bak ]; then
    run sudo cp /etc/profile.d/99-tmout.sh /var/backups/99-tmout.sh.bak
    record_backup /etc/profile.d/99-tmout.sh /var/backups/99-tmout.sh.bak
  fi
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
  print_recovery_if_ssh
  _warn_if_not_tmux

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
  print_metrics_summary
  info "Review changes. Reboot when ready: sudo reboot"
  if [ "$USE_REMOTE_SSH" = "yes" ]; then
    info "Because SSH was changed, verify a SECOND session can log in BEFORE closing this one."
  fi
}

main "$@"
