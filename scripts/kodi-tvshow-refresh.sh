#!/usr/bin/env bash

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

MYSQL_HOST="$(get_kodi_setting 'host')"
MYSQL_PORT="$(get_kodi_setting 'port')"
MYSQL_USER="$(get_kodi_setting 'user')"
MYSQL_PASS="$(get_kodi_setting 'pass')"

#KODI_USER="$(getent passwd '1000' | cut -d: -f1)"
KODI_USER="$(ps aux | grep kodi | grep -v grep | head -n1 | cut -d ' ' -f1)"
SQL_EXCLUDE="%/archive/%"

SHOW_PREFIX=1
test -t 1 && SHOW_PREFIX=0
log_prefix() {
    [ $SHOW_PREFIX -eq 1 ] && echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
}

secs_to_human() {
    #echo "$(( ${1} / 3600 ))h $(( (${1} / 60) % 60 ))m $(( ${1} % 60 ))s"
    echo "$(( ${1} / 60 ))m $(( ${1} % 60 ))s"
}

function usage() {
  cat << EOF
Usage: $0 [options...]
This script removed watched TV Shows from the Kodi library.

Options:
  -h            Show the help and exit
  -e            Include Ended
  -c            Include Continuing
  -d seconds    Set delay between API calls (default 2)
  -o            Display option settings
EOF
}

function parse_args() {
    while getopts "hecd:o" OPT; do
        case $OPT in
            h)
                usage
                exit 1
                ;;
            e)
                INCLUDE_ENDED=1
                ;;
            c)
                INCLUDE_CONTINUING=1
                ;;
            d)
                DELAY=$OPTARG
                ;;
            o)
                DISPLAY_OPTIONS=1
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                echo ""
                usage
                exit 1
                ;;
        esac
    done
}

function display_options(){
    if [ $DISPLAY_OPTIONS -eq 1 ] ; then
        echo "
  Options:
    Include Ended:      $([ $INCLUDE_ENDED -eq 1 ] && echo 'True' || echo 'False')
    Include Continuing: $([ $INCLUDE_CONTINUING -eq 1 ] && echo 'True' || echo 'False')
    Delay:              ${DELAY}s

    MySQL:
      Host: $MYSQL_HOST
      Port: $MYSQL_PORT
    "
        if (jq --version > /dev/null 2>&1); then
            WEBSERVER_SETTINGS=$(kodi-rpc Settings.GetSettings  | jq -M '.result.settings | map(select(.parent == "services.webserver"))')
            echo "  Kodi:
      Host: $(kodi-rpc XBMC.GetInfoLabels labels '[ "Network.IPAddress" ]' | jq -r '.result | .[]')
      Port: $(echo $WEBSERVER_SETTINGS | jq -r 'map(select(.id == "services.webserverport")) | .[].value')
      User: $(echo $WEBSERVER_SETTINGS | jq -r 'map(select(.id == "services.webserverusername")) | .[].value')
      Pass: $(echo $WEBSERVER_SETTINGS | jq -r 'map(select(.id == "services.webserverpassword")) | .[].value')
        "
        fi
    fi
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
    local _KODI_DB=$6

    [ -z ${_KODI_DB} ] && _KODI_DB=$(get_kodi_myvideo_db "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}")

    MYSQL_PWD="$_MYSQL_PASS" mysql \
        --skip-column-names \
        --user=$_MYSQL_USER \
        --host=$_MYSQL_HOST \
        --port=$_MYSQL_PORT \
        --database="$_KODI_DB" \
        --execute="${_QUERY}"
}

function refresh_series () {
    local _MYSQL_HOST="${1:-$(get_kodi_setting 'host')}"
    local _MYSQL_PORT="${2:-$(get_kodi_setting 'port')}"
    local _MYSQL_USER="${3:-$(get_kodi_setting 'user')}"
    local _MYSQL_PASS="${4:-$(get_kodi_setting 'pass')}"

    if [ $INCLUDE_ENDED -eq 1 ] && [ $INCLUDE_CONTINUING -eq 1 ]; then
        WHAT="all"
        WHERE=""
    elif [ $INCLUDE_ENDED -eq 1 ] && [ $INCLUDE_CONTINUING -eq 0 ]; then
        WHAT="all but continuing"
        WHERE="WHERE c02 != 'Continuing'"
    elif [ $INCLUDE_ENDED -eq 0 ] && [ $INCLUDE_CONTINUING -eq 1 ]; then
        WHAT="all but ended"
        WHERE="WHERE c02 != 'Ended'"
    else
        WHAT="upcoming (and unknown)"
        WHERE="WHERE c02 NOT IN ('Ended', 'Continuing')"
    fi

    echo "$(log_prefix)Refreshing $WHAT series..."

    local _KODI_DB=$(get_kodi_myvideo_db "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}")

    #Get file path and episode id from supplied partial_path
    SHOW_LIST="$(mktemp --tmpdir -- tmp.lst.XXXXXXXXXX)"
    mysql_query "SELECT idShow 'tvShowId' FROM tvshow $WHERE" "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}" "${_KODI_DB}" \
        > "${SHOW_LIST}" \
        || { echo >&2 "ERROR: mysql Query Failed.  Aborting."; exit 2; }

    while read tvShowId; do
        echo "$(log_prefix)    Processing $(kodi-rpc VideoLibrary.GetTVShowDetails tvshowid $tvShowId | jq .result.tvshowdetails.label -c)..."
        kodi-rpc VideoLibrary.RefreshTVShow tvshowid $tvShowId ignorenfo true refreshepisodes false > /dev/null
        sleep $DELAY
    done < "$SHOW_LIST"
    rm "$SHOW_LIST"
}

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

# Check for kodi-rpc being installed and configured
kodi-rpc --version > /dev/null 2>&1 || { echo >&2 "ERROR: kodi-rpc Required but not installed.  Aborting."; exit 1; }
[ "$(kodi-rpc JSONRPC.Ping | jq -r .result)" == "pong" ] || { echo "ERROR: kodi-rpc Installed but not configured.  Aborting."; exit 1; }

# Check for mysql being installed
mysql --version > /dev/null 2>&1 || { echo >&2 "ERROR: mysql Required but not installed.  Aborting."; exit 1; }

DISPLAY_OPTIONS=0
INCLUDE_ENDED=0
INCLUDE_CONTINUING=0
DELAY=2

parse_args $@

display_options

refresh_series "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}"

echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"