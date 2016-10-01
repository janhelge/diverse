#!/bin/sh
set -e

### BEGIN INIT INFO
# Provides:           docker-babysitter
# Required-Start:     docker $syslog $remote_fs
# Required-Stop:      docker $syslog $remote_fs
# Default-Start:      2 3 4 5
# Default-Stop:       0 1 6
# Short-Description:  the Docker babysitter starts and stops containers
### END INIT INFO

BASE=docker-babysitter
BINARY=/z/deploy/${BASE}-slave.sh
# CONFIG=/z/deploy/${BASE}.config
CHUIDARG="jhs:jhs" # <== Unpriviliged user

PIDFILE=/var/run/$BASE.pid
LOGFILE=/var/log/$BASE.log
DESC="$BASE"

. /lib/lsb/init-functions

if [ -f /etc/default/$BASE ];then . /etc/default/$BASE; fi
if init_is_upstart;then log_failure_msg "$BASE is managed via upstart, try using service $BASE $1"; exit 1; fi
if [ ! -x "$BINARY" ];then log_failure_msg "$BINARY not present or not executable"; exit 1; fi
fail_unless_root() { if [ "$(id -u)" != '0' ]; then log_failure_msg "$DESC must be run as root"; exit 1; fi; }

case "$1" in
	start)
		fail_unless_root
		log_begin_msg "Starting $DESC"
		echo "#" >> $LOGFILE
		echo $(date "+%Y-%m-%d %H:%M.%S") $(basename $0) starts $BINARY >> $LOGFILE
		chown $CHUIDARG $LOGFILE
		start-stop-daemon --start \
			--background \
			--no-close \
			--chuid "$CHUIDARG" \
			--exec "$BINARY" \
			--pidfile "$PIDFILE" \
			--make-pidfile \
			-- "$CONFIG" >> "$LOGFILE" 2>&1
		log_end_msg $?
		;;
		
	stop)
		fail_unless_root
		log_begin_msg "Stopping $DESC"
		start-stop-daemon --stop \
			--remove-pidfile \
			--pidfile "$PIDFILE"
		log_end_msg $?
		;;
		
	restart|force-reload)
		fail_unless_root
		$0 stop # Dette betinger absolutt path og executable
		sleep 5; # Give docker some time to stop containers
		$0 start
		;;
		
	status)
		status_of_proc -p "$PIDFILE" "$BINARY" "$DESC"
		;;
		
	*)
		echo "usage: $0 {start|stop|restart|status}"
		exit 1
		;;
esac
