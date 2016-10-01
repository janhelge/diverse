#!/bin/bash
verboseLevel=2 # 0==Only_ERROR, 1==INFO_AndBelow, 2==DEBUG_AndBelow
#DockerImages=/z/deploy/docker/hello-world.dockerimage:... # Colon-list
DockerImages=/z/deploy/docker/hello-world.dockerimage
Echo(){ echo $(date "+%Y-%m-%d %H:%M.%S") $*; }
ERROR(){ 	if [ "$verboseLevel" -ge 0 ];then Echo ERROR 	$*;fi; }
INFO(){ 	if [ "$verboseLevel" -ge 1 ];then Echo INFO 	$*;fi; }
DEBUG(){ 	if [ "$verboseLevel" -ge 2 ];then Echo DEBUG 	$*;fi; }

Doit(){
	INFO Argumenter ved start $*
	DieIfNotDockerd
	LoadIfNotLoaded
	StopAndRemoveContainers; 
	if [ "$1" = "stop" ];then exit; fi
        Run
	ctrl_c() {
		DEBUG Trapped CTRL-C
		StopAndRemoveContainers
		DEBUG Normal end
		exit 0;
	}
	trap ctrl_c TERM;
	DEBUG "To continue, do kill -TERM $$"
	while :;do sleep 1; done
	StopAndRemoveContainers
}
LoadIfNotLoaded(){ 
	local img file
	for file in $(echo $DockerImages|tr : ' '); do
		if [ ! -f $file	];then
			ERROR $file is missing, We must exit;
			exit 1;
		fi
		img=$(basename $file|awk -F. '{printf "%s\n",$1;}')
		if [ "$(docker images -q $img)" = "" ];then
			docker load -q --input $file; 
			INFO $img Loaded
		else
			DEBUG $img Was already loaded
		fi
	done
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
Run(){
	local img file hint
	for file in $(echo $DockerImages|tr : ' '); do
		img=$(basename $file|awk -F. '{printf "%s\n",$1;}')
		hint=$(dirname $file)/$img.dockerhint
		if [ -f $hint	];then
			INFO Run using hint $hint
			sh $hint & 
		else
			ERROR  $hint is missing, dont know how to run, must exit;
			exit 1
		fi
	done
}
Doit $*
