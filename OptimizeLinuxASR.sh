#!/usr/bin/env bash

# ==============================================================================
# Ubuntu/Linux Holistic Service Optimizer & Attack Surface Reducer
# Prompts the user to disable non-essential daemons to free up system resources
# and reduce potential security vulnerabilities.
# ==============================================================================

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please use sudo." 
   exit 1
fi

echo "============================================================================="
echo "         Ubuntu Service Optimization & Attack Surface Script                 "
echo "============================================================================="
echo "You will be prompted to manage services by category."
echo "For each category, you can choose to:"
echo "  [i] Interact: Prompt for each service individually (Default)"
echo "  [a] Disable All: Bulk disable every applicable service in the category"
echo "  [s] Skip All: Bulk skip (keep) every service in the category"
echo "============================================================================="
echo ""

# Global variable to hold the current category's bulk action
CATEGORY_ACTION="i"

# Function to ask for category bulk action
ask_category() {
    local category_name="$1"
    echo ""
    echo "============================================================================="
    echo " CATEGORY: ${category_name}"
    echo "============================================================================="
    while true; do
        read -r -p "Action for this category? [i=Interactive / a=Disable All / s=Skip All] (Default i): " cat_choice
        cat_choice=${cat_choice,,} # Convert to lowercase
        case "$cat_choice" in
            a|all )
                CATEGORY_ACTION="a"
                echo " -> Action: DISABLING ALL applicable services in ${category_name}."
                break ;;
            s|skip|none )
                CATEGORY_ACTION="s"
                echo " -> Action: SKIPPING ALL services in ${category_name}."
                break ;;
            i|interactive|"" )
                CATEGORY_ACTION="i"
                echo " -> Action: Interactive mode."
                break ;;
            * )
                echo "Invalid choice. Please enter i, a, or s."
                ;;
        esac
    done
    echo ""
}

# Function to prompt and disable a service
ask_disable() {
    local service="$1"
    local description="$2"
    local default_choice="${3:-N}" # Default to No if not specified

    if [[ "$CATEGORY_ACTION" == "s" ]]; then
        # Silently skip if category action is Skip All
        return
    fi

    # Check if service exists and is currently enabled or active
    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1 || systemctl list-unit-files "${service}" >/dev/null 2>&1 || systemctl list-unit-files "${service}.socket" >/dev/null 2>&1; then
        local is_enabled
        is_enabled=$(systemctl is-enabled "${service}" 2>/dev/null)
        local is_active
        is_active=$(systemctl is-active "${service}" 2>/dev/null)
        
        if [[ "$is_enabled" == "enabled" || "$is_active" == "active" ]]; then
            local choice
            
            if [[ "$CATEGORY_ACTION" == "a" ]]; then
                choice="y"
                echo "[BULK DISABLE] ${service}: ${description}"
            else
                read -r -p "Disable ${service} (${description})? [y/N]: " choice
                # Default handling
                if [[ -z "$choice" ]]; then
                    choice="$default_choice"
                fi
            fi

            case "$choice" in
                [Yy]* )
                    echo " -> Stopping and disabling ${service}..."
                    systemctl stop "${service}" 2>/dev/null
                    systemctl disable "${service}" 2>/dev/null
                    systemctl mask "${service}" 2>/dev/null # Optional: prevents it from being started by other services
                    echo " -> ${service} disabled."
                    ;;
                * )
                    echo " -> Skipping ${service}."
                    ;;
            esac
        else
            if [[ "$CATEGORY_ACTION" == "i" ]]; then
                echo "[INFO] ${service} is already disabled or inactive. Skipping."
            fi
        fi
    else
        if [[ "$CATEGORY_ACTION" == "i" ]]; then
            echo "[INFO] ${service} is not installed on this system. Skipping."
        fi
    fi
    
    if [[ "$CATEGORY_ACTION" == "i" ]]; then
        echo ""
    fi
}

# ==============================================================================
# 1. Hardware & Peripherals
# ==============================================================================
ask_category "Hardware & Peripherals"
ask_disable "bluetooth" "Bluetooth daemon. Disable if you do not use Bluetooth devices."
ask_disable "cups" "Common Unix Printing System. Disable if you do not print from this machine."
ask_disable "cups-browsed" "Discovers shared network printers. Safe to disable if not printing."
ask_disable "ModemManager" "Provides mobile broadband (2G/3G/4G) support. Disable if you don't use cellular modems."
ask_disable "pcscd" "Smart Card Reader daemon. Disable if you don't use hardware security keys/smart cards."

