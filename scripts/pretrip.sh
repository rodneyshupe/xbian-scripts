#!/usr/bin/env bash

sudo /home/$USER/.scripts/kodi-remove-watched.sh | sudo tee -a /var/log/$USER/kodi-removed-watched.log
