#!/usr/bin/env bash

echo "Kodi Version: $(dpkg -l | grep 'xbian-package-xbmc ' | awk '{ print $3 }')"
echo "XBian Version: $(grep PRETTY_NAME /etc/os-release | sed 's/.*"\([^"]*\)"/\1/')"
