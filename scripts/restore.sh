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
        file="/home/${kodi_user}/.kodi/userdata/advancedsettings.xml"
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

MYSQL_USER="$(get_kodi_setting 'user')"
MYSQL_PASS="$(get_kodi_setting 'pass')"
MYSQL_HOST="$(get_kodi_setting 'host')"
MYSQL_PORT="$(get_kodi_setting 'post')"

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


#echo "Transfering Files..."
#sudo ${RCLONE_BIN} move "${RCLONE_REMOTE_PATH}/${SYSTEM_BACKUP}.tar.gz" "${HOMEDIR}" --config "${RCLONE_DATA_PATH}/rclone.conf" && tar x --extract "${SYSTEM_BACKUP}.tar.gz"
#sudo ${RCLONE_BIN} move "${RCLONE_REMOTE_PATH}/${KODIDB_BACKUP}.tar.gz" "${HOMEDIR}" --config "${RCLONE_DATA_PATH}/rclone.conf" && tar x --extract "${KODIDB_BACKUP}.tar.gz"
#sudo ${RCLONE_BIN} move "${RCLONE_REMOTE_PATH}/${KODIUSERDATA_BACKUP}.tar.gz" "${HOMEDIR}" --config "${RCLONE_DATA_PATH}/rclone.conf" && tar x --extract "${KODIUSERDATA_BACKUP}.tar.gz"

#Check for system backup and restore
if [ -d system ]; then
    cd system

    # Crontab
    [ -f crontab ] && sudo crontab crontab && rm crontab

    # Apt sources file
    if [ -f ::etc::apt::sources.list ]; then
        echo "Restoring package sources..."
        sudo apt-get --quiet --quiet update
        sudo mv ::etc::apt::sources.list /etc/apt/sources.list && sudo apt-get --quiet update
    fi

    # Install missing packages
    if [ -f .installed_packages ]; then
        #TODO: read file and install missing packages.
        echo "Installing missing packages:"

        tmp_installed_list=".temp_installed"
        sudo apt list --installed 2>/dev/null | sudo cut -d '/' -f 1 > "${tmp_installed_list}"
        while IFS= read -r package_name; do
            if ! cat "${tmp_installed_list}" | grep "^${package_name}$" > /dev/null ; then
                echo "   Installing ${package_name}..."
                #sudo apt-get --yes --quiet --quiet install ${package_name}
            fi
        done < ".installed_packages"
        rm "${tmp_installed_list}"
        rm ".installed_packages"
    fi

    for path in *; do
        dest_path="$(encode_path ${path})"
        [[ $dest_path == "${HOMEDIR}/"* ]] && do_sudo="" || do_sudo="sudo "
        if [ -d "${path}" ]; then
            echo "${do_sudo}mkdir ""${dest_path}/"""
            echo "${do_sudo}cp ""${path}/""* ""${dest_path}/"" && ${do_sudo}rm -R ""${path}/"""
        elif [ -f "${path}" ]; then
            echo "${do_sudo}mv ""${path}"" ""${dest_path}"""
        else
            echo "  ERROR: $path. Not recognized as directory or file."
        fi
    done

    cd ..
fi

if [ -f kodi_backup.sql ]; then
    echo "Restoring kodi db backups..."

    export MYSQL_PWD=$MYSQL_PASS

    cat kodi_backup.sql | mysql --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER && sudo rm -R kodi_backup.sql
fi

if [ -d userdata ]; then
    echo "Restoring kodi userdata backups..."
    cp --recursive --quiet userdata/* "${OS_DEFAULT_USER_DIR}/.kodi/userdata/"

    cd "${HOMEDIR}"
fi

cd "${CURRENT_DIR}"

echo
echo "Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
