#!/usr/bin/env bash

ENVIORMENT_FILE= "$(dirname "$0")/$(basename "$0" | cut -f 1 -d '.').env"
[ ! -f "$ENVIORMENT_FILE" ] $ENVIORMENT_FILE="/home/$(stat -c '%U' "$0")/.config/$(basename "$0" | cut -f 1 -d '.').env"
[ -f "$ENVIORMENT_FILE" ] source $ENVIORMENT_FILE

SONARR_API_URL="${1:-$SONARR_API_URL}"
SONARR_API_KEY="${2:-$SONARR_API_KEY}"

REMOTE_PATH="${3:-$REMOTE_PATH}"
LOCAL_PATH="${4:-$LOCAL_PATH}"

# Function to extract the value of a node from an XML file
get_kodi_setting() {
  # Set the variables for the node and parent node names
  local node="${1:-host}"
  local parent_node="${2:-videodatabase}"
  local file="${3}"
  if [ -z ${file} ] || [ ! -f ${file} ]; then
    kodi_user="$(ps aux | grep kodi | grep -v grep | head -n1 | cut -d ' ' -f1)"
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

MYSQL_HOST="$(get_kodi_setting 'host')"
MYSQL_PORT="$(get_kodi_setting 'post')"
MYSQL_USER="$(get_kodi_setting 'user')"
MYSQL_PASS="$(get_kodi_setting 'pass')"

#KODI_USER="$(getent passwd '1000' | cut -d: -f1)"
KODI_USER="$(ps aux | grep kodi | grep -v grep | head -n1 | cut -d ' ' -f1)"
SQL_EXCLUDE="%/archive/%"

log_prefix() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
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
  -h  Show the help and exit
  -d  Dry run
  -c  Don't execute Kodi clean
  -s  Don't execute Kodi scan
  -o  Display option settings
EOF
}

function parse_args() {
  while getopts ":hdcso" OPT; do
    case $OPT in
      h)
        usage
        exit 1
        ;;
      d)
        echo "Executing with Dryrun."
        DRYRUN="true"
        ;;
      c)
        echo "Executing with No Clean."
        DO_CLEAN="false"
        ;;
      s)
        echo "Executing with No Scan."
        DO_SCAN="false"
        ;;
      o)
        DISPLAY_OPTIONS="true"
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
  if [ "$DISPLAY_OPTIONS" = "true" ] ; then
    echo "
  Options:
    Execute Dryrun:     $DRYRUN
    Execute Kodi Clean: $DO_CLEAN
    Execute Kodi Scan:  $DO_SCAN
    Working Directory:  $WORK_DIR
    MySQL:
      Host: $MYSQL_HOST
      Port: $MYSQL_PORT
  "
    if (jq --version > /dev/null 2>&1); then
      WEBSERVER_SETTINGS=$(kodi-rpc Settings.GetSettings  | jq -M '.result.settings | map(select(.parent == "services.webserver"))')
      echo "  Kodi:
      Host: $(kodi-rpc XBMC.GetInfoLabels labels '[ "Network.IPAddress" ]' | jq -r '.result | .[]')
      Post: $(echo $WEBSERVER_SETTINGS | jq -r 'map(select(.id == "services.webserverport")) | .[].value')
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
  local _MYSQL_HOST="${1:-$(get_kodi_setting 'host')}"
  local _MYSQL_PORT="${2:-$(get_kodi_setting 'port')}"
  local _MYSQL_USER="${3:-$(get_kodi_setting 'user')}"
  local _MYSQL_PASS="${4:-$(get_kodi_setting 'pass')}"
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

function all_series_json {
  echo "$(curl --header "Content-Type: application/json" \
               --get \
               --data "apikey=${SONARR_API_KEY}" \
               --silent \
               --request GET "${SONARR_API_URL}/series")"
}

function remove_file () {
  local _FILE_PATH="${1}"
  local _EPISODE_ID="${2}"
  local _DO_CLEAN="${3:-true}"
  local _DRYRUN="${4:-false}"

  PREFIX="$(log_prefix) "
  if [[ "${_DRYRUN}" == "true" ]] ; then
    PREFIX="$(log_prefix)[DRYRUN] "
  fi

  if [ -f "${_FILE_PATH}" ]; then
    echo "${PREFIX}Removing File: ${_FILE_PATH}"
    [[ "${_DRYRUN}" == "false" ]] && sudo rm "${_FILE_PATH}" \
    && [[ "${_DO_CLEAN}" == "true" ]] \
    && kodi-rpc VideoLibrary.RemoveEpisode episodeid ${_EPISODE_ID} > /dev/null
  else
    if [[ "${_DO_CLEAN}" == "true" ]] ; then
      echo "${PREFIX}Removing File (${_FILE_PATH}) Missing. Removing Episode ID: ${_EPISODE_ID}"
      [[ "${_DRYRUN}" = "false" ]] && kodi-rpc VideoLibrary.RemoveEpisode episodeid ${_EPISODE_ID} > /dev/null
    fi
  fi
}

