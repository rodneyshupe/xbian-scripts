#!/usr/bin/env bash

color_normal="$(tput sgr0)"
color_ok="$(tput setaf 2)$(tput bold)"
color_warn="$(tput setaf 202)$(tput bold)"
color_fail="$(tput setab 1)$(tput setaf 7)$(tput bold)"

MOUNT_CHECK="/mnt/media/videos/"

kodi_version() {
    version="Unknown"

    # Check for kodi-rpc being installed and configured
    if [ "$(kodi-rpc --version > /dev/null 2>&1 && kodi-rpc JSONRPC.Ping | jq -r .result)" == "pong" ]; then
        #Get Version JSON
        versionJSON="$(/usr/bin/kodi-rpc Application.GetProperties properties '["version", "name"]')"

        #Extract Version Indo
        major="$(echo "${versionJSON}" | grep --only-matching '"major":[^,]*' | sed 's/"major"://g')"
        minor="$(echo "${versionJSON}" | grep --only-matching '"minor":[^,]*' | sed 's/"minor"://g')"

        version="${major}.${minor}"
    fi

    echo "${version}"
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
  tr '\n' ' ' <"${file}" | grep --text --only-matching --ignore-case --regexp "$regex" | sed "s/.*<${node}>\(.*\)<\/${node}>.*/\1/i"
}

check_connection() {
    local name="$1"
    local host="$2"
    local port="$3"
    local site="${4:-}"
    local msg="${5:-}"
    local port_state=""
    local site_state=""

    ( timeout 1 nc -z -v -w5 $host $port > /dev/null 2>&1 ) && port_state="${color_ok}  Open  ${color_normal}" || port_state="${color_fail} Closed ${color_normal}"

    if [ ! -z "${site}" ]; then
        [ $(curl --write-out %{http_code} --silent --output /dev/null --location "${site}") -eq 200 ] && site_state="${site}: ${color_ok} Active ${color_normal}" || site_state="${site}: ${color_fail} Closed ${color_normal}"
    fi
    #printf "    %-15.15s %-20s %s %s %s\n" "${name}" "(${host}:${port}): " "${port_state}" "${site_state}" "${msg}"
    printf "    %-15.15s %s %s\n" "${name}" "${site_state}" "${msg}"
}

echo "Services:"
echo "    Kodi:          $(/sbin/status xbmc 2>/dev/null | grep 'start/running' >/dev/null 2>&1 && echo "${color_ok}   Active ${color_normal}" || echo "${color_fail}   Stopped   ${color_normal}") Version: $(kodi_version)"
echo "    MySQL DB:      $(export MYSQL_PWD=kodi; mysqladmin --user kodi --host $(get_kodi_setting 'host') --post $(get_kodi_setting 'post') ping > /dev/null 2>&1 && echo "${color_ok}   Active ${color_normal}" || echo "${color_fail}   Stopped   ${color_normal}") Host: $(get_kodi_setting)"
echo "    Media Share:   $([ -d $MOUNT_CHECK ] && echo "${color_ok}   Active ${color_normal}" || echo "${color_fail} Unavailable ${color_normal}")"
echo "    VNC Server:    $(/sbin/status vnc-server 2>/dev/null | grep 'start/running' >/dev/null 2>&1 && echo "${color_ok}   Active ${color_normal}" || echo "${color_fail}   Stopped   ${color_normal}")"
echo
echo "Connections:"

check_connection "Kodi Webserver" localhost 8080 "http://kodi:kodi@localhost:8080/"

# Check for kodi-rpc being installed and configured
if [ ! [ kodi-rpc --version > /dev/null 2>&1 ] ]; then
    echo "    kodi-rpc: ${color_fail} Not installed ${color_normal}"
elif [ "$(kodi-rpc JSONRPC.Ping | jq -r .result)" == "pong" ]; then
    echo "    kodi-rpc: ${color_ok} Active ${color_normal}"
else
    echo "    kodi-rpc: ${color_warn} Installed but not configured  ${color_normal}"
fi

echo

drive_path_dir="/"  # mount drive to check
echo "Disk Space: (${drive_path_dir})"

WARN_SIZE=1048576 # 1G = 1*1024*1024k   # limit size in GB   (FLOOR QUOTA)
FAIL_SIZE=204800  # 200M = 200*1024k    # limit size in GB   (FLOOR QUOTA)
FREE_RAW=$(df -k --output=avail "${drive_path_dir}" | tail -n1) # df -k not df -h

color_free="${color_ok}"
[ $FREE_RAW -lt $WARN_SIZE ] && color_free="${color_warn}"
[ $FREE_RAW -lt $FAIL_SIZE ] && color_free="${color_fail}"
disk_total=$(df --human-readable --output=size $drive_path_dir | tail -1)
disk_used=$(df --human-readable --output=used $drive_path_dir | tail -1)
disk_avail=$(df --human-readable --output=avail $drive_path_dir | tail -1)
disk_pcent=$(df --human-readable --output=pcent $drive_path_dir | tail -1)
echo "    Total: ${disk_total}    Used: ${disk_used} ${color_free} ${disk_pcent} ${color_normal}    Avail:${color_free} ${disk_avail} ${color_normal}"

cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
[ "$cores" -eq "0" ] && cores=1
threshold="${cores:-1}.0"
if [ $(echo "0.13 < $threshold" | bc) -eq 1 ]; then
    echo
    echo -n "System information as of "
    /bin/date
    echo
    sys_load=$(cut -f1 -d ' ' /proc/loadavg)

    swap_used=$(vmstat -s | grep 'used swap' | grep --only-matching '[0-9]*')
    swap_total=$(vmstat -s | grep 'total swap' | grep --only-matching '[0-9]*')
    swap_usage=$(bc <<< "scale=2; $swap_used * 100 / $swap_total" | awk '{printf "%.1f%\n", $0}')

    logged_in=$(who | wc -l)

    memory_used=$(vmstat -s | grep 'used memory' | grep --only-matching '[0-9]*')
    memory_total=$(vmstat -s | grep 'total memory' | grep --only-matching '[0-9]*')
    memory_usage=$(bc <<< "scale=2; $memory_used * 100 / $memory_total" | awk '{printf "%.0f%\n", $0}')

    processes=$(ps -A | wc -l)

    printf "    System load:  %4s   Swap usage: %4s  Users logged in: %s\n" "${sys_load}" "${swap_usage}" "${logged_in}"
    printf "    Memory usage: %4s   Processes:  %4s" "${memory_usage}" "${processes}"

    echo -n "  Network:"
    for interface in $(/sbin/ifconfig -a -s | grep --only-matching '^[^\ ]*' | grep -v 'Iface\|lo'); do
        ip="$(/sbin/ifconfig ${interface} | grep --only-matching '[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*' | head -1)"
        [ ! -z $ip ] && echo -n "  ${interface}: ${ip}"
    done
    ip="$(wget -qqO- 'https://duckduckgo.com/?q=what+is+my+ip' | grep -Pow 'Your IP address is \K[0-9.]+')"
    [ ! -z $ip ] || ip="${color_fail}Internet Down${color_normal}"
    echo "  External IP: ${ip}"
fi
echo
