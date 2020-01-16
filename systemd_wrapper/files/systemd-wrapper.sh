# vim: tabstop=4 shiftwidth=4 fenc=utf-8 spell spelllang=en cc=120
#
#          FILE: systemctl-shell-wrapper.bash
#   DESCRIPTION: Wrapper script to aid and shorten systemd commands
#       LICENSE: Apache 2.0
#       CREDITS: http://github.com/yaffare/systemd-shell-wrapper 
#   MODIFIED BY: http://github.com/mortn/systemd-shell-wrapper 
# MODIFIED MORE: gravattj
#  INSTALLATION: wget -SO/etc/profile.d/systemd-wrapper.sh [Raw URL to this]
#

# Exit if not BASH_VERSION is set
if [ -z "$BASH_VERSION" ]; then	return; fi

if [[ -f /etc/systemd/shell-wrapper.conf ]]; then
	source /etc/systemd/shell-wrapper.conf
else
	HIDEDAEMONS=()
	#console-getty console-shell debug-shell ftpd nscd sshdgenkeys \
	#	systemd-readahead-collect systemd-readahead-drop systemd-readahead-replay)
fi

# some people seem to not have /usr/bin in $PATH when using sudo
if [ -x $(which systemctl) ];then _systemctl=$(which systemctl); else _systemctl="/bin/systemctl";fi 
if [ -x $(which journalctl) ];then _journalctl=$(which journalctl); else _journalctl="/bin/journalctl";fi 


s.start()       { s_systemctl "start"   $1; }
s.stop()        { s_systemctl "stop"    $1; }
s.restart()     { s_systemctl "restart" $1; }
s.reload()      { s_systemctl "reload"  $1; }
s.enable()      { s_systemctl "enable"  $1; }
s.disable()     { s_systemctl "disable" $1; }
s.status()      { s_systemctl "status"  $1; }
s.listfailed()  { $_systemctl --failed; }
s.analyze()     { systemd-analyze $*; }
s.wants()       { $_systemctl show -p "Wants" $1; }
s.logsize()     { s_exec "${_journalctl}"" --disk-usage"; }
s.list()        { s_list_services "list"; }
s.listall()		{ s_listall_services "list"; }
s.log()         { s_journalctl "$@"; }
s.logfollow()   { $_journalctl -f "$@"; }
s.tree()        { s_exec "/usr/bin/systemd-cgls --all"; }
s.logtruncate() {
	s_exec "${_systemctl}"" start systemd-journal-flush.service"
	s_exec "/bin/rm /var/log/journal/""$(cat /etc/machine-id)""/system@*"
	s_exec "${_systemctl}"" kill --kill-who=main --signal=SIGUSR2 systemd-journald.service"
}

# Function to unify regex matching, so we don't have to duplicate
# the regular expression. It returns the success of failure in matching $1
# $1: unit name to match
s_match_unit_name() {
	# ^(([^@.]*)(@([^.]*))?)(\.(.*))?$
	# ([^@.]*) = matches any starting character that is not a @ and a .
	#            This is the unit name, per se.
	# (@([^.]*))? = matches any template parameter, if present.
	# (\.(.*))? = matches the service type, if present.
	# The array BASH_REMATCH will be fileed with the following elements,
	# if the match happens:
	# 0: the whole unit name
	# 1: the unit name, with possible template parameter
	# 2: the basic unit name, without parameter
	# 3: @<template parameter>
	# 4: <template parameter>
	# 5: .<unit type>
	# 6: <unit type>
	[[ "$1" =~ ^(([^@.]*)(@([^.]*))?)(\.(.*))?$ ]]
}

# $1 unit name, with possible type
# $2 default unit type, to be returned if not found in $1
s_get_unit_type() {
	local defType=${2:-service}
	if s_match_unit_name "$1"; then
		echo "${BASH_REMATCH[6]:-$defType}"
	fi
}

# $1 unit name, with possible template parameter
s_get_template_parameter() {
	if s_match_unit_name "$1"; then
		echo "${BASH_REMATCH[4]}"
	fi
}

# Returns the pure unit name and optional template parameter
# $1 input unit name, with possible "address" and type
s_get_unit_name() {
	if s_match_unit_name "$1"; then
		echo "${BASH_REMATCH[1]}"
	fi
}

# Returns the unit name, without any template parameter and unit type
s_get_basic_unit_name() {
	if s_match_unit_name "$1"; then
		echo "${BASH_REMATCH[2]}"
	fi
}

