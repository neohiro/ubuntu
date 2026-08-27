#!/bin/bash
# Comprehensive Ubuntu Disk Cleanup Script

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

# 4. Apt Cache and Orphaned Packages
# Clears the local repository of retrieved package files and removes unused dependencies
echo "Cleaning apt cache and unused packages..."
apt-get clean -y
apt-get autoremove --purge -y

# 5. Old Snap Revisions
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

# 6. Crash Reports
echo "Removing old crash reports..."
rm -rf /var/crash/*

echo "Cleanup complete! Current disk space:"
df -h /
