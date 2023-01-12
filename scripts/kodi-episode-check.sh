#!/usr/bin/env bash

ENVIORMENT_FILE="$(dirname "$0")/$(basename "$0" | cut -f 1 -d '.').env"
[ ! -f "$ENVIORMENT_FILE" ] && ENVIORMENT_FILE="/home/$(stat -c '%U' "$0")/.config/$(basename "$0" | cut -f 1 -d '.').env"
[ -f "$ENVIORMENT_FILE" ] && source $ENVIORMENT_FILE

REMOTE_PATH="${3:-$REMOTE_PATH}"
LOCAL_PATH="${4:-$LOCAL_PATH}"

SHOW_PREFIX=1
test -t 1 && SHOW_PREFIX=0
log_prefix() {
    [ $SHOW_PREFIX -eq 1 ] && echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
}

secs_to_human() {
    #echo "$(( ${1} / 3600 ))h $(( (${1} / 60) % 60 ))m $(( ${1} % 60 ))s"
    echo "$(( ${1} / 60 ))m $(( ${1} % 60 ))s"
}

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
        echo "Error KODI config file missing [$file]"
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

MYSQL_HOST="$(get_kodi_setting 'host')"
MYSQL_PORT="$(get_kodi_setting 'port')"
MYSQL_USER="$(get_kodi_setting 'user')"
MYSQL_PASS="$(get_kodi_setting 'pass')"

TMP_FILELIST_LOCAL="/tmp/tvshowslocal.lst"
TMP_FILELIST_LIBRARY="/tmp/tvshowslibrary.lst"

# Check for kodi-rpc being installed and configured
kodi-rpc --version > /dev/null 2>&1 || { echo >&2 "ERROR: kodi-rpc Required but not installed.  Aborting."; exit 1; }
[ "$(kodi-rpc JSONRPC.Ping | jq -r .result)" == "pong" ] || { echo "ERROR: kodi-rpc Installed but not configured.  Aborting."; exit 1; }

# Check for mysql being installed
mysql --version > /dev/null 2>&1 || { echo >&2 "ERROR: mysql Required but not installed.  Aborting."; exit 1; }

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

echo "$(log_prefix)Pulling file list from server..."
find "${LOCAL_PATH}" -type f \
| grep -iE "\.webm$|\.flv$|\.vob$|\.ogg$|\.ogv$|\.drc$|\.gifv$|\.mng$|\.avi$|\.mov$|\.qt$|\.wmv$|\.yuv$|\.rm$|\.rmvb$|/.asf$|\.amv$|\.mp4$|\.m4v$|\.mp4$|\.m.?v$|\.svi$|\.3gp$|\.flv$|\.f4v$" \
| sed -e "s|^$LOCAL_PATH|$REMOTE_PATH|g" > $TMP_FILELIST_LOCAL

MYSQL_KODI_VIDEOS_DB=$(get_kodi_db_name "videodatabase" "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}")

echo "$(log_prefix)Pulling file list from library [$MYSQL_KODI_VIDEOS_DB]..."
export MYSQL_PWD=$MYSQL_PASS
mysql --skip-column-names \
  --user=$MYSQL_USER \
  --host=$MYSQL_HOST \
  --port=$MYSQL_PORT \
  --database=$MYSQL_KODI_VIDEOS_DB \
  --batch \
  --execute="SELECT CONCAT(strPath, strFilename) FROM files f JOIN path p ON p.idPath = f.idPath;" \
  > $TMP_FILELIST_LIBRARY

echo "$(log_prefix)Scan missing..."
STREAM_MISSING=0
while read PATH_LINE; do
    if ! grep -Fxq "$PATH_LINE" "$TMP_FILELIST_LIBRARY"; then
        echo "$(log_prefix)Calling Kodi API to Scan $(basename "${PATH_LINE}")..."
        kodi-rpc VideoLibrary.Scan directory "$(dirname "${PATH_LINE}")" showdialogs false > /dev/null
        sleep 5s
    fi
done < "${TMP_FILELIST_LOCAL}"

rm "${TMP_FILELIST_LOCAL}"
rm "${TMP_FILELIST_LIBRARY}"

echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
