#!/usr/bin/env bash
#
#    15-header - display logo
#

export TERM=xterm-256color

host="$(hostname --fqdn)"
[ -z "${host}" ] && host="$(uname -n)"
host="${host}                            "
host="$(tput bold)$(tput setaf 3)${host:0:28}$(tput sgr0)"

echo "
                           $(tput setaf 153)%%%$(tput setaf 60)*****$(tput sgr0)
                        $(tput setaf 153)%%%%%$(tput setaf 60)****$(tput sgr0)
$(tput bold)$(tput setaf 208)  #####################$(tput setaf 153)%%%%$(tput setaf 60)****$(tput setaf 208)########$(tput sgr0) 
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)       %%%      %%%%$(tput setaf 60)****       $(tput setaf 208)###$(tput sgr0) 
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)        %%%%   %%%%$(tput setaf 60)***         $(tput setaf 208)###$(tput sgr0) $(tput bold)$(tput setaf 6) __  __ _ _ _ _$(tput sgr0)
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)          %%% %%%$(tput setaf 60)****          $(tput setaf 208)###$(tput sgr0) $(tput bold)$(tput setaf 6)|  \/  (_) | (_)_ __ ____ _ _  _ ___$(tput sgr0)
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)           %%%%$(tput setaf 60)****            $(tput setaf 208)###$(tput sgr0) $(tput bold)$(tput setaf 6)| |\/| | | | | \ V  V / _\\\` | || (_-<$(tput sgr0)
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)          %%%%%%%$(tput setaf 60)****          $(tput setaf 208)###$(tput sgr0) $(tput bold)$(tput setaf 6)|_|  |_|_|_|_|_|\_/\_/\__,_|\_, /__/$(tput sgr0)
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)        %%%%   %%%%$(tput setaf 60)****        $(tput setaf 208)###$(tput sgr0) ${host}$(tput bold)$(tput setaf 6)|__/$(tput sgr0)
$(tput bold)$(tput setaf 208)  ###$(tput setaf 153)       %%%      %%%%$(tput setaf 60)****       $(tput setaf 208)###$(tput sgr0) 
$(tput bold)$(tput setaf 208)  #####################$(tput setaf 153)%%%%$(tput setaf 60)****$(tput setaf 208)########$(tput sgr0) 
                        $(tput setaf 153)%%%%%$(tput setaf 60)****$(tput sgr0) 
$(tput bold)$(tput setaf 208)        X B I A N           $(tput setaf 153)%%$(tput setaf 60)****$(tput sgr0)
"