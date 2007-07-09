#!/bin/sh -e
### BEGIN INIT INFO
# Provides:          apache2
# Required-Start:    $local_fs $remote_fs $network $syslog
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
### END INIT INFO
#
# apache2		This init.d script is used to start apache2.
#			It basically just calls apache2ctl.

ENV="env -i LANG=C PATH=/usr/local/bin:/usr/bin:/bin"

#[ `ls -1 /etc/apache2/sites-enabled/ | wc -l | sed -e 's/ *//;'` -eq 0 ] && \
#echo "You haven't enabled any sites yet, so I'm not starting apache2." && \
#echo "To add and enable a host, use addhost and enhost." && exit 0

#edit /etc/default/apache2 to change this.
HTCACHECLEAN_RUN=auto
HTCACHECLEAN_MODE=daemon
HTCACHECLEAN_SIZE=300M
HTCACHECLEAN_DAEMON_INTERVAL=120
HTCACHECLEAN_PATH=/var/cache/apache2/mod_disk_cache
HTCACHECLEAN_OPTIONS=""

set -e
if [ -x /usr/sbin/apache2 ] ; then
	HAVE_APACHE2=1
else
	echo "No apache MPM package installed"
	exit 0
fi

. /lib/lsb/init-functions

test -f /etc/default/rcS && . /etc/default/rcS
test -f /etc/default/apache2 && . /etc/default/apache2

APACHE2="$ENV /usr/sbin/apache2"
APACHE2CTL="$ENV /usr/sbin/apache2ctl"
HTCACHECLEAN="$ENV /usr/sbin/htcacheclean"

check_htcacheclean() {
	[ "$HTCACHECLEAN_MODE" = "daemon" ] || return 1

	[ "$HTCACHECLEAN_RUN"  = "yes"    ] && return 0

	[ "$HTCACHECLEAN_RUN"  = "auto" \
	  -a -e /etc/apache2/mods-enabled/disk_cache.load ] && return 0
	
	return 1
}

start_htcacheclean() {
	$HTCACHECLEAN $HTCACHECLEAN_OPTIONS -d$HTCACHECLEAN_DAEMON_INTERVAL \
			-i -p$HTCACHECLEAN_PATH -l$HTCACHECLEAN_SIZE
				
}

stop_htcacheclean() {
	killall htcacheclean 2> /dev/null || echo ...not running
}

pidof_apache() {
    # if pidof is null for some reasons the script exits automagically
    # classified as good/unknown feature
    PIDS=`pidof apache2` || true
    
    # let's try to find the pid file
    # apache2 allows more than PidFile entry
    # most simple way is to check all of them

    PIDS2=""

    for PFILE in `grep ^PidFile /etc/apache2/* -r | awk '{print $2}'`; do
	[ -e $PFILE ] && PIDS2="$PIDS2 `cat $PFILE`"
    done

    # if there is a pid we need to verify that belongs to apache2
    # for real
    for i in $PIDS; do
	# may be it is not the right way to make second dimension
	# for really huge setups with hundreds of apache processes
	# and tons of garbage in /etc/apache2... or is it?
	for j in $PIDS2; do
    	    if [ "$i" = "$j" ]; then
	      # in this case the pid stored in the
	      # pidfile matches one of the pidof apache
	      # so a simple kill will make it
           	echo $i
              return 0
            fi
        done
    done
    return 1
}

apache_stop() {
	if `$APACHE2 -t > /dev/null 2>&1`; then
		# if the config is ok than we just stop normaly
                $APACHE2CTL graceful-stop
	else
		# if we are here something is broken and we need to try
		# to exit as nice and clean as possible
		PID=$(pidof_apache)

		if [ "${PID}" ]; then
			# in this case it is everything nice and dandy
			# and we kill apache2
			log_warning_msg "We failed to correctly shutdown apache, so we're now killing all running apache processes. This is almost certainly suboptimal, so please make sure your system is working as you'd expect now!"
                        kill $PID
		elif [ "$(pidof apache2)" ]; then
			if [ "$VERBOSE" != no ]; then
                                echo " ... failed!"
			        echo "You may still have some apache2 processes running.  There are"
 			        echo "processes named 'apache2' which do not match your pid file,"
			        echo "and in the name of safety, we've left them alone.  Please review"
			        echo "the situation by hand."
                        fi
                        return 1
		fi
	fi
}

# Stupid hack to keep lintian happy. (Warrk! Stupidhack!).
case $1 in
	start)
		log_daemon_msg "Starting web server" "apache2"
		if $APACHE2CTL start; then
			if check_htcacheclean ; then
				log_progress_msg htcacheclean
				start_htcacheclean || log_end_msg 1
			fi
                        log_end_msg 0
                else
                        log_end_msg 1
                fi
	;;
	stop)
		if check_htcacheclean ; then
			log_daemon_msg "Stopping web server" "htcacheclean"
			stop_htcacheclean
			log_progress_msg "apache2"
		else
			log_daemon_msg "Stopping web server" "apache2"
		fi
		if apache_stop; then
                        log_end_msg 0
                else
                        log_end_msg 1
                fi
	;;
	reload | force-reload)
		if ! $APACHE2CTL configtest > /dev/null 2>&1; then
                    $APACHE2CTL configtest || true
                    log_end_msg 1
                    exit 1
                fi
                log_daemon_msg "Reloading web server config" "apache2"
		if pidof_apache; then
                    if $APACHE2CTL graceful $2 ; then
                        log_end_msg 0
                    else
                        log_end_msg 1
                    fi
                fi
	;;
	restart)
		if check_htcacheclean ; then
			log_daemon_msg "Restarting web server" "htcacheclean"
			stop_htcacheclean
			log_progress_msg apache2
		else
			log_daemon_msg "Restarting web server" "apache2"
		fi
		if ! apache_stop; then
                        log_end_msg 1 || true
                fi
		sleep 10
		if $APACHE2CTL start; then
			if check_htcacheclean ; then
				start_htcacheclean || log_end_msg 1
			fi
                        log_end_msg 0
                else
                        log_end_msg 1
                fi
	;;
	start-htcacheclean)
		log_daemon_msg "Starting htcacheclean"
		start_htcacheclean || log_end_msg 1
		log_end_msg 0
	;;
	stop-htcacheclean)
		log_daemon_msg "Stopping htcacheclean"
			stop_htcacheclean
			log_end_msg 0
	;;
	*)
		log_success_msg "Usage: /etc/init.d/apache2 {start|stop|restart|reload|force-reload|start-htcacheclean|stop-htcacheclean}"
		exit 1
	;;
esac
