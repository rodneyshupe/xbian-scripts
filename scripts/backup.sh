#!/usr/bin/env bash

# Uncomment the commands below to enable DEBUGGING
# exec 5> $(basename "$0" | sed -r 's|^(.*?)\.\w+$|\1|').log" # Log to file with same name as script
# #exec 5> >(logger -t $0) # Log to syslog
# BASH_XTRACEFD="5"
# PS4='$LINENO: '
# set -x

FLAG_CREATE_IMG=1 #TODO: Make this a parameter to get passed in

HOMEUSER="$(stat -c '%U' "$0")"
HOMEDIR="/home/${HOMEUSER}"
OS_DEFAULT_USER="$(getent passwd 1000 | cut -d: -f1)"
[ -z $OS_DEFAULT_USER ] && OS_DEFAULT_USER='xbian'
OS_DEFAULT_USER_DIR="/home/${OS_DEFAULT_USER}"
RCLONE_DATA_PATH="${HOMEDIR}/.config/rclone"
RCLONE_BIN="/usr/bin/rclone"
RCLONE_REMOTE_PATH="backups:/Xbian"

SYSTEM_BACKUP="system"
KODIDB_BACKUP="kodidb"
KODIUSERDATA_BACKUP="kodiuserdata"

# Function to extract the value of a node from an XML file
get_kodi_setting() {
    # Set the variables for the node and parent node names
    local node="${1:-host}"
    local parent_node="${2:-videodatabase}"
    local file="${3}"
    if [ -z ${file} ] || [ ! -f ${file} ]; then
        kodi_user="$(ps aux | grep kodi | grep -v grep | head -n1 | cut -d ' ' -f1)"
        [ -z $kodi_user ] && kodi_user="$(getent passwd 1000 | cut -d: -f1)"
        [ ! -d "/home/${kodi_user}" ] && kodi_user='xbian'
        file="/home/${kodi_user}/.kodi/userdata/advancedsettings.xml"
    fi

    if [ ! -f "$file" ]; then
        echo "$(log_prefix)Error KODI config file missing [$file]"
        exit 1
    fi

    # Set the regular expression to match the node
    local regex="<${node}>.*</${node}>"

    # If a parent node was specified, add it to the regular expression
    if [[ -n "$parent_node" ]]; then
        regex="<${parent_node}>.*${regex}.*</${parent_node}>"
    fi

    # Extract the value of the node using grep and sed
    tr '\n' ' ' <"${file}" | grep --text --only-matching --ignore-case --regexp "$regex" | sed "s/.*<${node}>\(.*\)<\/${node}>.*/\1/i"
}

