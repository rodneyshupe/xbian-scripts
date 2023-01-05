#!/usr/bin/env bash

HOMEUSER="$(stat -c '%U' "$0")"
HOMEDIR="/home/${HOMEUSER}"
OS_DEFAULT_USER_DIR="/home/xbian"
RCLONE_DATA_PATH="${HOMEDIR}/.config/rclone"
RCLONE_BIN="/usr/bin/rclone"
RCLONE_REMOTE_PATH="backups:/Xbian"

SYSTEM_BACKUP="system"
KODIDB_BACKUP="kodidb"
KODIUSERDATA_BACKUP="kodiuserdata"

MYSQL_USER=kodi
MYSQL_PASS=kodi

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

function decode_path() {
  echo "$1" | sed "s/:-homedir-:/$(echo ${HOMEDIR}/ | sed 's|\/|\\/|g')/g" | sed "s/::/\//g"
}

function encode_path {
  echo "$1" | sed "s/$(echo ${HOMEDIR}/ | sed 's|\/|\\/|g')/:-homedir-:/g" | sed "s/\//::/g"
}

START_SEC=$(date +%s)
echo "Start Time: $(date)"

ensure_sudo

CURRENT_DIR="$PWD"

cd "${HOMEDIR}"


#Create a system backup

echo "Creating backup of system files..."
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
#/usr/bin/kodi-update \
#TODO: Implement new kodi-remove-watched \
#/usr/bin/kodi-remove-watched \

for path in "${backup_files[@]}"; do
  if [ -e "${path}" ]; then
    if [ -d "${path}" ]; then
      mkdir "$(encode_path ${path})/"
      cp "${path}/"* "$(encode_path ${path})/"
    elif [ -f "${path}" ]; then
      cp "${path}" "$(encode_path ${path})"
    else
      echo "  ERROR: $path. Not recognized as directory or file."
    fi
  else
    echo "  ERROR: File (${path}) Missing"
  fi
done

cd ..
sudo tar  --gzip --create --file="${HOMEDIR}/${SYSTEM_BACKUP}.tar.gz" .
cd "${HOMEDIR}"
sudo rm -R "${TEMP_DIR}"

echo "Archiving kodi db backups..."
TEMP_DIR=$(mktemp -d -t "${KODIDB_BACKUP}-XXXXXXXXXX")
cd "${TEMP_DIR}"
mkdir "${KODIDB_BACKUP}"

export MYSQL_PWD=$MYSQL_PASS

LATEST_DB_QUERY="SELECT table_schema FROM information_schema.TABLES WHERE table_schema LIKE 'MyVideos%' GROUP BY table_schema;"
MYSQL_KODI_VIDEOS_DB=$(mysql --skip-column-names \
                             --user=$MYSQL_USER \
                             --execute="$LATEST_DB_QUERY" \
                       | sort | tail --lines=1)

LATEST_DB_QUERY="SELECT table_schema FROM information_schema.TABLES WHERE table_schema LIKE 'MyMusic%' GROUP BY table_schema;"
MYSQL_KODI_MUSIC_DB=$(mysql --skip-column-names \
                             --user=$MYSQL_USER \
                             --execute="$LATEST_DB_QUERY" \
                      | sort | tail --lines=1)

mysqldump --user=$MYSQL_USER \
          --databases $MYSQL_KODI_VIDEOS_DB $MYSQL_KODI_MUSIC_DB \
          > kodi_backup.sql

sudo tar --gzip --create --file="${HOMEDIR}/${KODIDB_BACKUP}.tar.gz" .

cd "${HOMEDIR}"
sudo rm -R "${TEMP_DIR}"


echo "Archiving kodi userdata backups..."
TEMP_DIR=$(mktemp -d -t "${KODIUSERDATA_BACKUP}-XXXXXXXXXX")
cd "${TEMP_DIR}"
mkdir "userdata"
rsync --archive --quiet "${OS_DEFAULT_USER_DIR}/.kodi/userdata/" "${TEMP_DIR}/userdata" --exclude=Thumbnails
rm "${TEMP_DIR}"/userdata/Database/Textures13.db 2>/dev/null
rm -R "${TEMP_DIR}"/userdata/*.bak 2>/dev/null

sudo tar --gzip --create --file="${HOMEDIR}/${KODIUSERDATA_BACKUP}.tar.gz" .

cd "${HOMEDIR}"
sudo rm -R "${TEMP_DIR}"


echo "Cycling Backups..."
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
#sudo ${RCLONE_BIN} deletefile "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.2.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.1.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.1.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.1.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.2.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
#sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.1.img.gz" "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.2.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${SYSTEM_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${SYSTEM_BACKUP}.1.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${KODIDB_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIDB_BACKUP}.1.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/${KODIUSERDATA_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}/Past/${KODIUSERDATA_BACKUP}.1.tar.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"
#sudo ${RCLONE_BIN} moveto "${RCLONE_REMOTE_PATH}/"xbian_backup_home_*.btrfs.img.gz "${RCLONE_REMOTE_PATH}/Past/xbian_backup_home.btrfs.1.img.gz" --quiet --config "${RCLONE_DATA_PATH}/rclone.conf"

echo "Transfering Files..."
sudo ${RCLONE_BIN} move "${HOMEDIR}/${SYSTEM_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} move "${HOMEDIR}/${KODIDB_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"
sudo ${RCLONE_BIN} move "${HOMEDIR}/${KODIUSERDATA_BACKUP}.tar.gz" "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"
#sudo ${RCLONE_BIN} copy /xbmc-backup/xbian_backup_home_*.btrfs.img.gz "${RCLONE_REMOTE_PATH}" --config "${RCLONE_DATA_PATH}/rclone.conf"

cd "${CURRENT_DIR}"

echo
echo "Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
