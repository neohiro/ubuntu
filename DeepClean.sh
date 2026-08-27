#!/bin/bash
# Comprehensive Ubuntu DeepClean & Auto-Prune Script
# Ensure you run this script as root (sudo ./cleanup.sh)

# Get initial disk usage for comparison later. 
# Using -kP ensures output is in KB and forces POSIX format to prevent line 
# breaks on long filesystem names (e.g., LVM volumes or container overlays).
USED_BEFORE_KB=$(df -kP / | tail -1 | awk '{print $3}')

# ==============================================================================
# ACTIVE CLEANUP PHASE
# ==============================================================================

# 1. Systemd Journal Logs
# Keeps only the last 1 day of logs and caps the total size at 50MB
echo "Cleaning systemd journal logs..."
journalctl --vacuum-time=1d
journalctl --vacuum-size=50M

# 2. Rotated and Compressed Logs
# Removes all archived logs (e.g., .gz, .1, .2) in /var/log
echo "Removing old rotated log files in /var/log..."
find /var/log -type f -regex ".*\.[0-9]$" -delete
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.xz" -delete

# 3. Active Legacy Logs
# Truncates large active text logs to 0 bytes without deleting the file itself, 
# preventing log daemons from crashing due to missing files.
echo "Truncating active legacy log files..."
for log in /var/log/syslog /var/log/messages /var/log/auth.log /var/log/kern.log /var/log/dpkg.log /var/log/daemon.log; do
    if [ -f "$log" ]; then
        truncate -s 0 "$log"
    fi
done

# 4. Apt Cache, Orphaned Packages, and Old Kernels
# Clears the local repository of retrieved package files and removes unused dependencies
echo "Cleaning apt cache and unused dependencies (including old kernels)..."
apt-get clean -y
apt-get autoremove --purge -y

# 5. Residual Configuration Files (rc state)
# When packages are removed but not purged, their configs remain. This clears them.
echo "Purging residual package configuration files..."
dpkg -l | awk '/^rc/ {print $2}' | xargs -r dpkg --purge

# 6. Old Snap Revisions
# Ubuntu keeps disabled old versions of snap packages which consume massive disk space.
if command -v snap >/dev/null 2>&1; then
    echo "Removing disabled snap revisions..."
    LANG=C snap list --all | awk '/disabled/{print $1, $3}' |
        while read snapname revision; do
            snap remove "$snapname" --revision="$revision" || true
        done
    
    # Clear snap cache
    rm -rf /var/lib/snapd/cache/*
fi

# 7. Docker Artifacts (If Installed)
# Safely prunes unused containers, networks, dangling images, and build cache.
if command -v docker >/dev/null 2>&1; then
    echo "Deep cleaning Docker artifacts (unused images, containers, networks, volumes)..."
    docker system prune -a -f --volumes
fi

# 8. Flatpak Leftovers (If Installed)
# Removes unused Flatpak runtimes and apps.
if command -v flatpak >/dev/null 2>&1; then
    echo "Removing unused Flatpak runtimes..."
    flatpak uninstall --unused -y
fi

# 9. Crash Reports & System Trash
echo "Removing old crash reports and system trash..."
rm -rf /var/crash/*
# Safely clear temp files managed by systemd
systemd-tmpfiles --clean 2>/dev/null || true
# Empty root trash
rm -rf /root/.local/share/Trash/* 2>/dev/null || true
# Empty user trash directories
find /home/*/.local/share/Trash/* -delete 2>/dev/null || true

# ==============================================================================
# FUTURE AUTO-PRUNING CONFIGURATION PHASE
# ==============================================================================

# 10. Configure Automated Future Pruning (journald)
echo "Configuring journald for automatic log retention..."
JOURNALD_CONF="/etc/systemd/journald.conf"

# Update SystemMaxUse
if grep -qE "^#?SystemMaxUse=" "$JOURNALD_CONF"; then
    sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=200M/' "$JOURNALD_CONF"
else
    echo "SystemMaxUse=200M" >> "$JOURNALD_CONF"
fi

# Update MaxRetentionSec
if grep -qE "^#?MaxRetentionSec=" "$JOURNALD_CONF"; then
    sed -i 's/^#*MaxRetentionSec=.*/MaxRetentionSec=7d/' "$JOURNALD_CONF"
else
    echo "MaxRetentionSec=7d" >> "$JOURNALD_CONF"
fi

# Apply the new journald configuration
systemctl restart systemd-journald

