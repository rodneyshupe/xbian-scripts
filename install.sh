#!/usr/bin/env bash

GITHUB_REPO_URL="https://raw.githubusercontent.com/rodneyshupe/xbian-scripts/main/"

FLAG_FORCE=0
[ $# -eq 1 ] && [ "$1" == "-f" ] && FLAG_FORCE=1

CMD_PATH='/usr/local/bin' # changed from '/usr/bin'

echo "This script requires sudo permissions."
sudo true

# Update and install essentials
echo "Update and Install Essentials"
sudo apt-get --quiet --quiet update \
    && sudo apt-get --yes --quiet --quiet upgrade \
    && sudo apt-get --yes --quiet --quiet install screen cron zip unzip wget curl nano jq logrotate mariadb-client

# Install rclone
echo "Install rclone..."
curl -sSL https://rclone.org/install.sh | sudo bash

# Install `kodi-rpc`
echo "Install kodi-rpc script..."
wget --quiet --output-document=/tmp/kodi-rpc https://raw.githubusercontent.com/tadly/kodi-rpc/master/kodi-rpc \
    && bash /tmp/kodi-rpc --install \
    && sudo chmod +x /usr/bin/kodi-rpc \
rm /tmp/kodi-rpc 2>/dev/null

echo "    Write config file..."
[ ! -f "$HOME/.config/kodi-rpc.conf" ] && cat > "$HOME/.config/kodi-rpc.conf" <<EOF
# Host/IP the web server is running on
HOST=localhost

# Port the web server is running on
PORT=8080

# Username (leave blank if not required)
USER="kodi"

# Password (leave blank if not required)
PASS="kodi"
EOF
[ ! -f "/usr/bin/kodi-rpc.conf" ] && sudo cp "$HOME/.config/kodi-rpc.conf" /usr/bin/kodi-rpc.conf

# Create Directories
echo "Create Directories..."
mkdir -p "$HOME/.ssh" 2>/dev/null
mkdir -p "$HOME/.scripts" 2>/dev/null
mkdir -p "$HOME/.nano" 2>/dev/null
mkdir -p "$HOME/.config/rclone" 2>/dev/null
# Make Log Directory
sudo mkdir -p /var/log/$USER 2>/dev/null

# Setup Logrotate
echo "Setup Logrotate..."
[ ! -f "/etc/logrotate.d/$USER" ] && sudo tee "/etc/logrotate.d/$USER" > /dev/null <<EOF
/var/log/$USER/kodi-removed-watched.log {
    rotate 4
    weekly
    missingok
    notifempty
}
/var/log/$USER/kodi-episode-check.log {
    rotate 4
    weekly
    missingok
    notifempty
}
/var/log/$USER/sonarr-unmonitor-watched.log {
    rotate 4
    weekly
    missingok
    notifempty
}
/var/log/$USER/kodi-detail-check.log {
    rotate 4
    weekly
    missingok
    notifempty
}
/var/log/$USER/backup.log {
    rotate 4
    weekly
    missingok
    notifempty
}
EOF

# Copy Utility Commands
echo "Copy Utility Commands..."
curl -sSL "$GITHUB_REPO_URL/scripts/restart-kodi.sh" | sudo tee "$CMD_PATH/restart-kodi" > /dev/null
curl -sSL "$GITHUB_REPO_URL/scripts/sys-status.sh" | sudo tee "$CMD_PATH/sys-status" > /dev/null
curl -sSL "$GITHUB_REPO_URL/scripts/versions.sh" | sudo tee "$CMD_PATH/versions" > /dev/null
sudo chmod +x "$CMD_PATH/restart-kodi"
sudo chmod +x "$CMD_PATH/sys-status"
sudo chmod +x "$CMD_PATH/versions"

# Copy Sample `.env` Files
echo "Copy Sample .env Files..."
[ ! -f "$HOME/.config/kodi-episode-check.env" ]  && curl -sSL "$GITHUB_REPO_URL/sample-configs/kodi-episode-check.env"  > "$HOME/.config/kodi-episode-check.env"
[ ! -f "$HOME/.config/kodi-remove-watched.env" ] && curl -sSL "$GITHUB_REPO_URL/sample-configs/kodi-remove-watched.env" > "$HOME/.config/kodi-remove-watched.env"
[ ! -f "$HOME/.config/sonarr-unmonitor-watched.env" ] && curl -sSL "$GITHUB_REPO_URL/sample-configs/sonarr-unmonitor-watched.env"   > "$HOME/.config/sonarr-unmonitor-watched.env"

# Copy Script Files
echo "Copy Script Files..."
curl -sSL "$GITHUB_REPO_URL/scripts/kodi-episode-check.sh"  > "$HOME/.scripts/kodi-episode-check.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/kodi-detail-check.sh"   > "$HOME/.scripts/kodi-detail-check.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/kodi-remove-watched.sh" > "$HOME/.scripts/kodi-remove-watched.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/sonarr-unmonitor-watched.sh" > "$HOME/.scripts/sonarr-unmonitor-watched.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/backup.sh"  > "$HOME/.scripts/backup.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/backup-image.sh"  > "$HOME/.scripts/backup-image.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/restore.sh" > "$HOME/.scripts/restore.sh"
curl -sSL "$GITHUB_REPO_URL/scripts/pretrip.sh" > "$HOME/.scripts/pretrip.sh"

chmod +x "$HOME/.scripts"/*

[ -f "$HOME/.scripts/backup.sh" ] && [ ! -f "$HOME/backup" ] && ln -s "$HOME/.scripts/backup.sh" "$HOME/backup"
[ -f "$HOME/.scripts/restore.sh" ] && [ ! -f "$HOME/restore" ] && ln -s "$HOME/.scripts/restore.sh" "$HOME/restore"
[ -f "$HOME/.scripts/pretrip.sh" ] && [ ! -f "$HOME/pretrip" ] && ln -s "$HOME/.scripts/pretrip.sh" "$HOME/pretrip"

# Copy motd
[ ! -f /etc/motd.ori ] && sudo cp /etc/motd /etc/motd.ori
echo '#!/bin/bash' | sudo tee /etc/update-motd.d/14-xbian > /dev/null \
    && echo "echo '" | sudo tee --append /etc/update-motd.d/14-xbian > /dev/null \
    && cat /etc/motd.ori | sudo tee --append /etc/update-motd.d/14-xbian > /dev/null \
    && echo "'" | sudo tee --append /etc/update-motd.d/14-xbian > /dev/null \
    && sudo chmod +x /etc/update-motd.d/14-xbian \
    && [ -f /etc/motd  ] && sudo rm /etc/motd

curl -sSL "$GITHUB_REPO_URL/scripts/update-motd.d/15-logo.sh" | sudo tee /etc/update-motd.d/15-logo > /dev/null
curl -sSL "$GITHUB_REPO_URL/scripts/update-motd.d/20-status.sh" | sudo tee /etc/update-motd.d/20-status > /dev/null
sudo chmod +x /etc/update-motd.d/15-logo
sudo chmod +x /etc/update-motd.d/20-status

# To run the scripts:
# sudo $HOME/.scripts/kodi-remove-watched.sh | sudo tee -a /var/log/$USER/kodi-removed-watched.log
# sudo $HOME/.scripts/kodi-episode-check.sh | sudo tee -a /var/log/$USER/kodi-episode-check.log
# sudo $HOME/.scripts/sonarr-unmonitor-watched.sh | sudo tee -a /var/log/$USER/sonarr-unmonitor-watched.log
# sudo $HOME/.scripts/kodi-detail-check.sh | sudo tee -a /var/log/$USER/kodi-detail-check.log
# sudo $HOME/.scripts/backup.sh | sudo tee -a /var/log/$USER/backup.log
