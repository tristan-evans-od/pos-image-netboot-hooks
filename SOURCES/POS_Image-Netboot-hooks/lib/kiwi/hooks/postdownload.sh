if [ -n "$FETCH_FILE_TEMP_DIR" ]; then
	if [ -n "$FETCH_FILE_TEMP_FILE" ] ; then
		rm "$FETCH_FILE_TEMP_FILE"
	fi
fi

openLUKSDevices

# Log to the branch server that we are successful (TE)
/etc/init.d/syslog start
/usr/sbin/busybox logger -t "KIWI Imaging" "Success!" 
