if [ -n "$FETCH_FILE_TEMP_DIR" ]; then
	if [ -n "$FETCH_FILE_TEMP_FILE" ] ; then
		rm "$FETCH_FILE_TEMP_FILE"
	fi
fi

openLUKSDevices

logToSyslog "The POS image deployment process was successful!" 
