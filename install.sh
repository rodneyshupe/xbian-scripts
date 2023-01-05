#!/usr/bin/env bash

GITHUB_REPO_URL="https://raw.githubusercontent.com/rodneyshupe/xbian-scripts/main/"

FLAG_FORCE=0
[ $# -eq 1 ] && [ "$1" == "-f" ] && FLAG_FORCE=1

echo "This script requires sudo permissions."
sudo true

# Update and install esentials
sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get -y install cron htop jq curl zip unzip logrotate mariadb-client

# Install rclone
echo "Install rclone..."
curl -sS https://rclone.org/install.sh | sudo bash

# Install `kodi-rpc`
echo "Install script..."
wget --quiet --output-document=/tmp/kodi-rpc https://raw.githubusercontent.com/tadly/kodi-rpc/master/kodi-rpc \
  && bash /tmp/kodi-rpc --install \
  && sudo chmod +x /usr/bin/kodi-rpc \
  && rm /tmp/kodi-rpc

echo "    Write config file..."
[ ! -f "$HOME/.config/kodi-rpc.conf" ]  && cat > "$HOME/.config/kodi-rpc.conf" <<EOF
# Host/IP the web server is running on
HOST=localhost

# Port the web server is running on
PORT=8080

# Username (leave blank if not required)
USER="kodi"

# Password (leave blank if not required)
PASS="kodi"
EOF
sudo cp "$HOME/.config/kodi-rpc.conf" /usr/bin/kodi-rpc.conf

# Create Directories
echo "Create Directories..."
mkdir -p "$HOME/.ssh" 2>/dev/null
mkdir -p "$HOME/.scripts" 2>/dev/null
mkdir -p "$HOME/.nano" 2>/dev/null
mkdir -p "$HOME/.config/rclone" 2>/dev/null
# Make Log Directory
sudo mkdir -p /var/log/milliways 2>/dev/null

# Copy Utility Commands
echo "Copy Utility Commands..."
curl -sS "$GITHUB_REPO_URL/scripts/restart-kodi.sh" | sudo tee /usr/bin/restart-kodi > /dev/null
curl -sS "$GITHUB_REPO_URL/scripts/sys-status.sh" | sudo tee /usr/bin/sys-status > /dev/null
curl -sS "$GITHUB_REPO_URL/scripts/version.sh" | sudo tee /usr/bin/version > /dev/null
sudo chmod +x /usr/bin/restart-kodi
sudo chmod +x /usr/bin/sys-status
sudo chmod +x /usr/bin/version

# Copy Sample `.env` Files
echo "Copy Sample `.env` Files..."
[ ! -f "$HOME/.config/kodi-episode-check.env" ]  && curl "$GITHUB_REPO_URL/sample-configs/kodi-episode-check.env"  "$HOME/.config/kodi-episode-check.env"
[ ! -f "$HOME/.config/kodi-detail-check.env" ]   && curl "$GITHUB_REPO_URL/sample-configs/kodi-detail-check.env"   "$HOME/.config/kodi-detail-check.env"
[ ! -f "$HOME/.config/kodi-remove-watched.env" ] && curl "$GITHUB_REPO_URL/sample-configs/kodi-remove-watched.env" "$HOME/.config/kodi-remove-watched.env"

# Copy Script Files
echo "Copy Script Files..."
curl -sS "$GITHUB_REPO_URL/scripts/kodi-episode-check.sh"  > "$HOME/.scripts/kodi-episode-check.sh"
curl -sS "$GITHUB_REPO_URL/scripts/kodi-detail-check.sh"   > "$HOME/.scripts/kodi-detail-check.sh"
curl -sS "$GITHUB_REPO_URL/scripts/kodi-remove-watched.sh" > "$HOME/.scripts/kodi-remove-watched.sh"
curl -sS "$GITHUB_REPO_URL/scripts/sonarr-unmonitor-watched.sh" > "$HOME/.scripts/sonarr-unmonitor-watched.sh"
curl -sS "$GITHUB_REPO_URL/scripts/backup.sh"  > "$HOME/.scripts/backup.sh"
curl -sS "$GITHUB_REPO_URL/scripts/restore.sh" > "$HOME/.scripts/restore.sh"
curl -sS "$GITHUB_REPO_URL/scripts/pretrip.sh" > "$HOME/.scripts/pretrip.sh"

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
    && sudo rm /etc/motd

curl -sS "$GITHUB_REPO_URL/scripts/update-motd.d/15-logo.sh" | sudo tee /etc/update-motd.d/15-logo > /dev/null
curl -sS "$GITHUB_REPO_URL/scripts/update-motd.d/20-status.sh" | sudo tee /etc/update-motd.d/20-status > /dev/null
sudo chmod +x /etc/update-motd.d/15-logo
sudo chmod +x /etc/update-motd.d/20-status
