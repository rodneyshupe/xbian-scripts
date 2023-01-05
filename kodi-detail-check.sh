#!/bin/bash

log_prefix() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S %Z')] $(basename "$(test -L "$0" && readlink "$0" || echo "$0")"): "
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
    file="/home/xbian/.kodi/userdata/advancedsettings.xml"
  fi

  # Set the regular expression to match the node
  local regex="<${node}>.*</${node}>"

  # If a parent node was specified, add it to the regular expression
  if [[ -n "$parent_node" ]]; then
    regex="<${parent_node}>.*${regex}.*</${parent_node}>"
  fi

  # Extract the value of the node using grep and sed
  echo $regex
  echo $node
  tr '\n' ' ' <"${file}" | grep --text --only-matching --ignore-case --regexp "$regex" | sed "s/.*<${node}>\(.*\)<\/${node}>.*/\1/i"
}

START_SEC=$(date +%s)
echo "$(log_prefix)Start Time: $(date)"

# Check for kodi-rpc being installed and configured
kodi-rpc --version > /dev/null 2>&1 || { echo >&2 "ERROR: kodi-rpc Required but not installed.  Aborting."; exit 1; }
[ "$(kodi-rpc JSONRPC.Ping | jq -r .result)" == "pong" ] || { echo "$(log_prefix)ERROR: kodi-rpc Installed but not configured.  Aborting."; exit 1; }

DEFAULT_DELAY_SEC=15

MYSQL_HOST=$(get_kodi_setting 'host')
MYSQL_PORT=$(get_kodi_setting 'port')
MYSQL_USER=$(get_kodi_setting 'user')
MYSQL_PASS=$(get_kodi_setting 'pass')

SAMBA_SHARE="smb://KODISERVER/streams"
SAMBA_PATH="/home/osmc/streams"

if [[ "${1,,}" == "full" ]]; then
  KODI_SELECT_MESSAGE="VideoLibrary.GetEpisodes"
  FIX_WATCHED="No" # Switch to "Yes" if you want to fix already watched shows.
else
  KODI_SELECT_MESSAGE="VideoLibrary.GetRecentlyAddedEpisodes"
  FIX_WATCHED="No"
fi

rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02X' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}

function get_episode_list() {
  RESPONSE="$(kodi-rpc ${KODI_SELECT_MESSAGE} properties '["plot", "thumbnail", "playcount"]' | jq '.result.episodes | .[] ' 2>/dev/null)"
  if [[ "${FIX_WATCHED}" != "Yes" ]]; then
    RESPONSE="$(echo "${RESPONSE}"  | jq ' select( .playcount == 0 ) ' 2>/dev/null)"
  fi
  echo "${RESPONSE}" | jq 'select( .thumbnail =="" or .plot == "" ) | .episodeid' 2>/dev/null
}

function sleep_timer() {
  SLEEP_SEC=${1:-$DEFAULT_DELAY_SEC}
  shift
  MSG="${@:-Pausing for}"
  for i in $(seq ${SLEEP_SEC} -1 1); do
    echo -ne "\r\e[0K${MSG} ${i}s"
    sleep 1
  done
  echo -ne "\r\e[0K${MSG}"
}

function wait_for_update() {
  EPISODEID=$1
  shift
  TVSHOWID=$1
  shift
  SEASON=$1
  shift
  EPISODE=$1
  shift
  MAX_WAIT=$((${1:-$DEFAULT_DELAY_SEC}))
  shift
  MSG="${@:-Waiting for Episode Info ...}"

  re='^[0-9]+$'

  LOOP_COUNT=$((0))
  NEW_EPISODE_ID=""

  while [ -z "${NEW_EPISODE_ID}" ] && [ ${LOOP_COUNT} -lt ${MAX_WAIT} ]; do
    COUNT=$((${MAX_WAIT} - ${LOOP_COUNT}))
    echo -ne "\r\e[0K${MSG} ${COUNT}s"
    sleep 1
    SHOWLIST="$(kodi-rpc VideoLibrary.GetEpisodes tvshowid ${TVSHOWID} season ${SEASON} properties '[ "episode" ]')"
    NEW_EPISODE_ID=$(echo "$SHOWLIST" | jq -r ".result.episodes | .[] | select (.episode == ${EPISODE}) | .episodeid" 2>/dev/null)

    if ! [[ ${NEW_EPISODE_ID} =~ $re ]]; then
      #echo ${NEW_EPISODE_ID}
      NEW_EPISODE_ID=""
    elif [ ${EPISODEID} -eq ${NEW_EPISODE_ID} ]; then
      NEW_EPISODE_ID=""
    fi

    LOOP_COUNT=$((${LOOP_COUNT} + 1))
  done

  #echo ${NEW_EPISODE_ID}
}

