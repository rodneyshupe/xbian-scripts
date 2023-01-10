#!/usr/bin/env bash


MOUNT_CHECK="/mnt/media/videos/"

# Most of this taken from the PADD project by Jim McKenna - https://github.com/jpmck/PADD/

declare -i core_count=1
core_count=$(cat /sys/devices/system/cpu/kernel_max 2> /dev/null)+1

# COLORS
black_text=$(tput setaf 0)   # Black
red_text=$(tput setaf 1)     # Red
green_text=$(tput setaf 2)   # Green
yellow_text=$(tput setaf 3)  # Yellow
blue_text=$(tput setaf 4)    # Blue
magenta_text=$(tput setaf 5) # Magenta
cyan_text=$(tput setaf 6)    # Cyan
white_text=$(tput setaf 7)   # White
reset_text=$(tput sgr0)      # Reset to default color

# STYLES
bold_text=$(tput bold)
blinking_text=$(tput blink)
dim_text=$(tput dim)

color_normal="$(tput sgr0)"
color_ok="$(tput setaf 2)$(tput bold)"
color_warn="$(tput setaf 202)$(tput bold)"
color_fail="$(tput setab 1)$(tput setaf 7)$(tput bold)"

HeatmapGenerator () {
    # if one number is provided, just use that percentage to figure out the colors
    if [ -z "$2" ]; then
        load=$(printf "%.0f" "$1")
    # if two numbers are provided, do some math to make a percentage to figure out the colors
    else
        load=$(printf "%.0f" "$(echo "$1 $2" | awk '{print ($1 / $2) * 100}')")
    fi

    # Color logic
    #  |<-                 green                  ->| yellow |  red ->
    #  0  5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100
    if [ "${load}" -lt 75 ]; then
        out=${green_text}
    elif [ "${load}" -lt 90 ]; then
        out=${yellow_text}
    else
        out=${red_text}
    fi

    echo "$out"
}

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

PrintServiceInformation() {
    echo "Services:"
    echo "    Kodi:          $(/sbin/status xbmc 2>/dev/null | grep 'start/running' >/dev/null 2>&1 && echo "${color_ok}   Active ${color_normal}" || echo "${color_fail}   Stopped   ${color_normal}") Version: $(kodi_version)"
    echo "    MySQL DB:      $(export MYSQL_PWD=$(get_kodi_setting 'pass'); mysqladmin --user $(get_kodi_setting 'user') --host $(get_kodi_setting 'host') --port $(get_kodi_setting 'port') ping > /dev/null 2>&1 && echo "${color_ok}   Active ${color_normal}" || echo "${color_fail}   Stopped   ${color_normal}") Host: $(get_kodi_setting)"
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
}

PrintDiskSpaceInformation(){
    drive_path_dir="${1:-/}"  # mount drive to check

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
}

