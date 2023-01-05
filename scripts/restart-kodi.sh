#!/usr/bin/env bash

#OSMC Method
#echo "Restarting Kodi..."
#sudo systemctl restart mediacenter

#XBian Method
if ( /sbin/status xbmc 2>/dev/null | grep --quiet running ); then
    echo "Restarting Kodi..."
    sudo stop xbmc && sudo start xbmc
else
    echo "Stopping Kodi..."
    sudo stop xbmc
    if ( ! ( /sbin/status xbmc 2>/dev/null | grep --quiet 'stop/waiting' ) ); then
        echo "Killing Kodi..."
        sudo kill -9 $(ps -A | grep -i kodi | grep --only-matching '[0-9]*' 2>&1 | head -n 1)
        MSG="Waiting for Kodi to fully stop: "
        while ( ! ( /sbin/status xbmc 2>/dev/null | grep --quiet 'stop/waiting' ) ); do
            COUNT=$((${COUNT} + 1))
            echo -ne "\r\e[0K${MSG} ${COUNT}s"
            sleep 1
        done
        echo " Stopped."
    fi
    echo "Starting Kodi..."
    sudo start xbmc
fi
