#!/bin/bash

StartContainerFromYml(){
	local _pod _v _services _s _r _i _f _a _x
	local _dockerimage _runflags _runargs
	_pod=$(BaseFromYmlFileName $1)
	# echo; echo; echo DEBUG; cat $1|ParseYaml ${_pod}_; echo; echo; echo
	eval $(cat $1|ParseYaml ${_pod}_)

	_services="$(eval echo \$${_pod}_services)"
	# echo DEBUG _services=$_services
	for _s in $(echo $_services); do
		DEBUG StartContaingerFromYml Will start $_s
		_x="${_pod}_services_${_s}_"
		_runargs="$(eval echo \$${_x}runargs)" # e.g: /bin/bash
		_runflags="$(eval echo \$${_x}runflags)" # Feks: -itp 8080:8080 -d
		_dockerimage=$(eval echo \$${_x}dockerimage)
		DEBUG $_s dockerimage: $_dockerimage Flags=${_runflags} Args: ${_runargs}
		LoadIfFileAndNotLoaded $_dockerimage
		docker run ${_runflags} $_s ${_runargs}
	done
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
	local news=$(Actual $YmlDir) _x _pod
	if [ "$Adopted" != "$news" ];then
		for _x in $(AnotinB "$Adopted" "$news");do
			_pod=$(BaseFromYmlFileName $_x)
			INFO Stopping pod $_pod from missing $_x 
			Recall $_pod
			_action="true";
		done
		for _x in $(AnotinB "$news" "$Adopted");do
			_pod=$(BaseFromYmlFileName $_x)
			INFO Starting pod $_pod from $_x 
			StartContainerFromYml $_x
			Memorize $_pod $_x
			_action="true";
		done
		Adopted=$news
	else
		DEBUG No change to Adopt
	fi
}
AnotinB(){
	local _a _b	
	for _a in $(echo $1|tr : " "); do
		for _b in $(echo $2|tr : " "); do
			if [ $_a = $_b ];then continue 2; fi
		done
		echo $_a
	done
}
BaseFromYmlFileName(){ basename $1|sed 's/\.yml$//g';}
Actual(){ 
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
			ERROR You must start dockerdeamon first, retry $retry
			sleep 3
		else
			DEBUG dockerdeamon OK
			return
		fi
		retry=$((retry - 1));
	done
	ERROR Giveup waiting on dockerdeamon retries: $retry FAIL
	exit 1
}
StopAndRemoveContainers(){
	if [ "$(docker ps -aq)" != "" ];then
		docker stop --time=3 $(docker ps -aq) > /dev/null
		docker rm -f $(docker ps -aq) > /dev/null
		INFO docker containers stopped and removed
		# docker rmi -f $(docker images -aq); echo Image cleaned
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
UbuntuYaml(){
	# Fasit: docker run -itd ubuntu bash
	cat <<-!
		services: ubuntu
		  ubuntu:
		    runflags: -itd 
		    runargs: bash
	!
}
FotoregYaml(){
	local e=""
	e="$e -e POSTGRES_PASSWORD=pass"
	e="$e -e POSTGRES_USER=jhs009"
	e="$e -e POSTGRES_DB=fangefoto"
	e="$e --name mypg"
	e="$e -d"
	cat <<-!
		services: mypg fotoreg
		  mypg:
		    dockerimage: /z/docker/mypg.dockerimage
		    runflags: $e --name mypg -d
		  fotoreg: 
		    dockerimage: /z/docker/fotoreg.dockerimage
		    runflags: -d -p 9191:9191 --link mypg:mypg
	!
}
MakeYamls(){
	FotoregYaml 	> $YmlDir/fotoregws.yml
	UbuntuYaml 	> $YmlDir/myubuntu.yml
}
verboseLevel=2 # 0==Only_ERROR, 1==INFO_AndBelow, 2==DEBUG_AndBelow
YmlDir=/z/deploy/yml
Adopted=""
Echo(){ echo $(date "+%Y-%m-%d %H:%M.%S") $*; }
ERROR(){ 	if [ "$verboseLevel" -ge 0 ];then Echo ERROR 	$*;fi; }
INFO(){ 	if [ "$verboseLevel" -ge 1 ];then Echo INFO 	$*;fi; }
DEBUG(){ 	if [ "$verboseLevel" -ge 2 ];then Echo DEBUG 	$*;fi; }

Doit(){
	# MakeYamls
	# INFO Argumenter ved start $*
	DieIfNotDockerd
	# ...LoadIfNotLoadednot-implementd
	# StopAndRemoveContainers; 
	# if [ "$1" = "stop" ];then exit; fi
        # Run
	on_ctrl_c() {
		DEBUG Trapped CTRL-C
		# StopAndRemoveContainers
		DEBUG Normal end
		exit 0;
	}
	on_hup() {
		DEBUG Refreshing on HUP
		Adopt
		return;
	}
	trap on_ctrl_c INT;
	trap on_hup HUP;
	Adopt
	DEBUG "To continue, do kill -HUP $$ or ctrl_c"
	DEBUG Made /tmp/refresh.sh with pid=$$
	echo kill -HUP $$ > /tmp/refresh.sh
	while :;do sleep 0.3; done # Consider 0.3 to be more snappy
}
Reverse(){ echo $*|awk '{for (i=NF; i>0; i--) printf "%s ",$(i);}'; }
Recall(){
	local _pod=$1 _v _services
	_v=$(eval echo \$mem_$_pod)
	# DEBUG Recall _v=$_v
	# echo $_v|base64 -d|zcat|ParseYaml
	eval $(echo $_v|base64 -d|zcat|ParseYaml $_pod)
	_v=${_pod}services
	_services=$(eval echo \$${_v})
	for _v in $(Reverse $_services); do
		DEBUG Recall Will halt Service $_v
		docker stop $_v
	done
	
}
Memorize(){
	# local _pod=$1 _ymlfile=$2 _r _a _i
	eval mem_$1=$(cat $2|gzip|base64 -w0)
	DEBUG memorized $1
}
Doit $*