GetSystemInformation() {
    sys_load=$(cut -f1 -d ' ' /proc/loadavg)

    swap_used=$(vmstat -s | grep 'used swap' | grep --only-matching '[0-9]*')
    swap_total=$(vmstat -s | grep 'total swap' | grep --only-matching '[0-9]*')
    swap_usage=$(bc <<< "scale=2; $swap_used * 100 / $swap_total" | awk '{printf "%.1f%\n", $0}' 2>/dev/null)

    logged_in=$(who | wc -l)

    memory_used=$(vmstat -s | grep 'used memory' | grep --only-matching '[0-9]*')
    memory_total=$(vmstat -s | grep 'total memory' | grep --only-matching '[0-9]*')
    memory_usage=$(bc <<< "scale=2; $memory_used * 100 / $memory_total" | awk '{printf "%.0f%\n", $0}' 2>/dev/null)

    processes=$(ps -A | wc -l)

    # System uptime
    system_uptime=$(uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/){if ($9=="min") {d=$6;m=$8} else {d=$6;h=$8;m=$9}} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes"}')

    # CPU temperature
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        cpu=$(</sys/class/thermal/thermal_zone0/temp)
    else
        cpu=0
    fi

    temperature="$(printf %.1f "$(echo "${cpu}" | awk '{print $1 / 1000}')")°C"

    # CPU load, heatmap
    read -r -a cpu_load < /proc/loadavg
    cpu_load_1_heatmap=$(HeatmapGenerator "${cpu_load[0]}" "${core_count}")
    cpu_load_5_heatmap=$(HeatmapGenerator "${cpu_load[1]}" "${core_count}")
    cpu_load_15_heatmap=$(HeatmapGenerator "${cpu_load[2]}" "${core_count}")
    cpu_percent=$(printf %.1f "$(echo "${cpu_load[0]} ${core_count}" | awk '{print ($1 / $2) * 100}')")

    # CPU temperature heatmap
    # If we're getting close to 85°C... (https://www.raspberrypi.org/blog/introducing-turbo-mode-up-to-50-more-performance-for-free/)
    if [ ${cpu} -gt 80000 ]; then
        temp_heatmap=${blinking_text}${red_text}
    elif [ ${cpu} -gt 70000 ]; then
        temp_heatmap=${magenta_text}
    elif [ ${cpu} -gt 60000 ]; then
        temp_heatmap=${blue_text}
    else
        temp_heatmap=${cyan_text}
    fi

    # Number of processes
    processes=$(ps ax | wc -l | tr -d " ")

    # Disk space
    if df -Pk | grep -E '^/dev/root' > /dev/null; then
        disk_space="`df -PkH | grep -E '^/dev/root' | awk '{ print $4 }'` (`df -Pk | grep -E '^/dev/root' | awk '{ print $5 }'` used) on /dev/root"
    else
        disk_space="`df -PkH | grep -E '^/dev/mmcblk0p2' | awk '{ print $4 }'` (`df -Pk | grep -E '^/dev/mmcblk0p2' | awk '{ print $5 }'` used) on /dev/mmcblk0p2"
    fi

    # Memory use, heatmap and bar
    memory_percent=$(awk '/MemTotal:/{total=$2} /MemFree:/{free=$2} /Buffers:/{buffers=$2} /^Cached:/{cached=$2} END {printf "%.1f", (total-free-buffers-cached)*100/total}' '/proc/meminfo')
    memory_heatmap=$(HeatmapGenerator "${memory_percent}")

    # Get pi IP address, hostname and gateway
    pi_hostname=$(hostname)
    #pi_ip_address=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
    pi_ip_address=$(ip r | grep 'default' | awk '{print $9}')
    pi_ip6_address=$(ip addr | grep 'state UP' -A4 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
    pi_gateway=$(ip r | grep 'default' | awk '{print $3}')

    pi_external_ip="$(wget -qqO- 'https://duckduckgo.com/?q=what+is+my+ip' | grep -Pow 'Your IP address is \K[0-9.]+')"
}

PrintSystemInformation() {
    #Uptime and Users
    printf "    %-10s%-39s %-10s %-6s\\n" "Uptime:" "${system_uptime}" "Users logged in:" "${logged_in}"

    # CPU temp, load, percentage
    printf "    %-10s${temp_heatmap}%-10s${reset_text} %-10s${cpu_load_1_heatmap}%-4s${reset_text}, ${cpu_load_5_heatmap}%-4s${reset_text}, ${cpu_load_15_heatmap}%-7s${reset_text} %-10s %-6s\\n" "CPU Temp:" "${temperature}" "CPU Load:" "${cpu_load[0]}" "${cpu_load[1]}" "${cpu_load[2]}" "CPU Load:" "${cpu_percent}%"

    printf "    %-10s%-10s%-10s%4s               %-10s %-8s\\n\\n" "Memory:" "${memory_percent}%" "Swap usage:"  "${swap_usage}" "Processes:" "${processes}"
}

PrintNetworkInformation() {
    printf "    %-14s%-19s\\n" "Hostname:" "${pi_hostname}"
    if [ -z $pi_ip_address ]; then
        for interface in $(/sbin/ifconfig -a -s | grep --only-matching '^[^\ ]*' | grep -v 'Iface\|lo'); do
            ip="$(/sbin/ifconfig ${interface} | grep --only-matching '[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*' | head -1)"
            [ ! -z $ip ] && printf "    %-14s%-19s %-10s%-29s\\n"  "${interface}:" "${ip}"
        done
    else
        printf "    %-14s%-19s %-10s%-29s\\n" "IPv4 Adr:" "${pi_ip_address}" "IPv6 Adr:" "${pi_ip6_address}"
    fi
    printf "    %-14s%-19s\\n" "Gateway:" "${pi_gateway}"
    [ ! -z $pi_external_ip ] || pi_external_ip="${color_fail}Internet Down${color_normal}"
    printf "    %-14s%-19s\\n" "External IP:" "${pi_external_ip}"
}

PrintServiceInformation
echo
PrintDiskSpaceInformation

cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
[ "$cores" -eq "0" ] && cores=1
threshold="${cores:-1}.0"
if [ $(echo "0.13 < $threshold" | bc) -eq 1 ]; then
    GetSystemInformation

    #echo "${bold_text}SYSTEM =========================================================================${reset_text}"
    echo
    echo -n "System information as of "
    /bin/date
    echo
    PrintSystemInformation
fi

# Network
#echo "${bold_text}NETWORK ========================================================================${reset_text}"
echo "Network:"
PrintNetworkInformation