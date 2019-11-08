	#======================================
	# Connection/access check for SERVER
	#--------------------------------------
	Echo "Checking for config file: config.$DHCPCHADDR"
	fetchFile KIWI/config.$DHCPCHADDR $CONFIG

	# detect connection-related transfer problems, missing file should not trigger this:
	if [ ! -s $CONFIG ] && echo "$loadStatus" |grep -q 'connect\|abort\|host' && \
		! ( echo "$loadStatus" | grep -q 'File not found' ) ; then
		Echo "Download failed: $loadStatus"
		#problem with server, try service partition fallback
		if [ -f "/srv/SLEPOS/KIWI/config.$DHCPCHADDR" ]; then
			SRV_CONFIG="/srv/SLEPOS/KIWI/config.$DHCPCHADDR"
		elif [ -f "/srv/SLEPOS/KIWI/config.default" ]; then
			SRV_CONFIG="/srv/SLEPOS/KIWI/config.default"
		fi
	
		if [ -n "$SRV_CONFIG" ]; then
			Echo "Using local config '$SRV_CONFIG'"
			unset root
			cp -f "$SRV_CONFIG" "$CONFIG"
			SERVER=/srv/SLEPOS/
			SERVERTYPE=local
			unset loadStatus
		fi
	fi

	# NLPOS9 Branch Server has config files in tftpboot/CR directory 
	# instead of tftpboot/KIWI (bnc#552302) 
	if [ ! -s $CONFIG ];then
		fetchFile CR/config.$DHCPCHADDR $CONFIG
	fi

	#======================================
	# Check alternative config names
	#--------------------------------------
	if [ ! -s $CONFIG ] ; then
		searchGroupConfig
	fi
	#======================================
	# Check alternative config names
	#--------------------------------------
	if [ ! -s $CONFIG ];then
		searchAlternativeConfig
	fi

	# NLPOS9 Branch Server has config files in tftpboot/CR directory 
	# instead of tftpboot/KIWI (bnc#552302) 
	if [ ! -s $CONFIG ];then
		searchNlposAlternativeConfig
	fi

	#======================================
	# try to read role configuration
	#--------------------------------------
	posGetHwtype
	posFetchRoles
	posFetchRollback
	#======================================
	# Check and import Hardware Maps if set
	#--------------------------------------
	searchHardwareMapConfig

	runHook roles
	#======================================
	# try to import configuration
	#--------------------------------------
	IMPORTED=0
	if [ -s $CONFIG ] ;then
		importConfigFile
	fi
	[ -n "$POS_ID" ] && Echo "Configured ID:   $POS_ID"
	[ -n "$POS_ROLE" ] && Echo "Configured Role: $POS_ROLE"
	

	# no config means that there is nothing to change
	if [ -z "$POS_DISABLE_BOOT_HOTKEY" ] && \
	   [ -s $CONFIG ] && \
	   [ -n "$POS_ROLE_BASED" -o -n "$POS_ROLLBACK" ] && \
	   bootChangeHotkey ; then
		posBootChangeMenu
		case $POS_BOOT_MODE in
			I) POS_FORCE_ROLE_SELECTION=1 ;;
			R) POS_FORCE_ROLLBACK=1 ;;
		esac
	fi

	if [ -n "$POS_FORCE_ROLLBACK" ]; then
		posSelectRollbackConfig
		importConfigFile
		posRemapAssocConfigs
		posAppendPxeParams
	fi

	#======================================
	# handle role-related errors 
	#--------------------------------------
	if [ -n "$POS_ROLE_BASED" ]; then
		if [ -z "$IMAGE" -o ! -s $CONFIG ] ; then
			POS_FORCE_ROLE_SELECTION=1
			rm $CONFIG
		fi
	fi

	if [ -z "$IMAGE" -o ! -s $CONFIG -o -n "$POS_FORCE_ROLE_SELECTION" ];then

		#======================================
		# Register new network client
		#--------------------------------------
		Echo "Registering new network client..."
		pxeSetupSystemAliasName
		#send hwinfo only on the first boot when we have no config at all
		[ ! -s $CONFIG ] && pxeSetupSystemHWInfoFile
		STEP=10
		while true ; do
			posSelectRole
			[ -s $CONFIG ] && posCmpSelectedRole && break #selected role is already configured
			
			setupSystemHWTypeFile
			#======================================
			# Put files on the boot server
			#--------------------------------------
			putFile hwinfo.$DHCPCHADDR upload/hwinfo.$DHCPCHADDR
			POS_HWTYPE_DOT_HASH=
			if [ -n "$POS_ROLE_BASED" ]; then
				POS_HWTYPE_DOT_HASH=".`md5sum hwtype.$DHCPCHADDR|cut -d ' ' -f 1`"
			fi
			putFile hwtype.$DHCPCHADDR upload/hwtype.$DHCPCHADDR$POS_HWTYPE_DOT_HASH
			echo
			Echo "Registered as: $DHCPCHADDR$POS_HWTYPE_DOT_HASH"
			Echo "Waiting for configuration..."
			if [ -n "$POS_ROLE_BASED" ]; then
				waitWhileExists upload/hwtype.$DHCPCHADDR$POS_HWTYPE_DOT_HASH
				Echo "upload/hwtype.$DHCPCHADDR$POS_HWTYPE_DOT_HASH was processed by server"
			else
				sleep 2
			fi
			#======================================
			# Wait for configuration (reload)
			#--------------------------------------
			rm -f $CONFIG
			while test ! -s $CONFIG;do
				Echo "Lookup network client config file again..."
				Echo "Checking for config file: config.$DHCPCHADDR"
				dhcpcd -n $PXE_IFACE
				fetchFile KIWI/config.$DHCPCHADDR $CONFIG

				if [ ! -s $CONFIG ] ; then
					searchGroupConfig
				fi
				if [ ! -s $CONFIG ] ; then
					searchAlternativeConfig
				fi
				test -s $CONFIG || {
					Echo "Couldn't get image configuration"
					Echo "sleeping [60 sec]..."
					sleep 60
				}
			done
			importConfigFile
			NEWIP=0
			posCmpSelectedRole && break
			posConfirmRole && break
			let STEP=STEP-1
			[ "$STEP" -eq 0 ] && systemException "Can't register ID / Role" "reboot"
			
			# get up-to-date role and id list
			posFetchRoles 
		done
	fi

