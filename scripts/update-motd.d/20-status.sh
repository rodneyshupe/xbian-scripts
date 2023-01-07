#!/usr/bin/env bash
#
#    20-status - display status
#

# To be stored in /etc/update-motd.d/20-status

export TERM=xterm-256color
/usr/local/bin/sys-status
