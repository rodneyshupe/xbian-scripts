#!/usr/bin/env bash

ENVIORMENT_FILE= "$(dirname "$0")/$(basename "$0" | cut -f 1 -d '.').env"
[ ! -f "$ENVIORMENT_FILE" ] $ENVIORMENT_FILE="/home/$(stat -c '%U' "$0")/.config/$(basename "$0" | cut -f 1 -d '.').env"
[ -f "$ENVIORMENT_FILE" ] source $ENVIORMENT_FILE

SONARR_API_URL="${1:-$SONARR_API_URL}"
SONARR_API_KEY="${2:-$SONARR_API_KEY}"

log_prefix() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
}

function secs_to_human() {
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

function get_kodi_myvideo_db() {
    local _MYSQL_HOST="${1:-$(get_kodi_setting 'host')}"
    local _MYSQL_PORT="${2:-$(get_kodi_setting 'port')}"
    local _MYSQL_USER="${3:-$(get_kodi_setting 'user')}"
    local _MYSQL_PASS="${4:-$(get_kodi_setting 'pass')}"

    echo $(MYSQL_PWD="$_MYSQL_PASS" mysql --skip-column-names \
                                          --user=$_MYSQL_USER \
                                          --host=$_MYSQL_HOST \
                                          --port=$_MYSQL_PORT \
                                          --execute="SELECT table_schema
                                                     FROM information_schema.TABLES
                                                     WHERE table_schema LIKE 'MyVideos%'
                                                     GROUP BY table_schema;" \
                                        | sort | tail --lines=1)
}

function mysql_query() {
    local _QUERY="$1"
    local _MYSQL_HOST="${2:-$(get_kodi_setting 'host')}"
    local _MYSQL_PORT="${3:-$(get_kodi_setting 'port')}"
    local _MYSQL_USER="${4:-$(get_kodi_setting 'user')}"
    local _MYSQL_PASS="${5:-$(get_kodi_setting 'pass')}"

    MYSQL_PWD="$_MYSQL_PASS" \
    mysql --skip-column-names \
        --user=$_MYSQL_USER \
        --host=$_MYSQL_HOST \
        --port=$_MYSQL_PORT \
        --database="$(get_kodi_myvideo_db "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}")" \
        --execute="${_QUERY}"
}

function get_watched_episodes() {
    local SQL_EXCLUDE="%/TV_Archive/%"
    local LAST_SCAN='2010-01-01'
    if [ -f "${LASTSCAN_FILE}" ]; then
        LAST_SCAN=$(cat "${LASTSCAN_FILE}")
    fi

    mysql_query "SELECT t.c00, e.c00
                FROM episode e
                JOIN files f ON f.idFile = e.idFile
                JOIN tvshow t ON t.idShow =e.idShow
                JOIN path p ON p.idPath = f.idPath
                WHERE f.playCount > 0
                    AND lastPlayed >= '$LAST_SCAN'
                    AND LENGTH(e.c00)>0
                    AND p.strPath NOT LIKE '$SQL_EXCLUDE'"
}

function all_series_json {
    echo "$(curl --header "Content-Type: application/json" \
                --get \
                --data "apikey=${SONARR_API_KEY}" \
                --silent \
                --request GET "${SONARR_API_URL}/series")"
}

function unmonitor_episode() {
    local _SERIES_NAME="$1"
    local _EPISODE_NAME="$2"
    local _ALL_SERIES_JSON="${3:-$(all_series_json)}"

    local SERIES_ID=$(echo "${_ALL_SERIES_JSON}" |  jq ".[] | select(.title==\"${_SERIES_NAME}\") | .id")

    local EPISODE_ID=$(curl --header "Content-Type: application/json" \
                            --get \
                            --data "apikey=${SONARR_API_KEY}" \
                            --data "seriesId=${SERIES_ID}" \
                            --silent \
                            --request GET "${SONARR_API_URL}/episode" \
                        | jq ".[] | select(.title==\"${_EPISODE_NAME}\") | .id" | tail --lines=1)

    if [ -z $EPISODE_ID ]; then
        echo "$(log_prefix)ERROR: Missing Episode Id for Series Id: ${SERIES_ID}. Skipping."
    else
        local TEMP_EPISODE_JSON_FILE="$(mktemp --tmpdir -- tmp.json.XXXXXXXXXX)"
        echo "$(log_prefix)Get episode JSON for Series Id: ${SERIES_ID}  Episode Id: ${EPISODE_ID}..."
        curl --header "Content-Type: application/json" \
            --get \
            --data "apikey=${SONARR_API_KEY}" \
            --silent \
            --request GET "${SONARR_API_URL}/episode/${EPISODE_ID}" \
        > ${TEMP_EPISODE_JSON_FILE} 2>/dev/null

        MONITORED="$(jq '.monitored' ${TEMP_EPISODE_JSON_FILE})"
        if [ -z "$MONITORED" ]; then
            echo "$(log_prefix)ERROR: Problem getting monitored status"
            echo "$(log_prefix)---"
            curl --header "Content-Type: application/json" \
                --get \
                --data "apikey=${SONARR_API_KEY}" \
                --silent \
                --request GET "${SONARR_API_URL}/episode/${EPISODE_ID}"
            echo "$(log_prefix)---"
        else
            if [ "$MONITORED" == "false" ]; then
                echo "$(log_prefix)Skipping episode already not monitoring."
            else
                echo "$(log_prefix)Updating episode monitoring setting..."
                local TEMP_UPDATED_JSON_FILE="$(mktemp --tmpdir -- tmp.json.XXXXXXXXXX)"
                jq '.monitored = false' ${TEMP_EPISODE_JSON_FILE} > ${TEMP_UPDATED_JSON_FILE}
                curl --header "Content-Type: application/json" \
                    --data @${TEMP_UPDATED_JSON_FILE} \
                    --silent \
                    --request PUT "${SONARR_API_URL}/episode?apikey=${SONARR_API_KEY}" > /dev/null
            fi
        fi
        rm "${TEMP_EPISODE_JSON_FILE}"
    fi
}

LASTSCAN_FILE="$(dirname ${0})/.$(basename ${0}).lastscan"

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

# Check for mysql being installed
mysql --version > /dev/null 2>&1 || { echo >&2 "ERROR: mysql Required but not installed.  Aborting."; exit 1; }

TEMP_FILE_LIST="$(mktemp --tmpdir -- tmp.lst.XXXXXXXXXX)"

echo "$(log_prefix)Getting watched episodes..."
get_watched_episodes > "${TEMP_FILE_LIST}"

echo "$(log_prefix)Getting all serieses json..."
ALL_SERIES_JSON="$(all_series_json)"

echo "$(log_prefix)Begin processing..."
while IFS=$'\t' read SERIES_NAME EPISODE_NAME; do
    echo "$(log_prefix)Processing ${SERIES_NAME} - ${EPISODE_NAME}..."
    unmonitor_episode "${SERIES_NAME}" "${EPISODE_NAME}" "${ALL_SERIES_JSON}"
done < "${TEMP_FILE_LIST}"

date +"%Y-%m-%d" > "${LASTSCAN_FILE}"

rm "${TEMP_FILE_LIST}"

echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