s_systemctl() {
	# allow full status listing
	if [[ "$1"=="status" && -z $2 ]]; then ${_systemctl} status; return; fi
	unitType="$(s_get_unit_type $2 $3)"
	unitName="$(s_get_unit_name $2)"
	daemon="$unitName.$unitType"
	if [[ $(s_daemon_exists $daemon $unitType) == 1 ]]; then
		echo -e "\e[1;31m:: \e[1;37m ${daemon/.service/} daemon does not exist\e[0m"; return
	fi
	s_exec "/bin/true" # if sudo then ask for password now to avoid messing up the output later
	case $1 in
		start|stop|restart|reload)
			systemctl -q is-active "${daemon}" >& /dev/null
			if [[ $? -eq 0 ]]; then
				if [[ "$1" == "start" ]]; then echo -e "\e[1;31m:: \e[1;37m ${daemon/.service/} daemon is already running\e[0m"; return; fi
			else
				if [[ "$1" != "start" ]]; then
					echo -e "\e[1;31m:: \e[1;37m ${daemon/.service/} daemon is not running\e[0m";
					if [[ "$1" != "restart" ]]; then return; fi
				fi
			fi
			if [[ "$1" == "start" ]];   then echo -en "\e[1;34m:: \e[1;37m Starting ${daemon/.service/} daemon\e[0m"; cols=25; fi
			if [[ "$1" == "stop" ]];    then echo -en "\e[1;34m:: \e[1;37m Stopping ${daemon/.service/} daemon\e[0m"; cols=25; fi
			if [[ "$1" == "restart" ]]; then echo -en "\e[1;34m:: \e[1;37m Restarting ${daemon/.service/} daemon\e[0m"; cols=27; fi
			if [[ "$1" == "reload" ]];  then echo -en "\e[1;34m:: \e[1;37m Reloading ${daemon/.service/} daemon\e[0m"; cols=26; fi
			s_exec "${_systemctl} -q ${1} ${daemon}"
			if [[ $? -eq 0 ]]; then 
				s_msg ${daemon/.service/} $cols 7 "DONE" 
			else 
				s_msg ${daemon/.service/} $cols 1 "FAIL"
				s_systemctl "status" $daemon
			fi
			;;
		enable|disable)
			if [[ ! "${daemon}" =~ @ ]]; then # sadly is-enabled does not work as expected for "@" services like dhcpcd@eth0
				if ${_systemctl} -q is-enabled "${daemon}" >& /dev/null; then
					if [[ "$1" == "enable" ]]; then echoerror "${daemon/.service/} daemon is already enabled"; return; fi
				else
					if [[ "$1" == "disable" ]]; then echo -e "\e[1;31m:: \e[1;37m ${daemon/.service/} daemon is not enabled\e[0m"; return; fi
				fi
			fi
			f=${1:0:1}
			echo -en "\e[1;34m:: \e[1;37m ""${f^^}""${1:1:${#1}-2}""ing ${daemon/.service/} daemon\e[0m"
			if [[ "$1" == "enable" ]]; then cols=25; else cols=26; fi
			s_exec "${_systemctl} -q ${1} ${daemon}"
			if [[ $? -eq 0 ]]; then s_msg ${daemon/.service/} $cols 7 "DONE"; else s_msg ${daemon/.service/} $cols 1 "FAIL"; fi
			;;
		status)
			${_systemctl} status ${daemon}
			;;
	esac
}