function remove_watched_files () {
  local _MYSQL_HOST="${1:-$(get_kodi_setting 'host')}"
  local _MYSQL_PORT="${2:-$(get_kodi_setting 'port')}"
  local _MYSQL_USER="${3:-$(get_kodi_setting 'user')}"
  local _MYSQL_PASS="${4:-$(get_kodi_setting 'pass')}"
  local _KODI_DB="$5"

  [ -z ${_KODI_DB} ] && _KODI_DB=$(get_kodi_myvideo_db "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}")

  function get_removal_list() {
    local _MYSQL_HOST="${1:-$(get_kodi_setting 'host')}"
    local _MYSQL_PORT="${2:-$(get_kodi_setting 'port')}"
    local _MYSQL_USER="${3:-$(get_kodi_setting 'user')}"
    local _MYSQL_PASS="${4:-$(get_kodi_setting 'pass')}"
    local _KODI_DB="$5"

    [ -z ${_KODI_DB} ] && _KODI_DB=$(get_kodi_myvideo_db "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}")

    FILE_QUERY="$(mktemp -t tmp.sql.XXXXXXXXXX)"
    echo "
      SELECT CONCAT(REPLACE(CONCAT(p.strPath, f.strFilename), '${REMOTE_PATH}/', '${LOCAL_PATH}/') , '|', e.idEpisode) AS 'line'
      FROM episode e
      JOIN files f ON f.idFile = e.idFile
      JOIN tvshow t ON t.idShow = e.idShow
      JOIN path p ON p.idPath = f.idPath
      WHERE f.playCount > 0
        AND p.strPath NOT LIKE '${SQL_EXCLUDE}'
        AND NOT (CAST(e.c12 AS UNSIGNED) = (SELECT MAX(CAST(episode.c12 AS UNSIGNED)) -- Season
            FROM episode
            JOIN files ON files.idFile = episode.idFile
            JOIN tvshow ON tvshow.idShow = episode.idShow
            WHERE files.playCount > 0
              AND tvshow.c00 = t.c00
            )
          AND CAST(e.c13 AS UNSIGNED) = (SELECT MAX(CAST(episode.c13 AS UNSIGNED)) -- Episode
            FROM episode
            JOIN files ON files.idFile = episode.idFile
            JOIN tvshow ON tvshow.idShow = episode.idShow
            WHERE files.playCount > 0
              AND episode.c12 = e.c12
              AND tvshow.c00 = t.c00
            )
          )
      ;
    " > "${FILE_QUERY}"
    SQL_QUERY="$(cat "${FILE_QUERY}")" && rm "${FILE_QUERY}"

    FILE_LIST="$(mktemp --tmpdir -- tmp.lst.XXXXXXXXXX)"
    mysql_query "${SQL_QUERY}" "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}" "${_KODI_DB}" \
      > "${FILE_LIST}" \
      || { echo >&2 "ERROR: mysql Query Failed.  Aborting."; exit 2; }

    echo "${FILE_LIST}"
  }

  echo "$(log_prefix)Querying Kodi Database [IP:$MYSQL_HOST:$MYSQL_PORT, DB:$kodi_db]..."

  FILE_LIST="$(get_removal_list "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}" "${_KODI_DB}")"

  echo "$(log_prefix)Removing Files:"
  while read line; do
    IFS="|" read -ra PARTS <<< "$line"
    file=${PARTS[0]}
    episodeid=${PARTS[1]}

    remove_file "${file}" "${episodeid}" "${DO_CLEAN}" "${DRYRUN}"
  done < "$FILE_LIST"
  rm "$FILE_LIST"
}