# ==============================================================================
# 2. Networking Services
# ==============================================================================
ask_category "Networking Services"
ask_disable "avahi-daemon" "mDNS/DNS-SD (Bonjour/Zeroconf) for local network discovery. Often unneeded on servers."
ask_disable "nfs-server" "Network File System server. Disable if you do not host NFS shares."
ask_disable "NetworkManager-wait-online" "Delays boot until network is connected. Disabling can speed up boot times."

# ==============================================================================
# 3. Attack Surface Reduction & Legacy Protocols
# ==============================================================================
ask_category "Attack Surface Reduction & Legacy Protocols"
ask_disable "rpcbind" "Portmapper service (RPC). High attack surface. Disable if no NFS or RPC mounts."
ask_disable "smbd" "Samba SMB daemon. Disable if you are not sharing files with Windows networks."
ask_disable "nmbd" "Samba NetBIOS daemon. Disable if you do not need legacy Windows network discovery."
ask_disable "vsftpd" "FTP server. Insecure protocol. Disable unless explicitly required."
ask_disable "proftpd" "Alternative FTP server. Insecure protocol. Disable unless explicitly required."
ask_disable "pure-ftpd" "Alternative FTP server. Insecure protocol. Disable unless explicitly required."
ask_disable "tftpd-hpa" "Trivial File Transfer Protocol. Unauthenticated, highly insecure. Disable unless needed for PXE booting."
ask_disable "snmpd" "Simple Network Management Protocol daemon. High attack surface if misconfigured."
ask_disable "rsync" "Rsync daemon (rsyncd). Disable if you only use rsync over SSH."
ask_disable "telnet.socket" "Legacy Telnet. Extremely insecure unencrypted protocol."
ask_disable "xinetd" "Legacy internet superserver daemon. Rarely needed on modern systems."
ask_disable "inetd" "Legacy internet superserver daemon. Rarely needed on modern systems."
ask_disable "postfix" "Mail Transfer Agent. Disable if this system does not need to send/receive emails directly."
ask_disable "exim4" "Mail Transfer Agent. Disable if this system does not need to send/receive emails directly."
ask_disable "apache2" "Apache Web Server. Disable if this machine is not actively hosting websites."
ask_disable "nginx" "Nginx Web Server. Disable if this machine is not actively hosting websites."

# ==============================================================================
# 4. Storage & Virtualization
# ==============================================================================
ask_category "Storage & Virtualization"
ask_disable "multipathd" "Handles multiple I/O paths to storage arrays. Common on Ubuntu Server but rarely needed for standard local drives."
ask_disable "lvm2-monitor" "Monitors LVM volumes. Disable ONLY if you are absolutely sure you do not use LVM (Logical Volume Management)."
ask_disable "iscsid" "iSCSI daemon. Disable if you do not connect to iSCSI network storage targets."
ask_disable "libvirtd" "Virtualization daemon. Disable if you do not run KVM/QEMU virtual machines on this host."

# ==============================================================================
# 5. Telemetry, Diagnostics & Updates
# ==============================================================================
ask_category "Telemetry, Diagnostics & Updates"
ask_disable "apport" "Ubuntu crash reporting service. Safe to disable for privacy/security."
ask_disable "whoopsie" "Ubuntu crash database submission daemon. Safe to disable for privacy/security."
ask_disable "unattended-upgrades" "Automatically downloads and installs security updates. Disable ONLY if you prefer fully manual updates."
ask_disable "motd-news.timer" "Fetches dynamic Message of the Day news on login. Safe to disable."

# ==============================================================================
# 6. Snap & Package Management (Use Caution)
# ==============================================================================
ask_category "Snap & Package Management"
ask_disable "snapd" "Snap package manager. WARNING: Disabling this will break all snap applications (often including Firefox on newer Ubuntu)."

# ==============================================================================
# 7. Miscellaneous
# ==============================================================================
ask_category "Miscellaneous"
ask_disable "speech-dispatcher" "Speech synthesis daemon. Usually unnecessary unless you use screen readers/accessibility tools."
ask_disable "geoclue" "Geolocation service. Often unneeded on stationary servers or desktops without location-aware apps."

echo "============================================================================="
echo "Optimization & Attack Surface Reduction complete!" 
echo "You may want to reboot your system for all changes to take full effect."
echo "If you ever need to re-enable a service, use:"
echo "sudo systemctl unmask <service> && sudo systemctl enable --now <service>"
echo "============================================================================="
