#!/usr/bin/env bash

# Uncomment the commands below to enable DEBUGGING
# exec 5> $(basename "$0" | sed -r 's|^(.*?)\.\w+$|\1|').log" # Log to file with same name as script
# #exec 5> >(logger -t $0) # Log to syslog
# BASH_XTRACEFD="5"
# PS4='$LINENO: '
# set -x

HOMEUSER="$(stat -c '%U' "$0")"
HOMEDIR="/home/${HOMEUSER}"
OS_DEFAULT_USER="$(getent passwd 1000 | cut -d: -f1)"
[ -z $OS_DEFAULT_USER ] && OS_DEFAULT_USER='xbian'
OS_DEFAULT_USER_DIR="/home/${OS_DEFAULT_USER}"

BACKUP_PATH="/mnt/storage/backups/xbian"
RCLONE_DATA_PATH="${HOMEDIR}/.config/rclone"
RCLONE_BIN="/usr/bin/rclone"
RCLONE_REMOTE_PATH="backups:/Xbian"

function secs_to_human() {
    #echo "$(( ${1} / 3600 ))h $(( (${1} / 60) % 60 ))m $(( ${1} % 60 ))s"
    echo "$(( ${1} / 60 ))m $(( ${1} % 60 ))s"
}

SHOW_PREFIX=1
test -t 1 && SHOW_PREFIX=0
log_prefix() {
    [ $SHOW_PREFIX -eq 1 ] && echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
}

function ensure_sudo() {
    if sudo -n true 2>/dev/null; then
        true
    else
        echo
        echo "$(log_prefix)ERROR: This script requires admin access. Rerun with sudo."
        exit 1;
    fi
}

ensure_sudo

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

CURRENT_DIR="$PWD"

cd "${HOMEDIR}"

#Create a backup image

IMAGE_NAME="$(hostname --all-fqdns | tr '[:upper:]' '[:lower:]')"
[ -z "${IMAGE_NAME}" ] && IMAGE_NAME="$(hostname --fqdn)"
[ -z "${IMAGE_NAME}" ] && IMAGE_NAME="$(uname -n)"
IMAGE_NAME="$(echo "$IMAGE_NAME" | sed -e 's/\.private//' -e 's/ //g' -e 's/\./_/g')"
[[ "$IMAGE_NAME" == "xbian" ]] && IMAGE_NAME="xbian_image"
[[ "$IMAGE_NAME" != "xbian"* ]] && IMAGE_NAME="xbian_$IMAGE_NAME"
IMAGE_FILE="$IMAGE_NAME.$(date +'%Y-%m-%d').img"
IMAGE_PATH="$BACKUP_PATH/$IMAGE_FILE"
ARCHIVE_PATH="$BACKUP_PATH/$IMAGE_FILE.gz"

xbiancopy_log="/tmp/xbiancopy.log"
rm $xbiancopy_log >/dev/null 2>&1
sudo xbian-config xbiancopy start /dev/root "file:$IMAGE_PATH" > /tmp/xbiancopy.pid
if [ $? -ne 0 ]; then
    test -t 1 && echo
    echo "$(log_prefix)ERROR: Error ($pid) creating image: [$IMAGE_PATH]"
    exit 1;
fi

echo -n "$(log_prefix)Creating image to $IMAGE_FILE..."
# Wait
#while [ $(sudo xbian-config xbiancopy status) -ge 0 ]; do
sleep 5
if [ -f "$xbiancopy_log" ]; then
    success_msg="Operation sucessfully completed"
    fail_msg="Operation failed with error"
    while [ $(grep -e "$success_msg" -e "$fail_msg" "$xbiancopy_log" > /dev/null; echo $?) -ne 0 ]; do
        test -t 1 && echo -n "."
        sleep 5
    done
    echo ""
    if [ $(grep -e "$fail_msg" "$xbiancopy_log" > /dev/null; echo $?) -eq 0 ]; then
        echo "$(log_prefix)ERROR: $(grep -e "$fail_msg" "$xbiancopy_log"): [$IMAGE_PATH]"
        exit 1
    fi
    sleep 5
fi

if [ ! -f "$IMAGE_PATH" ]; then
    test -t 1 && echo
    echo "$(log_prefix)ERROR: Failed to create image: [$IMAGE_PATH]"
    exit 1;
fi

echo "$(log_prefix)Image created [$(ls $IMAGE_PATH -alh | cut -d " " -f5)]" # NOTE: Image can be checked using `sudo sfdisk -uS -N1 -f -q -l $IMAGE_PATH`
echo "$(log_prefix)Shrinking image..."
if gzip --quiet "$IMAGE_PATH"; then
    if [ ! -f $ARCHIVE_PATH ]; then
        test -t 1 && echo
        echo "$(log_prefix)ERROR: Archive nmissing: [$ARCHIVE_PATH]"
        exit 1;
    fi
    echo "$(log_prefix)Image shrink complete: $ARCHIVE_PATH [$(ls $ARCHIVE_PATH -alh | cut -d " " -f5)]"
else
    test -t 1 && echo
    echo "$(log_prefix)ERROR: Error shrinking archive: [$ARCHIVE_PATH]"
    exit 1;
fi

echo "$(log_prefix)Cycling Backups..."
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.2.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.1.img.gz" "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.2.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${IMAGE_NAME}.img.gz" "${RCLONE_REMOTE_PATH}/Past/${IMAGE_NAME}.1.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

echo "$(log_prefix)Transfering Files..."
sudo ${RCLONE_BIN} copyto "${ARCHIVE_PATH}" "${RCLONE_REMOTE_PATH}"/"${IMAGE_NAME}.img.gz" --config "${RCLONE_DATA_PATH}/rclone.conf"

cd "${CURRENT_DIR}"

test -t 1 && echo
echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