# 11. Automating APT Cleanup
# Forces apt to automatically clean its cache and remove orphaned packages post-install
echo "Configuring apt to automatically remove downloaded packages and unused dependencies..."
cat <<EOF > /etc/apt/apt.conf.d/99-auto-clean
APT::Keep-Downloaded-Packages "false";
APT::Get::AutomaticRemove "true";
APT::Get::Purge "true";
EOF

# 12. Limiting Systemd Coredump Size
# Coredumps (crash memory dumps) can take gigabytes of space if left unchecked
echo "Configuring systemd-coredump limits..."
COREDUMP_CONF="/etc/systemd/coredump.conf"

# Ensure file and section exist before modifying
if ! [ -f "$COREDUMP_CONF" ]; then
    echo "[Coredump]" > "$COREDUMP_CONF"
fi

if grep -qE "^#?MaxUse=" "$COREDUMP_CONF"; then
    sed -i 's/^#*MaxUse=.*/MaxUse=100M/' "$COREDUMP_CONF"
else
    echo "MaxUse=100M" >> "$COREDUMP_CONF"
fi
systemctl restart systemd-coredump.socket || true

# 13. Enforcing Logrotate Compression and Shorter Retention
# Modifies global logrotate defaults to compress all logs and keep fewer backups
echo "Configuring global logrotate for shorter retention and compression..."
LOGROTATE_CONF="/etc/logrotate.conf"
if [ -f "$LOGROTATE_CONF" ]; then
    # Ensure 'compress' is active (uncomment if commented, or append if missing)
    sed -i 's/^#compress/compress/' "$LOGROTATE_CONF"
    if ! grep -q "^compress" "$LOGROTATE_CONF"; then
        echo "compress" >> "$LOGROTATE_CONF"
    fi
    
    # Change global rotation duration from the standard 4 weeks down to 2 weeks
    sed -i 's/^rotate 4/rotate 2/' "$LOGROTATE_CONF"
fi

# ==============================================================================
# FINAL OUTPUT & SUMMARY GENERATION
# ==============================================================================

# Get final disk usage
USED_AFTER_KB=$(df -kP / | tail -1 | awk '{print $3}')
FREED_KB=$((USED_BEFORE_KB - USED_AFTER_KB))

# Prevent negative output in case temporary files were generated during the run
if [ "$FREED_KB" -lt 0 ]; then
    FREED_KB=0
fi

# Convert freed space to Megabytes and Gigabytes for better readability
FREED_MB=$(awk "BEGIN {printf \"%.2f\", $FREED_KB/1024}")
FREED_GB=$(awk "BEGIN {printf \"%.2f\", $FREED_KB/1048576}")

# Gather human-readable stats for the root partition
ROOT_INFO=$(df -hP / | tail -1)
ROOT_FS=$(echo "$ROOT_INFO" | awk '{print $1}')
ROOT_TOTAL=$(echo "$ROOT_INFO" | awk '{print $2}')
ROOT_USED=$(echo "$ROOT_INFO" | awk '{print $3}')
ROOT_FREE=$(echo "$ROOT_INFO" | awk '{print $4}')
ROOT_PERCENT=$(echo "$ROOT_INFO" | awk '{print $5}')

# Setup ANSI color codes for visual formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "\n${BLUE}=================================================================${NC}"
echo -e "${GREEN}             DEEPCLEAN AND AUTO-PRUNE COMPLETE!                  ${NC}"
echo -e "${BLUE}=================================================================${NC}\n"

# Display freed space in MB, and dynamically show GB if it's over 1000MB
if [ "$FREED_KB" -gt 1024000 ]; then
    echo -e "${YELLOW}Total Space Freed During This Run:${NC} ${GREEN}${FREED_GB} GB${NC} (${FREED_MB} MB)\n"
else
    echo -e "${YELLOW}Total Space Freed During This Run:${NC} ${GREEN}${FREED_MB} MB${NC}\n"
fi

echo -e "${YELLOW}Current Disk Space Summary (Filesystem: ${CYAN}$ROOT_FS${YELLOW}):${NC}"
echo -e "  Total Size : ${BLUE}$ROOT_TOTAL${NC}"
echo -e "  Used Space : ${BLUE}$ROOT_USED${NC} (${ROOT_PERCENT})"
echo -e "  Free Space : ${GREEN}$ROOT_FREE${NC}\n"
echo -e "${BLUE}=================================================================${NC}\n"