s_journalctl() {
	unitType="$(s_get_unit_type $1)"
	unitName="$(s_get_unit_name $1)"
	daemon="$unitName.$unitType"
	if [[ $(s_daemon_exists "${daemon}" $unitType) == 0 ]]; then
		options=""; for ((i=1; i<$#; ++i )) ; do options="${options}""${!i}"" "; done
		echo "${_journalctl} --all $options _SYSTEMD_UNIT=${daemon}";
		s_exec "${_journalctl} --all $options _SYSTEMD_UNIT=${daemon}";
	else
		echo "${_journalctl} --all $*";
		s_exec "${_journalctl} --all $*";
	fi
}

s_listall_services () { $_systemctl --no-legend list-unit-files \
	|	{
			while read -r daemon daemonstate ; do

				# support for "@" stuff like dhcpcd@eth0 dhcpcd@eth1 ...
				if [[ "${daemon:${#daemon}-9}" == "@.service" ]]; then
					daemons=$(${_systemctl} --no-legend -t service | grep -o "${daemon/.service/}[A-Za-z0-9_/=:.-]*")
					if [[ "${daemons[0]}" == "" ]]; then daemons=($daemon); fi # when no instance of "@" service is started it appears just as dhcpcd@
				else
					daemons=($daemon)
				fi

				for daemon in $daemons; do
					if s_hidedaemon "${daemon/.service/}"; then continue; fi;
					if [[ "${1}" == "list" ]]; then
						echo -en "\e[1;34m[";
					elif [[ "${1}" == "enabled" || "${1}" == "disabled" ]]; then
						if [[ "${1}" == "${daemonstate}" ]]; then printf "%s\n" "${daemon/.service/}"; fi
						continue
					fi
					${_systemctl} -q is-active "${daemon}" >& /dev/null
					if [[ $? -eq 0 ]]; then
							if [[ "${1}" == "list" ]]; then
								echo -en "\e[1;37mSTARTED"
							else
								if [[ "${1}" != "stopped" ]]; then printf "%s\n" "${daemon/.service/}"; fi
							fi
					else
							if [[ "${1}" == "list" ]]; then
								echo -en "\e[1;31mSTOPPED"
							else
								if [[ "${1}" != "started" ]]; then printf "%s\n" "${daemon/.service/}"; fi
							fi
					fi
					if [[ "${1}" != "list" ]]; then continue; fi
					echo -en "\e[1;34m][\e[1;37m"

					# !!! in the rare case of having two or more "@" instances (dhcpcd@) from the same service having different states (en/disabled) this actually shows wrong results
					if [[ "${daemonstate}" == "enabled" ]]; then
							echo -n "AUTO"
					else
							echo -n "    "
					fi
					echo -en "\e[1;34m]\e[0m "
					echo "${daemon/.service/}"
				done

			done;
		}
}

s_list_services () { $_systemctl --no-legend -t service list-unit-files | grep -v static  \
	|	{
			while read -r daemon daemonstate ; do

				# ignore symlinks like crond.service (they dont work anyway, you can start/stop but not enable/disable)
				if [[ -h "/usr/lib/systemd/system/$daemon" ]]; then continue; fi

				# support for "@" stuff like dhcpcd@eth0 dhcpcd@eth1 ...
				if [[ "${daemon:${#daemon}-9}" == "@.service" ]]; then
					daemons=$(${_systemctl} --no-legend -t service | grep -o "${daemon/.service/}[A-Za-z0-9_/=:.-]*")
					if [[ "${daemons[0]}" == "" ]]; then daemons=($daemon); fi # when no instance of "@" service is started it appears just as dhcpcd@
				else
					daemons=($daemon)
				fi

				for daemon in $daemons; do
					if s_hidedaemon "${daemon/.service/}"; then continue; fi;
					if [[ "${1}" == "list" ]]; then
						echo -en "\e[1;34m[";
					elif [[ "${1}" == "enabled" || "${1}" == "disabled" ]]; then
						if [[ "${1}" == "${daemonstate}" ]]; then printf "%s\n" "${daemon/.service/}"; fi
						continue
					fi
					${_systemctl} -q is-active "${daemon}" >& /dev/null
					if [[ $? -eq 0 ]]; then
							if [[ "${1}" == "list" ]]; then
								echo -en "\e[1;37mSTARTED"
							else
								if [[ "${1}" != "stopped" ]]; then printf "%s\n" "${daemon/.service/}"; fi
							fi
					else
							if [[ "${1}" == "list" ]]; then
								echo -en "\e[1;31mSTOPPED"
							else
								if [[ "${1}" != "started" ]]; then printf "%s\n" "${daemon/.service/}"; fi
							fi
					fi
					if [[ "${1}" != "list" ]]; then continue; fi
					echo -en "\e[1;34m][\e[1;37m"

					# !!! in the rare case of having two or more "@" instances (dhcpcd@) from the same service having different states (en/disabled) this actually shows wrong results
					if [[ "${daemonstate}" == "enabled" ]]; then
							echo -n "AUTO"
					else
							echo -n "    "
					fi
					echo -en "\e[1;34m]\e[0m "
					echo "${daemon/.service/}"
				done

			done;
		}
}

# $1: Optional type of unit. The default is service
s_daemon_exists() {
	unitType="$(s_get_unit_type $1 ${2:-service})"
	baseName="$(s_get_basic_unit_name $1)"
	if ${_systemctl} --no-legend -t "$unitType" list-unit-files | grep -v static | (grep -Eq "^$baseName(@.*)?\.$unitType" >& /dev/null); then echo 0; else echo 1; fi
}

s_msg() {
	printf "%s%*s%s%s%s%s%s%s\n" "$(tput bold ; tput setaf 4)" $(($(tput cols)-${#1}-${2})) "[" "$(tput bold ; tput setaf $3)" "${4}" "$(tput bold ; tput setaf 4)" "]" "$(tput sgr0)"
}

s_exec() {
	if [[ $EUID -ne 0 ]]; then eval "sudo $@"; else eval "$@"; fi
}

s_hidedaemon() {
	for hidedaemon in ${HIDEDAEMONS[@]}; do if [[ "$1" == "$hidedaemon" ]]; then return 0; fi; done; return 1;
}

# $1: optional type
s_bashcompletion_list_by_type () {
	${_systemctl} --no-legend -t $1 list-unit-files  \
		|	{ while read -r a b  ; do printf "%s\n" "${a}"; done; }
}

s_bashcompletion () {
	local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
	local verb comps

	if [[ "${1}" == "target" ]]; then comps=$( s_bashcompletion_list_by_type "target" ); 
	else comps=$( s_list_services "${1}" ); fi
	COMPREPLY=( $(compgen -W '$comps' -- "$cur") )
}

_COLORS=${BS_COLORS:-$(tput colors 2>/dev/null || echo 0)}
__detect_color_support() {
	if [ $? -eq 0 ] && [ "$_COLORS" -gt 2 ]; then
		RC="\033[1;31m"
		GC="\033[1;32m"
		BC="\033[1;34m"
		YC="\033[1;33m"
		EC="\033[0m"
	else 
		RC=""; GC=""; BC=""; YC=""; EC=""
	fi
}
__detect_color_support

_print(){
	_msg_type=$1

}
echoinfo() { printf "${GC} ::  INFO${EC}: %s\n" "$@"; }
echowarn() { printf "${YC} >>  WARN${EC}: %s\n" "$@"; }
echoerror(){ printf "${RC} !! ERROR${EC}: %s\n" "$@" 1>&2; }
echodebug() { [ "$_ECHO_DEBUG" -eq 0 ] && printf "${BC} * DEBUG${EC}: %s\n" "$@"; }
__check_command_exists() { command -v "$1" > /dev/null 2>&1; }


s_bashcompletion_start () { s_bashcompletion "stopped"; return 0; }
s_bashcompletion_stop () { s_bashcompletion "started"; return 0; }
s_bashcompletion_restart () { s_bashcompletion "started"; return 0; }
s_bashcompletion_reload () { s_bashcompletion "started"; return 0; }
s_bashcompletion_enable () { s_bashcompletion "disabled"; return 0; }
s_bashcompletion_disable () { s_bashcompletion "enabled"; return 0; }
s_bashcompletion_status () { s_bashcompletion ""; return 0; }
s_bashcompletion_wants () { s_bashcompletion "target"; return 0; }
s_bashcompletion_log () { s_bashcompletion ""; return 0; }
s_bashcompletion_logfollow () { s_bashcompletion ""; return 0; }

complete -F s_bashcompletion_start s.start
complete -F s_bashcompletion_stop s.stop
complete -F s_bashcompletion_restart s.restart
complete -F s_bashcompletion_reload s.reload
complete -F s_bashcompletion_enable s.enable
complete -F s_bashcompletion_disable s.disable
complete -F s_bashcompletion_status s.status
complete -F s_bashcompletion_wants s.wants
complete -F s_bashcompletion_log s.log
complete -F s_bashcompletion_logfollow s.logfollow

#if [ "$BASH_VERSION" ] && [ -n "$PS1" ] && echo $SHELLOPTS | grep -v posix >>/dev/null; then
#    if [ -f /etc/profile.d/systemd-shell-wrapper.bash ]; then
#        source /etc/profile.d/systemd-shell-wrapper.bash
#    fi
#elif [ "$ZSH_VERSION" ] && [ -n "$PS1" ]; then
#    if [ -f /etc/profile.d/ ]; then
#        source /etc/profile.d/
#    fi
#fi