function update_episode() {
  EPISODE_ID=$1
  WATCHED=${2:-No}
  MESSAGE=${3:-"   Refreshing Episode ID: ${EPISODE_ID} ..."}
  DELAY_SEC=${4:-${DEFAULT_DELAY_SEC}}
  echo -n "${MESSAGE}"

  # Get Episode Details
  RESPONSE="$(kodi-rpc VideoLibrary.GetEpisodeDetails episodeid ${EPISODE_ID} properties '["tvshowid", "season", "episode", "playcount", "lastplayed"]')"
  PLAYCOUNT=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.playcount )
  LASTPLAYED=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.lastplayed )
  TVSHOWID=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.tvshowid )
  SHOW=$(kodi-rpc VideoLibrary.GetTVShowDetails tvshowid ${TVSHOWID} | jq -r .result.tvshowdetails.label)
  SEASON=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.season )
  EPISODE=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.episode )

  RESPONSE="$(kodi-rpc VideoLibrary.RefreshEpisode episodeid ${EPISODE_ID} ignorenfo true)"

  if [[ "$( echo ${RESPONSE} | jq -r .result )" == "OK" ]]; then
    wait_for_update ${EPISODE_ID} ${TVSHOWID} ${SEASON} ${EPISODE} ${DELAY_SEC} "${MESSAGE}"

    SHOWLIST="$(kodi-rpc VideoLibrary.GetEpisodes tvshowid ${TVSHOWID} season ${SEASON} properties '[ "episode" ]')"
    NEW_EPISODE_ID=$(echo "$SHOWLIST" | jq -r ".result.episodes | .[] | select (.episode == ${EPISODE}) | .episodeid" 2>/dev/null)

    re='^[0-9]+$'

    if [ -z "${NEW_EPISODE_ID}" ]; then
      #RESPONSE=""
      MESSAGE="${MESSAGE} Wait Expired [Debug: ShowId=${TVSHOWID} Episode:S${SEASON}E${EPISODE}"
      if [ ${PLAYCOUNT} -gt 0 ]; then
        MESSAGE="${MESSAGE} Played:${LASTPLAYED}]"
      else
        MESSAGE="${MESSAGE}]"
      fi
    elif ! [[ ${NEW_EPISODE_ID} =~ $re ]]; then
      #RESPONSE=""
      MESSAGE="${MESSAGE} Invalid Episode Id (${NEW_EPISODE_ID}) [Debug: ShowId=${TVSHOWID} Episode:S${SEASON}E${EPISODE}"
      if [ ${PLAYCOUNT} -gt 0 ]; then
        MESSAGE="${MESSAGE} Played:${LASTPLAYED}]"
      else
        MESSAGE="${MESSAGE}]"
      fi
    else
      if [ ${PLAYCOUNT} -gt 0 ] && [ ${EPISODE_ID} -ne ${NEW_EPISODE_ID} ]; then
        MESSAGE="${MESSAGE}   New ID: ${NEW_EPISODE_ID} Fixing playcount (${PLAYCOUNT}) and last played (${LASTPLAYED}) ..."
        RESPONSE="$(kodi-rpc VideoLibrary.SetEpisodeDetails episodeid ${NEW_EPISODE_ID} playcount "${PLAYCOUNT}" lastplayed "${LASTPLAYED}" )"
        if [[ "$( echo ${RESPONSE} | jq -r .result 2>/dev/null)" == "OK" ]]; then
          sleep_timer ${DELAY_SEC} "${MESSAGE}"
        else
          echo -n "$(log_prefix)Failed"
        fi
      elif [ ${EPISODE_ID} -ne ${NEW_EPISODE_ID} ]; then
        MESSAGE="${MESSAGE}   New ID: ${NEW_EPISODE_ID} "
      fi
      RESPONSE="$(kodi-rpc VideoLibrary.GetEpisodeDetails episodeid ${NEW_EPISODE_ID} properties '["plot", "firstaired", "fanart", "thumbnail", "playcount", "lastplayed", "file"]')"
      PLOT=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.plot )
      THUMBNAIL=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.thumbnail )
      FANART=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.fanart )
      AIRDATE=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.firstaired )
      DAYS_SINCE_AIRED=$( echo "( `date -d now +%s` - `date -d $AIRDATE +%s`) / (24*3600)" | bc --standard )
      if [ -z "${THUMBNAIL}" ] || [[ "${THUMBNAIL}" == "null" ]]; then
        FILE_URI=$(echo "${RESPONSE}" | jq  -r .result.episodedetails.file )
        FILE_PATH="$(dirname "${FILE_URI/$SAMBA_SHARE/$SAMBA_PATH}")"
        # Check directory for <Showname>.jpg or thumbnail.jpg
        if [ -f "${FILE_PATH}/thumbnail.jpg" ]; then
          THUMBNAIL_FILE="$(dirname "${FILE_URI}")/thumbnail.jpg"
        elif [ -f "${FILE_PATH}/$(basename "${FILE_PATH}").jpg" ]; then
          THUMBNAIL_FILE="${FILE_PATH}/$(basename "${FILE_PATH}").jpg"
        else
          THUMBNAIL_FILE=""
          #TODO: Check gdrive for thumbnail and if it is present copy down and use that.
        fi
        if [ ! -z "${THUMBNAIL_FILE}" ]; then
          THUMBNAIL="image://$(rawurlencode "${THUMBNAIL_FILE}")"
        elif ( [ ! -z "${PLOT}" ] && [ ${DAYS_SINCE_AIRED} -ge 7 ] ) || [ ${DAYS_SINCE_AIRED} -ge 14 ]; then
          THUMBNAIL="${FANART}"         
        else
          THUMBNAIL=""
        fi
        if [ ! -z "${THUMBNAIL}" ]; then
          RESPONSE="$(kodi-rpc VideoLibrary.SetEpisodeDetails episodeid ${NEW_EPISODE_ID} thumbnail "${THUMBNAIL}")"
          if [[ "$( echo ${RESPONSE} | jq -r .result )" != "OK" ]]; then
            THUMBNAIL=""
          fi
        fi
      fi
      MESSAGE="$MESSAGE Plot:"
      if [ -z "${PLOT}" ] || [[ "${PLOT}" == "null" ]]; then
        #TODO: Look for alternate way of finding the plot.
        MESSAGE="${MESSAGE} Missing"
      else
        MESSAGE="${MESSAGE} OK"
      fi

      MESSAGE="$MESSAGE Thumbnail:"
      if [ -z "${THUMBNAIL}" ] || [[ "${THUMBNAIL}" == "null" ]]; then
        MESSAGE="${MESSAGE} Missing"
      else
        MESSAGE="${MESSAGE} OK"
      fi
      MESSAGE="${MESSAGE} - ${SHOW} (${TVSHOWID}) S${SEASON}E${EPISODE}"
      echo -ne "\r\e[0K$(log_prefix)${MESSAGE}"
    fi

    echo ""
  else
    echo "$(log_prefix)Failed [Debug: ShowId=${TVSHOWID} Episode:S${SEASON}E${EPISODE} Played:${LASTPLAYED}]"
  fi
}

