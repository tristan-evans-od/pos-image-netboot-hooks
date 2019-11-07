
if [ $LOCAL_BOOT != "no" ];then
	if [ -f "/srv/SLEPOS/KIWI/config.$DHCPCHADDR" ]; then
		SRV_CONFIG="/srv/SLEPOS/KIWI/config.$DHCPCHADDR"
	elif [ -f "/srv/SLEPOS/KIWI/config.default" ]; then
		SRV_CONFIG="/srv/SLEPOS/KIWI/config.default"
	fi
	
	if [ -n "$SRV_CONFIG" ]; then
		Echo "Using local config '$SRV_CONFIG'"
		unset root
		CONFIG=/etc/config.netclient
		cp -f "$SRV_CONFIG" "$CONFIG"
		importConfigFile
		LOCAL_BOOT="no"
		SERVER=/srv/SLEPOS/
		SERVERTYPE=local
		startHaveged
		# set luks pw for image device to allow
		# check for installed image without entering pw
		setImageLuksPass
	else
		Echo "No local config found"
		if [ "x$root" == "x/srv/SLEPOS" ]; then
			systemException "Can't boot from service partition" "reboot"
		fi
	fi
fi
