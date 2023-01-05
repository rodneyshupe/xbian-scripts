#!/usr/bin/env bash

HOMEUSER="$(stat -c '%U' "$0")"
HOMEDIR="/home/${HOMEUSER}"
OS_DEFAULT_USER="$(getent passwd 1000 | cut -d: -f1)"
[ -z $OS_DEFAULT_USER ] && OS_DEFAULT_USER='xbian'
OS_DEFAULT_USER_DIR="/home/${OS_DEFAULT_USER}"
RCLONE_DATA_PATH="${HOMEDIR}/.config/rclone"
RCLONE_BIN="/usr/bin/rclone"
RCLONE_REMOTE_PATH="backups:/Xbian"

function secs_to_human() {
    #echo "$(( ${1} / 3600 ))h $(( (${1} / 60) % 60 ))m $(( ${1} % 60 ))s"
    echo "$(( ${1} / 60 ))m $(( ${1} % 60 ))s"
}

function ensure_sudo() {
    if sudo -n true 2>/dev/null; then
        true
    else
        echo
        echo -ne "This script requires admin access. Please enter your Admin "
        sudo true
        if [ $? -eq 0 ]; then
            true
        else
            false
        fi
    fi
}

START_SEC=$(date +%s)
echo "Start Time: $(date)"

ensure_sudo

CURRENT_DIR="$PWD"

cd "${HOMEDIR}"

#Create a backup image

echo "Create xbian image backup..."
IMAGE_NAME="xbian_$HOMEUSER"
IMAGE_DEST="file:/mnt/storage/backups/xbian/${IMAGE_NAME}.img"
xbian-config xbiancopy start /dev/root "${IMAGE_DEST}"
#TODO: Wait


echo "Cycling Backups..."
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.2.img" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.1.img" "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.2.img" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${IMAGE_NAME}.img" "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.1.img" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

echo "Transfering Files..."
sudo ${RCLONE_BIN} copy "${IMAGE_DEST}" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"

cd "${CURRENT_DIR}"

echo
echo "Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