function remove_ended_files () {
  local _MYSQL_HOST="${1:-localhost}"
  local _MYSQL_PORT="${2:-3306}"
  local _MYSQL_USER="${3:-kodi}"
  local _MYSQL_PASS="${4:-kodi}"
  local _KODI_DB="$5"

  echo "$(log_prefix)Removing files from ended series:"

  all_series_json | jq '.[] | select(.status=="ended") | .path' | \
  while read partial_path; do
    partial_path=`sed -e 's/^"//' -e 's/"$//' -e 's/\/$//' <<<"$partial_path"`

    #Get file path and episode id from supplied partial_path
    FILE_QUERY="$(mktemp --tmpdir -- tmp.sql.XXXXXXXXXX)"
    echo "
      SELECT CONCAT(REPLACE(CONCAT(p.strPath, f.strFilename), '${REMOTE_PATH}/', '${LOCAL_PATH}/') , '|', e.idEpisode) AS 'line'
      FROM episode e
      JOIN files f ON f.idFile = e.idFile
      JOIN path p ON p.idPath = f.idPath
      WHERE f.playCount > 0
        AND p.strPath LIKE \"${REMOTE_PATH}${partial_path}/%\"
        AND p.strPath NOT LIKE '${SQL_EXCLUDE}'
        AND NOT EXISTS (SELECT 1 FROM files f2 JOIN path p2 ON f2.idPath = p2.idPath
                        WHERE (f2.playCount = 0 OR f2.playCount IS NULL) AND p2.strPath = p.strPath
                        GROUP BY p2.strPath
                        HAVING count(*) > 1)
      ;
    " > "${FILE_QUERY}"
    SQL_QUERY="$(cat "${FILE_QUERY}")" && rm "${FILE_QUERY}"

    FILE_LIST="$(mktemp --tmpdir -- tmp.lst.XXXXXXXXXX)"
    mysql_query "${SQL_QUERY}" "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}" "${_KODI_DB}" \
      > "${FILE_LIST}" \
      || { echo >&2 "ERROR: mysql Query Failed.  Aborting."; exit 2; }

    if [ ! -z "$(cat "$FILE_LIST")" ]; then
      while read line; do
        IFS="|" read -ra PARTS <<< "$line"
        file="${PARTS[0]}"
        episodeid=${PARTS[1]}

        remove_file "${file}" "${episodeid}" "${DO_CLEAN}" "${DRYRUN}"
      done < "$FILE_LIST"
      rm "$FILE_LIST"
    else
      echo "
        SELECT CONCAT(REPLACE(CONCAT(p.strPath, f.strFilename), '${REMOTE_PATH}/', '${LOCAL_PATH}/') , '|', IFNULL(e.idEpisode,-1), '|', IFNULL(f.playCount, 0)) AS 'line'
        FROM files f
        JOIN path p ON p.idPath = f.idPath
        JOIN episode e ON f.idFile = e.idFile
        WHERE p.strPath LIKE \"${REMOTE_PATH}${partial_path}/%\"
          AND p.strPath NOT LIKE '${SQL_EXCLUDE}';
      " > "${FILE_QUERY}"
      SQL_QUERY="$(cat "${FILE_QUERY}")" && rm "${FILE_QUERY}"

      mysql_query "${SQL_QUERY}" "${_MYSQL_HOST}" "${_MYSQL_PORT}" "${_MYSQL_USER}" "${_MYSQL_PASS}" "${_KODI_DB}" \
        > "${FILE_LIST}" \
        || { echo >&2 "ERROR: mysql Query Failed.  Aborting."; exit 2; }

      if [ ! -z "$(cat "$FILE_LIST")" ]; then
        count=0
        while read line; do
          IFS="|" read -ra PARTS <<< "$line"
          file="${PARTS[0]}"
          episodeid=${PARTS[1]}
          playcount=${PARTS[2]}

          [ $playcount -eq 0 ] && [ -s "${file}" ] && count=$((count+1))
        done < "$FILE_LIST"

        if [ $count -eq 0 ]; then
          while read line; do
            IFS="|" read -ra PARTS <<< "$line"
            file="${PARTS[0]}"
            episodeid=${PARTS[1]}

            remove_file "${file}" "${episodeid}" "${DO_CLEAN}" "${DRYRUN}"
          done < "$FILE_LIST"
        else
          [[ "${DRYRUN}" == "true" ]] && true # echo "... Skipping: ${LOCAL_PATH}${partial_path}"
        fi
        rm "$FILE_LIST"
      fi
    fi
  done
}

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

# Check for kodi-rpc being installed and configured
kodi-rpc --version > /dev/null 2>&1 || { echo >&2 "ERROR: kodi-rpc Required but not installed.  Aborting."; exit 1; }
[ "$(kodi-rpc JSONRPC.Ping | jq -r .result)" == "pong" ] || { echo "ERROR: kodi-rpc Installed but not configured.  Aborting."; exit 1; }

# Check for mysql being installed
mysql --version > /dev/null 2>&1 || { echo >&2 "ERROR: mysql Required but not installed.  Aborting."; exit 1; }

DRYRUN="false"
DO_CLEAN="true"
DO_SCAN="true"
DISPLAY_OPTIONS="false"

parse_args $@

WORK_DIR="$(dirname -- "$0")"

if [ ! -d "${LOCAL_PATH}" ]; then
  echo "$(log_prefix)Local Path Missing..."
  sudo umount "${LOCAL_PATH}" 2>/dev/null
  sudo mount "${LOCAL_PATH}" 2>/dev/null

  if [ ! -d "${LOCAL_PATH}" ]; then
    echo "$(log_prefix)Problem Mounting Local Path!"
    DRYRUN="true"
    DO_CLEAN="false"
  fi
fi
display_options

OUTPUT_JSON="$(mktemp --tmpdir -- tmp.json.XXXXXXXXXX)"

kodi_db=$(get_kodi_myvideo_db "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}")

remove_watched_files "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}" "${kodi_db}"

remove_ended_files "${MYSQL_HOST}" "${MYSQL_PORT}" "${MYSQL_USER}" "${MYSQL_PASS}" "${kodi_db}"

if [ "$DO_SCAN" = "true" ]; then
  echo "$(log_prefix)Calling Kodi API for Scan..."
  kodi-rpc VideoLibrary.Scan showdialogs false > /dev/null
  rm "$OUTPUT_JSON"
fi

echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"