echo "$(log_prefix)Calling Kodi API to find missing Plots and Thumbnails..."
EPISODE_LIST=$(get_episode_list)
EPISODE_COUNT=$(echo ${EPISODE_LIST} | wc -w)
EPISODE_LOOP_COUNT=0
echo "$(log_prefix)Refreshing Episodes. Estimated time: $(( $(( ${EPISODE_COUNT} * ${DEFAULT_DELAY_SEC} )) / 60 + 1)) minutes"
for ID in $(echo ${EPISODE_LIST}); do
  EPISODE_LOOP_COUNT=$((${EPISODE_LOOP_COUNT} + 1))
  update_episode ${ID} ${FIX_WATCHED} "   Refreshing ${EPISODE_LOOP_COUNT} of ${EPISODE_COUNT} Episode ID: ${ID} ..."
done

SUCCESS_COUNT=$(( ${EPISODE_LOOP_COUNT} - $(get_episode_list | wc -w) ))

echo "$(log_prefix)Successfully updated ${SUCCESS_COUNT} of ${EPISODE_COUNT}"

#echo ""
echo "$(log_prefix)Fixing Dates..."
export MYSQL_PWD=$MYSQL_PASS
LATEST_DB_QUERY="SELECT table_schema FROM information_schema.TABLES WHERE table_schema LIKE 'MyVideos%' GROUP BY table_schema;"
MYSQL_KODI_VIDEOS_DB=$(mysql --skip-column-names \
                             --user=$MYSQL_USER \
                             --host=$MYSQL_HOST \
                             --port=$MYSQL_PORT \
                             --execute="$LATEST_DB_QUERY" \
                       | sort | tail --lines=1)

echo "$(log_prefix)Querying Kodi Database [IP:$MYSQL_HOST:$MYSQL_PORT, DB:$MYSQL_KODI_VIDEOS_DB]..."
SQL_EXECUTE="UPDATE files f JOIN episode e ON f.idFile=e.idFile
  SET f.dateAdded = cast(concat(DATE_FORMAT(e.c05,'%Y-%m-%d'), ' ', DATE_FORMAT(f.dateAdded,'%H:%i:%s')) as datetime)
  WHERE DATEDIFF(f.dateAdded, e.c05) > 7;"
mysql --user=$MYSQL_USER \
  --host=$MYSQL_HOST \
  --port=$MYSQL_PORT \
  --database=$MYSQL_KODI_VIDEOS_DB \
  --batch \
  --execute="${SQL_EXECUTE}"

#echo ""
echo "$(log_prefix)Complete. Time Elapsed: $(secs_to_human "$(($(date +%s) - ${START_SEC}))")"