function get_kodi_db_name() {
    local DB_TYPE="${1:-videodatabase}"
    local _MYSQL_HOST="${2:-$(get_kodi_setting 'host')}"
    local _MYSQL_PORT="${3:-$(get_kodi_setting 'port')}"
    local _MYSQL_USER="${4:-$(get_kodi_setting 'user')}"
    local _MYSQL_PASS="${5:-$(get_kodi_setting 'pass')}"

    local _MYSQL_DB="$(get_kodi_setting 'name' "$DB_TYPE")"
    if [ -z $_MYSQL_DB ]; then
        if [[ "$DB_TYPE" == "videodatabase" ]]; then
            _MYSQL_DB='MyVideos'
        elif [[ "$DB_TYPE" == "musicdatabase" ]]; then
            _MYSQL_DB='MyMusic'
        else
            echo "Error: Unknown database type." >&2
            exit 1
        fi
    fi

    echo $(MYSQL_PWD="$_MYSQL_PASS" mysql --skip-column-names \
                                          --user=$_MYSQL_USER \
                                          --host=$_MYSQL_HOST \
                                          --port=$_MYSQL_PORT \
                                          --execute="SELECT table_schema
                                                     FROM information_schema.TABLES
                                                     WHERE table_schema LIKE '${_MYSQL_DB}%'
                                                     GROUP BY table_schema;" \
                                        | sort | tail --lines=1)
}

MYSQL_USER="$(get_kodi_setting 'user')"
MYSQL_PASS="$(get_kodi_setting 'pass')"
MYSQL_HOST="$(get_kodi_setting 'host')"
MYSQL_PORT="$(get_kodi_setting 'port')"

SHOW_PREFIX=1
test -t 1 && SHOW_PREFIX=0
log_prefix() {
    [ $SHOW_PREFIX -eq 1 ] && echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
}

function secs_to_human() {
    #echo "$(( ${1} / 3600 ))h $(( (${1} / 60) % 60 ))m $(( ${1} % 60 ))s"
    echo "$(( ${1} / 60 ))m $(( ${1} % 60 ))s"
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

function decode_path() {
    echo "$1" | sed "s/:-homedir-:/$(echo ${HOMEDIR}/ | sed 's|\/|\\/|g')/g" | sed "s/::/\//g"
}

function encode_path {
    echo "$1" | sed "s/$(echo ${HOMEDIR}/ | sed 's|\/|\\/|g')/:-homedir-:/g" | sed "s/\//::/g"
}

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

ensure_sudo

CURRENT_DIR="$PWD"

cd "${HOMEDIR}"

if [ $FLAG_CREATE_IMG -eq 1 ]; then
    # create xbian backup
    sudo xbian-config backuphome start > /tmp/backuphome.pid

    msg="Creating xbian home backup: "
    echo -n "$(log_prefix)Creating xbian home backup: "
    # wait
    sleep 5
    count=5
    if [ ! -f /tmp/backuphome.running ]; then
        echo "$(log_prefix)"
        echo "$(log_prefix)ERROR: Error backup not started: [$IMAGE_PATH]"
        exit 1
    fi

    while [ -f /tmp/backuphome.running ]; do
        if test -t 1; then
            # Calculate the minutes and seconds
            minutes=$((count / 60))
            seconds=$((count % 60))

            # Format the timer string
            if [ "$seconds" -lt 10 ]; then
                # Add a leading zero to the seconds if necessary
                timer="$minutes:0$seconds"
            else
                timer="$minutes:$seconds"
            fi

            echo -ne "\r$msg$timer"
        fi
        sleep 1
        ((count++))
        [ $((count % 5)) -eq 0 ] && sudo xbian-config backuphome status > /dev/null
    done
    echo ""
    sleep 5
    sync; sync
fi
XBIAN_BACKUP_IMAGE="$(ls -t /xbmc-backup/xbian_backup_home_$(date +'%Y-%m-%d')*.btrfs.img.gz | head -1)"

#Create a system backup
echo "$(log_prefix)Creating backup of system files..."
TEMP_DIR=$(mktemp -d -t "${SYSTEM_BACKUP}-XXXXXXXXXX")
cd "${TEMP_DIR}"
mkdir "${SYSTEM_BACKUP}"
cd "${SYSTEM_BACKUP}"

sudo crontab -l > crontab

sudo apt list --installed 2>/dev/null | sudo cut -d '/' -f 1 > .installed_packages
sudo cp /etc/apt/sources.list ::etc::apt::sources.list

backup_files=( /etc/ssh/sshd_config \
        "${HOMEDIR}/.ssh" \
        /etc/samba/smb.conf \
        /etc/samba/shares.conf \
        /etc/fstab \
        /etc/hostname \
        /etc/hosts \
        "${HOMEDIR}/.scripts" \
        "${HOMEDIR}/.nanorc" \
        "${HOMEDIR}/.nano" \
        "${HOMEDIR}/.bashrc" \
        /usr/bin/kodi-rpc \
        "${HOMEDIR}/.config/kodi-rpc.conf" \
        "${HOMEDIR}/.config/rclone/rclone.conf" \
    )

for path in "${backup_files[@]}"; do
    if [ -e "${path}" ]; then
        if [ -d "${path}" ]; then
            mkdir "$(encode_path ${path})/"
            cp "${path}/"* "$(encode_path ${path})/"
        elif [ -f "${path}" ]; then
            cp "${path}" "$(encode_path ${path})"
        else
            echo "$(log_prefix)  ERROR: $path. Not recognized as directory or file."
        fi
    else
        echo "$(log_prefix)  ERROR: File (${path}) Missing"
    fi
done

cd ..
sudo tar  --gzip --create --file="${HOMEDIR}/${SYSTEM_BACKUP}.tar.gz" .
cd "${HOMEDIR}"
sudo rm -R "${TEMP_DIR}"

echo "$(log_prefix)Archiving kodi db backups..."
TEMP_DIR=$(mktemp -d -t "${KODIDB_BACKUP}-XXXXXXXXXX")
cd "${TEMP_DIR}"
mkdir "${KODIDB_BACKUP}"

MYSQL_KODI_VIDEOS_DB=$(get_kodi_db_name "videodatabase" "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}")
MYSQL_KODI_MUSIC_DB=$(get_kodi_db_name "musicdatabase" "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}")

echo "$(log_prefix)  Music [$MYSQL_KODI_VIDEOS_DB] and Video [$MYSQL_KODI_MUSIC_DB] DBS..."

export MYSQL_PWD=$MYSQL_PASS
mysqldump \
    --user=$MYSQL_USER \
    --host=$MYSQL_HOST \
    --port=$MYSQL_PORT \
    --add-drop-database \
    --add-drop-table \
    --add-drop-trigger \
    --routines \
    --triggers \
    --databases $MYSQL_KODI_VIDEOS_DB $MYSQL_KODI_MUSIC_DB \
    > kodi_backup.sql

echo "$(log_prefix)  User [$MYSQL_USER] specific..."

mysqldump \
    --user=$MYSQL_USER \
    --host=$MYSQL_HOST \
    --port=$MYSQL_PORT \
    --skip-add-drop-table
    --no-create-info \
    --databases mysql
    --tables user 
    --where="User='$MYSQL_USER'" \
    > kodi_user_backup.sql

sudo tar --gzip --create --file="${HOMEDIR}/${KODIDB_BACKUP}.tar.gz" .

cd "${HOMEDIR}"
sudo rm -R "${TEMP_DIR}"

echo "$(log_prefix)Archiving kodi userdata backups..."
TEMP_DIR=$(mktemp -d -t "${KODIUSERDATA_BACKUP}-XXXXXXXXXX")
cd "${TEMP_DIR}"
mkdir "userdata"
rsync --archive --quiet "${OS_DEFAULT_USER_DIR}/.kodi/userdata/" "${TEMP_DIR}/userdata" --exclude=Thumbnails
rm "${TEMP_DIR}"/userdata/Database/Textures13.db 2>/dev/null
rm -R "${TEMP_DIR}"/userdata/*.bak 2>/dev/null

sudo tar --gzip --create --file="${HOMEDIR}/${KODIUSERDATA_BACKUP}.tar.gz" .

cd "${HOMEDIR}"
sudo rm -R "${TEMP_DIR}"


echo "$(log_prefix)Cycling Backups..."
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.2.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.1.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.1.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.1.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.1.img.gz" "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.2.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${SYSTEM_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.1.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${KODIDB_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.1.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${KODIUSERDATA_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.1.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/xbian_backup_home.btrfs.img.gz" "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.1.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

echo "$(log_prefix)Transfering Files..."
sudo ${RCLONE_BIN} move "${HOMEDIR}/${SYSTEM_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} move "${HOMEDIR}/${KODIDB_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} move "${HOMEDIR}/${KODIUSERDATA_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} copyto "$XBIAN_BACKUP_IMAGE" "${RCLONE_REMOTE_PATH}/xbian_backup_home.btrfs.img.gz" --config "${RCLONE_DATA_PATH}/rclone.conf"

cd "${CURRENT_DIR}"

echo
echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
