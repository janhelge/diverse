#!/bin/bash
Documetation(){ : <<-! | tr -d '#' # >README.md
# DOC: This script tracks the $YmlDir directory for yml-files
# and starts/stops docker containers accordingly. If an yml file
# is removed, and the script is signalled (eg. kill -HUP <pid>), the 
# corresponding docker container(s) is/are terminated. 
#
# This script responds to two signals
#  * INT (aka ctrl-c)  Refreshes 
#        the configuration and adopts to changes
#  * TERM cleanup and terminate
#
# This script is useful on its own, but is also capable
# to run as a slave script of a linux lsb-daemon process such as 
# docker-babysitter-daemon.sh
# 
!
}; # Documetation; exit

verboseLevel=1 # 0==Only_ERROR, 1==INFO_AndBelow, 2==DEBUG_AndBelow
YmlDir=/z/deploy/yml
Doit(){
	DieIfNotDockerd
	# BrutalStopAndRemoveContainers; exit
	MainLoop
	
}
MainLoop(){
	on_ctrl_c() {
		DEBUG Will terminate on CTRL-C
		Adopt /dev/null # Adopt as if no yamls was active
		DEBUG Normal end
		exit 0;
	}
	on_hup() {
		DEBUG Will refresh on HUP
		Adopt $YmlDir
		return;
	}
	trap on_ctrl_c INT;
	trap on_hup HUP;
	Adopt $YmlDir
	DEBUG "To continue, do kill -HUP $$ or ctrl_c"
	echo kill -HUP $$ > /tmp/refresh.sh; DEBUG Made /tmp/refresh.sh with pid=$$
	while :;do sleep 0.3; done # Consider 0.3 to be more snappy
}
Reverse(){ echo $*|awk '{for (i=NF; i>0; i--) printf "%s ",$(i);}'; }
Memorize(){ eval mem_$1=$(cat $2|gzip|base64 -w0); DEBUG memorized $1; }
Docker(){
	local _rc
	echo '# About to run following docker command'
	echo docker $*; docker $*; _rc=$?
	echo '###############################' RC=$_rc
	return $_rc
}

LoadIfFileAndNotLoaded(){
	# local _dockerImageFile=$1
	if [ "$1" = "" ];then DEBUG NoFile nothing to load; return; fi
	if [ ! -f "$1" ];then ERROR dockerImage: $1 missing; exit 1; fi
	local img=$(basename $1|awk -F. '{printf "%s\n",$1;}')
	if [ "$(docker images -q $img)" = "" ];then
		docker load -q --input $1;
		INFO $img Loaded
	else
		DEBUG $img Was already loaded
	fi
}

Adopt(){
	# d1=normally $YmlDir, exept when terminating
	local news=$(Actual $1) _x _pod
	if [ "$Adopted" != "$news" ];then
		for _x in $(AnotinB "$Adopted" "$news");do
			_pod=$(BaseFromYmlFileName $_x)
			INFO Stopping $_pod from memorized $(basename $_x)
			UseMemorizedConfigAndTerminate $_pod
		done
		for _x in $(AnotinB "$news" "$Adopted");do
			_pod=$(BaseFromYmlFileName $_x)
			INFO Starting $_pod from $(basename $_x)
			StartContainerFromYml $_x
			Memorize $_pod $_x
		done
		Adopted=$news
	else
		DEBUG No change to Adopt
	fi
}

AnotinB(){
# Enries is a colon-separated list as in /a/file.yml:/a/file2.yml 
# This function returns enries in $1 that is not in $2. 
# Eg: AnotinB a:b:c a:c returns b
	local _a _b	
	for _a in $(echo $1|tr : " "); do
		for _b in $(echo $2|tr : " "); do
			if [ $_a = $_b ];then continue 2; fi
		done
		echo $_a
	done
}

BaseFromYmlFileName(){ basename $1|sed 's/\.yml$//';}

Actual(){ 
	# Will normally have arg1=$YmlDir, but /dev/null when terminating
	local dir=$1 y accumul colon;
	for y in $(ls $dir/*.yml 2>/dev/null);do
		if [ -f "$y" ];then 
			accumul="${accumul}${colon}$y"; colon=:;
		fi
	done
	if [ "$accumul" != "" ];then echo $accumul; fi
}

DieIfNotDockerd(){
	local retry=3
	while [ $retry -gt 0 ];do
		docker images -q dummy >/dev/null 2>&1
		if [ "$?" -ne 0 ];then
			ERROR Unable to communicate with docker deamon. Will try again
			# ERROR docker deamon is not active, $retry retries left
			sleep 3
		else
			DEBUG Fine, docker deamon responds OK
			return
		fi
		retry=$((retry - 1));
	done
	ERROR This scripts will terminate and FAIL
	exit 1
}

StartContainerFromYml(){
	local _pod _services _serv _x
	local _dockerimage _runflags _runargs
	_pod=$(BaseFromYmlFileName $1)
	# echo; echo; echo DEBUG; cat $1|ParseYaml ${_pod}_; echo; echo; echo
	eval $(cat $1|ParseYaml ${_pod}_)

	_services="$(eval echo \$${_pod}_services)"
	# echo DEBUG _services=$_services
	for _serv in $(echo $_services); do
		DEBUG StartContaingerFromYml Will start $_serv
		_x="${_pod}_services_${_serv}_"
		_runargs="$(eval echo \$${_x}runargs)" # e.g: /bin/bash
		_runflags="$(eval echo \$${_x}runflags)" # e.g: -itp 8080:8080 -d
		_dockerimage=$(eval echo \$${_x}dockerimage)
		# DEBUG $_serv dockerimage: $_dockerimage Flags=${_runflags} Args: ${_runargs}
		LoadIfFileAndNotLoaded $_dockerimage
		docker run ${_runflags} $_serv ${_runargs}
	done
}

UseMemorizedConfigAndTerminate(){
	local _pod=$1 _v _services
	_v=$(eval echo \$mem_$_pod)
	eval $(echo $_v|base64 -d|zcat|ParseYaml ${_pod}_)
	_services=$(eval echo \$${_pod}_services)
	INFO Brings down services in sequence $(Reverse $_services)
	_v=$(docker stop $DockerStopGracetime $(Reverse $_services)); DEBUG Stopped $_v
	_v=$(docker rm $(Reverse $_services)); DEBUG cleaned up $_v
}

BrutalStopAndRemoveContainers(){
	if [ "$(docker ps -aq)" != "" ];then
		docker stop $DockerStopGracetime $(docker ps -aq) # > /dev/null
		docker rm -f $(docker ps -aq) # > /dev/null
		INFO docker containers stopped and removed
		# docker rmi -f $(docker images -aq); INFO All Images cleared
	else
		DEBUG No container to remove.
	fi
}

ParseYaml(){
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo "\034")
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" |
   awk -F$fs -v prefix=$1 '{ indent=length($1)/2; vname[indent]=$2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", prefix,vn, $2, $3);
      }
   }'
}
DockerStopGracetime="--time=1"
# PrivateTemporaryFile=/tmp/slave-tmp-$$.tmp
Adopted=""
Echo(){ echo $(date "+%Y-%m-%d %H:%M.%S") $*; }
ERROR(){ 	if [ "$verboseLevel" -ge 0 ];then Echo ERROR 	$*;fi; }
INFO(){ 	if [ "$verboseLevel" -ge 1 ];then Echo INFO 	$*;fi; }
DEBUG(){ 	if [ "$verboseLevel" -ge 2 ];then Echo DEBUG 	$*;fi; }
Doit $*
