#======================================
# setupSystemHWInfoFile
#--------------------------------------
function setupSystemHWInfoFile {
	# /.../
	# calls hwinfo and stores the information into a file
	# suffixed by the hardware address of the network card
	# ----
	hwinfo --all --log=hwinfo.$DHCPCHADDR >/dev/null
}

function posGetHwtype {
	if [ -f /sbin/posbios ];then
		HWBIOS=`/sbin/posbios -b`
		HWTYPE=`/sbin/posbios -ms`
	fi
}

#======================================
# setupSystemHWTypeFile
#--------------------------------------
function setupSystemHWTypeFile {
	# /.../
	# collects information about the alias name the
	# architecture the BIOS version and more and stores
	# that into a file suffixed by the hardware address of the
	# network card. The information is uploaded to the pxe
	# boot server and used to create a machine config.<MAC> 
	# from the ldap directory
	# ----
	echo "NCNAME=$SYSALIAS"   >  hwtype.$DHCPCHADDR
	echo "CRNAME=$SYSALIAS"   >> hwtype.$DHCPCHADDR
	echo "IPADDR=$IPADDR"     >> hwtype.$DHCPCHADDR
	echo "ARCHITECTURE=$ARCH" >> hwtype.$DHCPCHADDR
	if [ -n "$POS_ROLE_BASED" ]; then
		# missing POS_ID no change
		# POS_ID=(empty) delete id
		[ -z "$POS_SELECTED_ID_TIMEOUT" -o -n "$POS_SELECTED_ID" ] && echo "POS_ID=$POS_SELECTED_ID" >> hwtype.$DHCPCHADDR
		[ -n "$POS_SELECTED_ROLE" ] && echo "POS_ROLE=$POS_SELECTED_ROLE" >> hwtype.$DHCPCHADDR
	fi
	#========================================
	# Try to get BIOS data if tools are there
	#----------------------------------------
	test -c /dev/mem      || mknod -m 0600 /dev/mem      c 1 1
	if [ -f /sbin/posbios ];then
		echo "HWBIOS=$HWBIOS" >> hwtype.$DHCPCHADDR
		echo "HWTYPE=$HWTYPE" >> hwtype.$DHCPCHADDR
	fi
	echo "POS_MAC=$(echo $(hwinfo --netcard |grep "HW Address:" |cut -d : -f 2- ) )" |sed -e "s| |,|g" >>hwtype.$DHCPCHADDR
}


function encodeHwtype { 
	local STR
	local CH
	local STR="$@"
	local IFS=''
	echo -n "$STR" | while read -n1 CH; do 
		[[ $CH =~ [-_A-Za-z0-9] ]] && printf "$CH" || printf "%%%x" \'"$CH"
	done
}

function posFetchRoles {
	Echo "Checking Role-based configuration"
	IDLIST=/etc/idlist
	ROLELIST=/etc/rolelist
	Echo "Checking for idlist file"
	# zero length idlist is valid
	fetchFile KIWI/idlist $IDLIST || rm -f $IDLIST
	Echo "Checking for rolelist.$DHCPCHADDR file"
	fetchFile KIWI/rolelist.$DHCPCHADDR $ROLELIST
	if [ ! -s $ROLELIST -a -n "$HWTYPE" ]; then
		ENC_HWTYPE=`encodeHwtype "$HWTYPE"`
		Echo "Checking for rolelist.$ENC_HWTYPE file"
		fetchFile KIWI/rolelist.$ENC_HWTYPE $ROLELIST
	fi
	if [ ! -s $ROLELIST ]; then
		Echo "Checking for rolelist.default file"
		fetchFile KIWI/rolelist.default $ROLELIST
	fi
	if [ ! -s $ROLELIST ]; then
		Echo "Checking for rolelist file"
		fetchFile KIWI/rolelist $ROLELIST
	fi
	# zero length idlist is valid
	if [ -s $ROLELIST -o -f $IDLIST ]; then
		POS_ROLE_BASED=1
	fi
}

function posFetchRollback {
	POS_ROLLBACK=rollback.$DHCPCHADDR 
	Echo "Checking for rollback.$DHCPCHADDR file"
	fetchFile KIWI/rollback.$DHCPCHADDR $POS_ROLLBACK || POS_ROLLBACK=
	[ -n "$POS_ROLLBACK" ]
}

function posSelectRollbackConfig {
	local ARGS
	ROLLBACK_CONFIG=
	if [ -n "$POS_ROLLBACK" ]; then
		test -e /proc/splash && echo verbose > /proc/splash
		local CFG
		local TIMESTAMP
		local NAME
		local DESC
		while true; do
			ROLLBACK_CONFIG=
			IFS="|"
			ARGS=`N=1; cat $POS_ROLLBACK | while read -r CFG TIMESTAMP NAME DESC; do echo -n "$N|$DESC|" ; let N=N+1 ; done`
			dialog --timeout 60 --no-cancel --menu "Restore previous configuration" 20 75 20 $ARGS 2>sel_rollback
			grep '^timeout$' sel_rollback && dialog --infobox "Rollback timeout..." 3 70 && break
			ROLLBACK_CONFIG=`cat sel_rollback`
			ROLLBACK_CONFIG=`N=1; cat $POS_ROLLBACK | while read -r CFG TIMESTAMP NAME DESC; do [ "$N" -eq "$ROLLBACK_CONFIG" ] && echo -n "$CFG" && break; let N=N+1 ; done`
			[ -z "$ROLLBACK_CONFIG" ] && continue
			Echo "Checking for '$ROLLBACK_CONFIG' file"
			IFS=$IFS_ORIG  #fetchfile needs original IFS to support 'curl ftp... | dd ...' 
			fetchFile "$ROLLBACK_CONFIG" $CONFIG.rollback && [ -s $CONFIG.rollback ] && mv -f $CONFIG.rollback $CONFIG && \
			          dialog --infobox "Using restored configuration..." 3 70 && break
			posFetchRollback || break #rollback list might be changed, update
		done
	fi
}

function posSelectRole {
	local ARGS
	if [ -n "$POS_ROLE_BASED" ]; then
		test -e /proc/splash && echo verbose > /proc/splash
		runHook selectRole
		
		[ -n "$POS_DISABLE_ROLE_DIALOG" ] && return
		
		IFS="|"
		if [ -f $IDLIST ]; then
#			while [ -z "$POS_SELECTED_ID" ]; do
				local DEFAULT=
				local ID
				ARGS=`cat $IDLIST | while read -r ID ; do echo -n "$ID| |" ; done`
				
				# No ID
				ARGS="|No ID|$ARGS"

				#current ID if we have one
				if [ -n "$POS_ID" ]; then
					ARGS="$POS_ID|Keep current ID|$ARGS"
					DEFAULT="$POS_ID"
				fi
				dialog --timeout 60 --no-cancel --default-item "$DEFAULT" --menu "Select id" 20 75 20 $ARGS 2>sel_id
				if grep -q '^timeout$' sel_id ; then
					POS_SELECTED_ID="$POS_ID"
					POS_SELECTED_ID_TIMEOUT=1
					dialog --infobox "ID selection timeout..." 3 70
				else
					POS_SELECTED_ID_TIMEOUT=
				        POS_SELECTED_ID=`cat sel_id`
					POS_SELECTED_ID=`(echo "$POS_ID"; cat $IDLIST )| while read -r ID ; do [ "$ID" = "$POS_SELECTED_ID" ] && echo -n "$ID" && break ; done`
					dialog --infobox "Selected ID: '$POS_SELECTED_ID'" 3 70
				fi
#			done
		fi
		
		if [ -s $ROLELIST ]; then
#			while [ -z "$POS_SELECTED_ROLE" ]; do
				local DEFAULT=
				local DN
				local NAME
				local DESC
				if [ -n "$POS_ROLE" ]; then
					DEFAULT=`grep "^$POS_ROLE|" $ROLELIST |cut -f 2 -d '|'`
				fi
				ARGS=`cat $ROLELIST | while read -r DN NAME DESC ; do echo -n "$NAME|$DESC|" ; done`
				dialog --timeout 60 --no-cancel --default-item "$DEFAULT" --menu "Select role" 20 75 20 $ARGS 2>sel_role
				if grep -q '^timeout$' sel_role ; then
					POS_SELECTED_ROLE="$POS_ROLE"
					POS_SELECTED_ROLE_TIMEOUT=1
					dialog --infobox "Role selection timeout..." 3 70

				else
					POS_SELECTED_ROLE_TIMEOUT=
					POS_SELECTED_ROLE=`cat sel_role`
					dialog --infobox "Selected role: '$POS_SELECTED_ROLE'" 3 70
					POS_SELECTED_ROLE=`cat $ROLELIST | while read -r DN NAME DESC ; do [ "$NAME" = "$POS_SELECTED_ROLE" ] && echo -n "$DN" && break ; done`
				fi
#			done
		fi
		IFS=$IFS_ORIG

	fi
}

function bootChangeHotkey {
	test -e /proc/splash && echo verbose > /proc/splash
	Echo -n "Press C to change terminal configuration..."
	local KEY
	read -t 5 -n 1 KEY
	while [ -n "$KEY" -a "$KEY" != 'C' -a "$KEY" != 'c' ]; do
		KEY=
		read -t 1 -n 1 KEY
	done
	
	[ "$KEY" = 'C' -o "$KEY" = 'c' ] && echo " pressed." || echo " timeout."
	[ "$KEY" = 'C' -o "$KEY" = 'c' ]
}

function posBootChangeMenu {
	IFS="|"
	local ARGS
	local N=2
	
	ARGS="N|Normal boot"

	if [ -n "$POS_ROLE_BASED" ]; then
		ARGS="$ARGS|I|Change ID/Role"
	fi
	
	if [ -n "$POS_ROLLBACK" ]; then
		ARGS="$ARGS|R|Rollback"
	fi

	dialog --timeout 60 --no-cancel --menu "Change configuration" 20 75 20 $ARGS 2>boot_mode
	POS_BOOT_MODE=`cat boot_mode`
	
	IFS=$IFS_ORIG
}

function waitWhileExists {
	TMP_FILE=tmp_file
	while fetchFile "$1" $TMP_FILE && test -s $TMP_FILE ; do
		sleep 2
		rm tmp_file
	done
}

function posCmpSelectedRole {
	if [ -n "$POS_SELECTED_ROLE_TIMEOUT" ]; then
		POS_SELECTED_ROLE="$POS_ROLE" #use anything sent by the server
	fi

	if [ -n "$POS_SELECTED_ID_TIMEOUT" ]; then
		POS_SELECTED_ID="$POS_ID" #use anything sent by the server
	fi

        [ -z "$IMAGE" ] && return 1 #no chance to boot without an image
	[ -z "$POS_ROLE_BASED" ] && return 0
	
	[ "$POS_SELECTED_ID"   = "$POS_ID" -a \
	  "$POS_SELECTED_ROLE" = "$POS_ROLE" ]
}

function posConfirmRole {
	test -e /proc/splash && echo verbose > /proc/splash
	if [ ".$POS_HWTYPE_ERR_HASH" = "$POS_HWTYPE_DOT_HASH" ]; then
		[ -n "$POS_ERR" ] && dialog --timeout 60 --msgbox "$POS_ERR" 10 60
		return 1
	fi
	
	[ -z "$IMAGE" ] && return 1 #no chance to boot without an image
	
	if [ -n "$POS_ID" -o -n "$POS_ROLE" ]; then
		dialog  --timeout 60 --yesno "The configured ID/role does not match the selected one. Use ID '$POS_ID' and role '$POS_ROLE' ?" 10 60
		return $?
	fi
	return 1
}

function importConfigFile {
	unset IMAGE
	unset PART
	unset DISK
	unset POS_ID
	unset POS_ROLE
	unset POS_HWTYPE_HASH
	unset POS_ERR
	unset POS_HWTYPE_ERR_HASH
	importFile <$CONFIG
	IMPORTED=1
	[ -n "$POS_HWTYPE_ERR_HASH" ] && Echo "Got POS_HWTYPE_ERR_HASH $POS_HWTYPE_ERR_HASH"
}

#======================================
# searchNlposAlternativeConfig
# - NLPOS9 Branch Server has config files in tftpboot/CR directory 
#   instead of tftpboot/KIWI (bnc#552302)
#--------------------------------------
function searchNlposAlternativeConfig {
	# Check config.IP in Hex (pxelinux style)
	localip=$IPADDR
	hexip1=`echo $localip | cut -f1 -d'.'`
	hexip2=`echo $localip | cut -f2 -d'.'`
	hexip3=`echo $localip | cut -f3 -d'.'`
	hexip4=`echo $localip | cut -f4 -d'.'`
	hexip=`printf "%02X" $hexip1 $hexip2 $hexip3 $hexip4`
	STEP=8
	while [ $STEP -gt 0 ]; do
		hexippart=`echo $hexip | cut -b -$STEP`
		Echo "Checking for config file: config.$hexippart"
		fetchFile CR/config.$hexippart $CONFIG
		if test -s $CONFIG;then
			break
		fi
		let STEP=STEP-1
	done
	# Check config.default if no hex config was found
	if test ! -s $CONFIG;then
		Echo "Checking for config file: config.default"
		fetchFile CR/config.default $CONFIG
	fi
}

function posGetHwtype {
	if [ -f /sbin/posbios ];then
		HWBIOS=`/sbin/posbios -b`
		HWTYPE=`/sbin/posbios -ms`
	fi
}




function posRemapAssocConfigs
{
	local CONFMOD=''
	local CSEP=''
	local RPTH='/KIWI/rollback/configs/'
	IFS=','
	for cfg in $CONF;do  #change conf path and add hash to its name
		CONFMOD=$CONFMOD$CSEP`echo $cfg | sed -r -e "s<^([^;]*)/([^;]*);(.*);(.*)$<$RPTH\2.\4;\3;\4<"`
		CSEP=$IFS
	done
	CONF=$CONFMOD
	IFS=$IFS_ORIG
}


function posAppendPxeParams
{
	#TODO: reboot cleanly (kexec?), allow rollback of initrd and kernel
	#append pxe parameter, only applies them from init stage 7 (pxeSetupDownloadServer) on (no reboot)
	local PXEPATH='/etc/pxe.rollback'
	local RPXEPATH='/KIWI/rollback/boot/pxe.'$POS_KERNEL_PARAMS_HASH_VERIFY
	if  ! fetchFile $RPXEPATH $PXEPATH ;then 
		Echo "rollback pxe file $RPXEPATH not found, ignoring..."
		return
	fi
	Echo "fetched specific pxe $RPXEPATH, updating parameters"
	eval `cat $PXEPATH | grep append | sed -e 's/^\s*append\s*//'`
	pxeSetupDownloadServer
}

function checkDataPartFilesystemExt3
{
	local diskPartition=$1
	e2fsck -p $diskPartition 1>&2
	local res=$?
	#        The exit code returned by e2fsck is the sum of the following conditions:
	#            0    - No errors
	#            1    - File system errors corrected
	#            2    - File system errors corrected, system should
	#                   be rebooted
	#            4    - File system errors left uncorrected
	#            8    - Operational error
	#            16   - Usage or syntax error
	#            32   - E2fsck canceled by user request
	#            128  - Shared library error
	if [ "$res" -ge 4 ] ; then
		Echo "Partition $diskPartition is not valid, formating..."
		createFilesystem $diskPartition
	else
		Echo "Partition $diskPartition is valid, leave it untouched"
		Echo "Formatting of $diskPartition can be forced by POS_FORMAT_DATA_PART=force"
		# allow growing of the partition - fate#313337
		if ! resize2fs $diskPartition 1>&2 ; then
			# resize failed, try again check and resize with force
			e2fsck -p -f $diskPartition 1>&2 
			if [ "$res" -ge 4 ] ; then
				Echo "Partition $diskPartition can't be resized, formating..."
				createFilesystem $diskPartition
			else
				resize2fs -f $diskPartition 1>&2 
			fi
		fi
	fi
}

function setupDataPartFilesystem 
{
	local field=0
	local count=0
	local IFS=","
	local imageDevice=$(echo "$IMAGE" | cut -d ";" -f 1 )
	local fs
	local pwlist=$PART_PASSWORDS
	local luks_pass
	for i in $PART;do
		luks_pass=${pwlist%%,*}
		pwlist=${pwlist#*,}
		field=0
		count=$((count + 1))
		IFS=";" ; for n in $i;do
			case $field in
				0) partSize=$n   ; field=1 ;;
				1) partID=$n     ; field=2 ;;
				2) partMount=$n;
			esac
		done
		device=$(ddn $imageDiskDevice $count)
		if [ ! -z "$RAID" ];then
			device=/dev/md$((count - 1))
		else
			device=$(ddn $imageDiskDevice $count)
		fi

		if [ "$device" != "$imageDevice" -a "$partMount" != "/" ]; then
			if ! waitForStorageDevice $device ; then
				Echo $device did not appear
				continue
			fi

			probeFileSystem $device
			if [ "$FSTYPE" = "unknown"  -a $partID = "83" ]; then
				Echo "Partition $device is not valid, formating..."
				if [ -n "$luks_pass" ]; then
					echo "$luks_pass" | cryptsetup luksFormat $device
					luksOpen $device
					device=$luksDeviceOpened
				fi
				createFilesystem $device
			elif [ "$FSTYPE" != "luks" -a -n "$luks_pass" -a $partID = "83" ]; then
				Echo "Partition $device may contain unencrypted filesystem, encryption is requested by PART_PASSWORDS"
				if [ -n "$POS_FORMAT_DATA_PART" ] ; then
					Echo "Formatting with luks has been forced by POS_FORMAT_DATA_PART=$POS_FORMAT_DATA_PART"
					echo "$luks_pass" | cryptsetup luksFormat $device
					luksOpen $device
					device=$luksDeviceOpened
					createFilesystem $device
				else
					Echo "Formatting of $device can be forced by POS_FORMAT_DATA_PART=yes"
					systemException "NOT formatting $device to preserve user data" "reboot"
				fi
			elif [ "$FSTYPE" == "luks" -a -z "$luks_pass" -a $partID = "83" ]; then
				Echo "Partition $device is encrypted, password was not given in PART_PASSWORDS"
				if [ -n "$POS_FORMAT_DATA_PART" ] ; then
					Echo "Formatting of $device has been forced by POS_FORMAT_DATA_PART=$POS_FORMAT_DATA_PART"
					createFilesystem $device
				else
					Echo "Formatting of $device can be forced by POS_FORMAT_DATA_PART=yes"
					systemException "NOT formatting $device to preserve user data" "reboot"
				fi
			elif [ "$FSTYPE" = "ext3" -a $partID != "82" ]; then
				if [ "x$POS_FORMAT_DATA_PART" = "xforce" ] ; then
					echo "Formatting of $device has been forced by POS_FORMAT_DATA_PART=force"
					createFilesystem $device
				else
					checkDataPartFilesystemExt3 $device
				fi
				#check of encrypted devices is called later in openLUKSDevices
			fi
		fi
	done
}

function getLuksPass
{
	local count
	local pass
	local pwlist=$PART_PASSWORDS
	local check_device=$1
	
	local count=0
	for i in $PART;do
		pass=${pwlist%%,*}
		pwlist=${pwlist#*,}
		count=$((count + 1))

		if [ ! -z "$RAID" ];then
			device=/dev/md$((count - 1))
		else
			device=$(ddn $DISK $count)
		fi

		if [ "$check_device" = "$device" ]; then
			echo "$pass"
			return 0
		fi
	done
	return 1
}


function setImageLuksPass
{
	local field
	local count
	local imageDevice
	local imageName
	local imageVersion
	local pass
	local pwlist=$PART_PASSWORDS
	local IFS
	
	[ -n "$luks_pass" ] && return 2 #pw already set
	[ -z "$DISK" ] && return 1
	
	local IMAGE_FIRST=$(echo "$IMAGE" | cut -f1 -d,)
	for i in $IMAGE_FIRST;do
		field=0
		IFS=";" ; for n in $i;do
			case $field in
				0) imageDevice=$n ; field=1 ;;
				1) imageName=$n   ; field=2 ;;
				2) imageVersion=$n; field=3
			esac
		done

		pass=$(getLuksPass "$imageDevice")

		if [ -n "$pass" ]; then
			luks_pass=$pass
			return 0
		fi
	done
	return 1
}

function createEncryptedSwapDevice
{
	local swapDevice=$1
	
	local pass=$(getLuksPass "$swapDevice")
	local luks_pass
	local luks_open_can_fail=yes
	
	if [ -n "$pass" ]; then
		if [ "x$pass" = "x*" ]; then
			pass=$(head -c 15 /dev/random |md5sum |cut -d ' ' -f 1)
		fi
		luks_pass=$pass
		luksOpen $swapDevice
		if [ -z "$luksDeviceOpened" -o "$luksDeviceOpened" = "$swapDevice" ]; then
			luks_pass=pass
			echo "$luks_pass" | cryptsetup luksFormat $swapDevice
			luksOpen $swapDevice
		fi
		#set the new swap device 
		imageSwapDevice=$luksDeviceOpened
	fi
}

function openLUKSDevices 
{
	local field=0
	local count=0
	local device
	local imageDevice=$(echo "$IMAGE" | cut -d ";" -f 1 )
	local pwlist=$PART_PASSWORDS
	local luks_pass
	local luks_open_can_fail=yes
	local IFS=","
	for i in $PART;do
		luks_pass=${pwlist%%,*}
		pwlist=${pwlist#*,}
		field=0
		count=$((count + 1))
		IFS=";" ; for n in $i;do
		case $field in
			0) partSize=$n   ; field=1 ;;
			1) partID=$n     ; field=2 ;;
			2) partMount=$n;
		esac
		done
		if [ -n "$luks_pass" ]; then
			if [ ! -z "$RAID" ];then
				device=/dev/md$((count - 1))
			else
				device=$(ddn $imageDiskDevice $count)
			fi
			if ! waitForStorageDevice $device ; then
				Echo $device did not appear - repartitioning required
				continue
			fi
			if [ "x$luks_pass" = "x*" -o $partID = "82" -o $partID = "S" ]; then
				#reformat swap with a random pass
				createEncryptedSwapDevice $device
				if [ ! -z "$imageSwapDevice"  -a "`blkid $imageSwapDevice -s TYPE -o value`" != "swap" ];then
					if ! mkswap $imageSwapDevice 1>&2;then
						systemException "Failed to create swap signature" "reboot"
					fi
				fi
			else
				luksOpen $device
				if [ -n "$luksDeviceOpened" -a "$luksDeviceOpened" != "$device" -a "$device" != "$imageDevice" -a "$partMount" != "/" ]; then
					probeFileSystem $luksDeviceOpened
					if [ "$FSTYPE" = "ext3" -o "$FSTYPE" = "unknown" ]; then
						checkDataPartFilesystemExt3 $luksDeviceOpened
					else
						if [ "x$POS_FORMAT_DATA_PART" = "xforce" ] ; then
							echo "Formatting of $device has been forced by POS_FORMAT_DATA_PART=force"
							createFilesystem $luksDeviceOpened
						fi
					fi
				elif [ "$device" != "$imageDevice" -a "$partMount" != "/" ]; then
					# luksOpen failed
					if [ "x$POS_FORMAT_DATA_PART" = "xforce" ] ; then
						Echo "Formatting of $device has been forced by POS_FORMAT_DATA_PART=$POS_FORMAT_DATA_PART"
						echo "$luks_pass" | cryptsetup luksFormat $device
						luksOpen $device
						createFilesystem $luksDeviceOpened
					else
						Echo "Can't open encrypted $device. Formatting can be forced by POS_FORMAT_DATA_PART=force"
						systemException "NOT formatting $device to preserve user data" "reboot"
					fi
				fi
			fi
		fi
	done
}


function updateLUKSDeviceFstab 
{
	# /.../
	# check the contents of the $PART variable and
	# add one line to the fstab file for each partition
	# which has a mount point defined.
	# ----
	local prefix=$1
	local nfstab=$prefix/etc/fstab
	local index=0
	local field=0
	local count=0
	local device
	local pwlist=$PART_PASSWORDS
	local luks_pass
	local luks_open_can_fail=yes
	local IFS=","
	for i in $PART;do
		luks_pass=${pwlist%%,*}
		pwlist=${pwlist#*,}
		field=0
		count=$((count + 1))
		IFS=";" ; for n in $i;do
		case $field in
			0) partSize=$n   ; field=1 ;;
			1) partID=$n     ; field=2 ;;
			2) partMount=$n;
		esac
		done
		if  [ ! -z "$partMount" ]    && \
			[ ! "$partMount" = "x" ] && \
			[ ! "$partMount" = "/" ] && \
			[ ! "$partMount" = "swap" ]
		then
			if [ -n "$luks_pass" ]; then
				if [ ! -z "$RAID" ];then
					device=/dev/md$((count - 1))
				else
					device=$(ddn $imageDiskDevice $count)
				fi
				luksOpen $device
				if [ -n "$luksDeviceOpened" -a "$luksDeviceOpened" != "$device" ]; then
					probeFileSystem $luksDeviceOpened
					if [ ! -d /mnt/$partMount ];then
						mkdir -p /mnt/$partMount
					fi
					echo "$luksDeviceOpened $partMount $FSTYPE defaults 0 0" >> $nfstab
				fi
			fi
		fi
	done
}

function putFileNoFail {
	# /.../
	# the generic putFile function is used to upload boot data on
	# a server. Supported protocols are tftp, ftp, http, https
	# ----
	local path=$1
	local dest=$2
	local host=$3
	local type=$4
	if test -z "$path"; then
		return 1
	fi
	if test -z "$host"; then
		if test -z "$SERVER"; then
			return 1
		fi
		host=$SERVER
	fi
	if test -z "$type"; then
		if test -z "$SERVERTYPE"; then
			type="tftp"
		else
			type="$SERVERTYPE"
		fi
	fi
	case "$type" in
		"http")
			curl -f -T $path http://$host/$dest > $TRANSFER_ERRORS_FILE 2>&1
			return $?
			;;
		"https")
			curl -f -T $path https://$host/$dest > $TRANSFER_ERRORS_FILE 2>&1
			return $?
			;;
		"ftp")
			curl -T $path ftp://$host/$dest  > $TRANSFER_ERRORS_FILE 2>&1
			return $?
			;;
		"tftp")
			atftp -p -l $path -r $dest $host >/dev/null 2>&1
			return $?
			;;
		*)
			return 1
			;;
	esac
}

function uploadLog
{
	if [ -n "$DHCPCHADDR" ]; then
		putFileNoFail /var/log/boot.kiwi upload/boot.kiwi.$DHCPCHADDR
	fi
}

function censorLog
{
	local IFS=","
	local pw
	local pw_esc
	
	errorLogStop

	local pwlist="$luks_pass,$PART_PASSWORDS,"

	while [ -n "$pwlist" ]; do
		pw=${pwlist%%,*}
		pwlist=${pwlist#*,}

		if [ -n "$pw" -a "x$pw" != "x*" ]; then
			pw_esc=`echo "$pw"|sed -e 's/\(\.\|\/\|\*\|\[\|\]\|\\\\\)/\\&/g'`
			sed -i -e "s/$pw_esc/********/g" $ELOG_FILE
		fi
	done

	unset luks_pass
	unset PART_PASSWORDS
	
	errorLogContinue
}

function startHaveged
{
	# if we are using encryption, start haveged daemon to se tup a good entropy source
	if [ -n "$PART_PASSWORDS" ]; then
		haveged -w 1024 -v 1
	fi
}

function stopHaveged
{
	if [ -f /var/run/haveged.pid ]; then
		kill `cat /var/run/haveged.pid`
	fi
}

function applyHWTypeConfig
{
	if [ $LOCAL_BOOT = "no" ] && [ $systemIntegrity = "clean" ];then
		if [ -f "/mnt/lib/kiwi/HWTYPE/$HWTYPE.tar.gz" ]; then 
			tar xzf "/mnt/lib/kiwi/HWTYPE/$HWTYPE.tar.gz" -C /mnt
		fi
	fi
}

function mountServicePartition
{
	local field=0
	local count=0
	local IFS=","
	local pwlist=$PART_PASSWORDS
	local luks_pass
	for i in $PART;do
		luks_pass=${pwlist%%,*}
		pwlist=${pwlist#*,}
		field=0
		count=$((count + 1))
		IFS=";" ; for n in $i;do
			case $field in
				0) partSize=$n   ; field=1 ;;
				1) partID=$n     ; field=2 ;;
				2) partMount=$n;
			esac
		done
		
		[ "$partMount" = "/srv/SLEPOS" ] || continue
		
		if [ ! -z "$RAID" ];then
			device=/dev/md$((count - 1))
		else
			device=$(ddn $imageDiskDevice $count)
		fi
		

		if ! waitForStorageDevice $device ; then
			Echo $device did not appear
			continue
		fi
		
		SERVICE_PARTITION_DEVICE=$device
		SERVICE_PARTITION_IDX=$((count - 1))
		
		#set service part label
		tune2fs -L SRV_SLEPOS_PART $device
		
		mkdir -p /srv/SLEPOS
		mount $device /srv/SLEPOS
		return # exit status from mount
	done
	return 1 # failed
}

function mountServicePartitionByLabel
{
	#this is used for fetching config at the very beginning
	#no partition is known yet
	#prefer template over the regular part because it may contain updates
	mkdir -p /srv/SLEPOS
	waitForStorageDevice /dev/disk/by-label/SRV_SLEPOS_TMPL
	mount -L SRV_SLEPOS_TMPL /srv/SLEPOS || mount -L SRV_SLEPOS_PART /srv/SLEPOS
}


function umountServicePartition
{
	umount /srv/SLEPOS
}

function syncServicePartition
{
	mkdir -p /srv/SLEPOS_template
	# regular service partition has label SRV_SLEPOS_PART set during mount
	# SRV_SLEPOS_TMPL can be only on usb
	if [ -n "$SERVICE_PARTITION_DEVICE" ] && mount -L SRV_SLEPOS_TMPL /srv/SLEPOS_template ; then
		Echo "Updating service partition from template"
		cp -pr /srv/SLEPOS_template/* /srv/SLEPOS
		umount /srv/SLEPOS_template
	fi
}

function installServiceKernel 
{
	local SERVICE=$1
	POS_KERNEL_MD5="$POS_KERNEL.md5"
	POS_INITRD_MD5="${POS_INITRD%.gz}.md5"

	mkdir -p $SERVICE/boot
	Echo "Fetching kernel and initrd for local boot"
	fetchFile "boot/$POS_KERNEL_MD5" "$SERVICE/boot/$POS_KERNEL_MD5.tmp"
	fetchFile "boot/$POS_INITRD_MD5" "$SERVICE/boot/$POS_INITRD_MD5.tmp"

	POS_KERNEL_MD5_SUM=`cut -f 1 -d ' ' "$SERVICE/boot/$POS_KERNEL_MD5.tmp"`
	POS_INITRD_MD5_SUM=`cut -f 1 -d ' ' "$SERVICE/boot/$POS_INITRD_MD5.tmp"`

	if [ ! -f "$SERVICE/boot/$POS_KERNEL" ] || \
	   [ "$POS_KERNEL_MD5_SUM" != `md5sum "$SERVICE/boot/$POS_KERNEL" |cut -f 1 -d ' '` ]; then
		fetchFile "boot/$POS_KERNEL" "$SERVICE/boot/$POS_KERNEL.tmp"
		if [ -n "$POS_KERNEL_MD5_SUM" -a "$POS_KERNEL_MD5_SUM" != `md5sum "$SERVICE/boot/$POS_KERNEL.tmp" |cut -f 1 -d ' '` ]; then
			Echo "Checksum of downloaded kernel does not match"
			Echo "Local boot configuration left unchanged"
			return 1
		fi
	fi
	if [ ! -f "$SERVICE/boot/$POS_INITRD" ] || \
	   [ "$POS_INITRD_MD5_SUM" != `md5sum "$SERVICE/boot/$POS_INITRD" |cut -f 1 -d ' '` ]; then
		fetchFile "boot/$POS_INITRD" "$SERVICE/boot/$POS_INITRD.tmp"
		if [ -n "$POS_INITRD_MD5_SUM" -a "$POS_INITRD_MD5_SUM" != `md5sum "$SERVICE/boot/$POS_INITRD.tmp" |cut -f 1 -d ' '` ]; then
			Echo "Checksum of downloaded initrd does not match"
			Echo "Local boot configuration left unchanged"
			return 1
		fi
	fi
	
	[ -f "$SERVICE/boot/$POS_KERNEL.tmp" ] && mv -f "$SERVICE/boot/$POS_KERNEL.tmp" "$SERVICE/boot/$POS_KERNEL"
	[ -f "$SERVICE/boot/$POS_INITRD.tmp" ] && mv -f "$SERVICE/boot/$POS_INITRD.tmp" "$SERVICE/boot/$POS_INITRD"
	[ -f "$SERVICE/boot/$POS_KERNEL_MD5.tmp" ] && mv -f "$SERVICE/boot/$POS_KERNEL_MD5.tmp" "$SERVICE/boot/$POS_KERNEL_MD5"
	[ -f "$SERVICE/boot/$POS_INITRD_MD5.tmp" ] && mv -f "$SERVICE/boot/$POS_INITRD_MD5.tmp" "$SERVICE/boot/$POS_INITRD_MD5"
}


function installServiceGrub
{
	if [ -z "$POS_KERNEL" -o -z "$POS_INITRD" ]; then
		Echo "Local boot options are not set in config.MAC"
		return 1
	fi

	installServiceKernel /srv/SLEPOS

	# test grub here, after kernel and initrd
	# local kernel and initrd are usable also for kexec
	if [ ! -f /usr/sbin/grub ]; then
		Echo "Can't find grub executable. Local boot is not possible."
		return 1
	fi

        echo "setup --stage2=/boot/grub/stage2 (hd0) (hd0,$SERVICE_PARTITION_IDX)" >/etc/grub.conf
	if [ ! -z "$RAID" ];then
	        echo "setup --stage2=/boot/grub/stage2 (hd1) (hd1,$SERVICE_PARTITION_IDX)" >>/etc/grub.conf
	fi
        echo "quit" >>/etc/grub.conf
        
        cp -pr /usr/lib/grub /srv/SLEPOS/boot
        ln -sf /srv/SLEPOS/boot/grub /boot
        
	if [ -z "$RAID" ];then
        	echo "(hd0)    $DISK" > /srv/SLEPOS/boot/grub/device.map
        else
	        echo "(hd0)    $raidDiskFirst"  >  /srv/SLEPOS/boot/grub/device.map
	        echo "(hd1)    $raidDiskSecond" >> /srv/SLEPOS/boot/grub/device.map
	fi
        
        
        echo "timeout 0"                                          > /srv/SLEPOS/boot/grub/menu.lst
        echo "title SLEPOS"                                       >>/srv/SLEPOS/boot/grub/menu.lst
        echo "    root (hd0,$SERVICE_PARTITION_IDX)"              >>/srv/SLEPOS/boot/grub/menu.lst
        echo "    kernel /boot/$POS_KERNEL $POS_KERNEL_PARAMS root=$imageDevice"  >>/srv/SLEPOS/boot/grub/menu.lst
        echo "    initrd /boot/$POS_INITRD"                     >>/srv/SLEPOS/boot/grub/menu.lst
        
        /usr/sbin/grub --batch --no-floppy < /etc/grub.conf 1>&2
}

function fetchImageSize
{
	local count=0
	local IFS="," 
	for i in $IMAGE;do
		imageZipped="uncompressed"
		count=$(($count + 1))
		field=0
		IFS=";" ; for n in $i;do
		case $field in
			0) imageDevice=$n ; field=1 ;;
			1) imageName=$n   ; field=2 ;;
			2) imageVersion=$n; field=3 ;;
			3) imageServer=$n ; field=4 ;;
			4) imageBlkSize=$n; field=5 ;;
			5) imageZipped=$n ;
		esac
		done
	done
	if [ $count = 1 ];then
		imageRootDevice=$imageDevice
		imageRootName=$imageName
	fi
	imageName="image/$imageName-$imageVersion"
	imageMD5s="$imageName.md5"
	[ -z "$imageServer" ]  && imageServer=$SERVER
	[ -z "$imageBlkSize" ] && imageBlkSize=8192
	# /.../
	# get image md5sum to be able to check for the size
	# ---
	IFS=$IFS_ORIG
	fetchFile $imageMD5s /etc/image.md5 uncomp $imageServer
	read sum1 blocks blocksize zblocks zblocksize < /etc/image.md5
	needBytes=$(( blocks * blocksize ))
}

function appendWirelessPXENetwork
{
	local prefix=$1
	if [ "$WLAN_DEV" == "$PXE_IFACE" ]; then
		#append wireless configuration to sysconfig file
		local niface=$prefix/etc/sysconfig/network/ifcfg-$PXE_IFACE
		if [ -f "$niface" ] && ! grep -q "^WIRELESS" "$niface" ; then
			echo "WIRELESS='yes'" >> "$niface"
			echo "WIRELESS_WPA_DRIVER='$WIRELESS_WPA_DRIVER'" >> "$niface"
			if [ -n "$WIRELESS_WPA_PSK" -a -n "$WIRELESS_ESSID" ]; then
				# use creds from cmdline
				echo "WIRELESS_ESSID='$WIRELESS_ESSID'" >> "$niface"
				echo "WIRELESS_WPA_PSK='$WIRELESS_WPA_PSK'" >> "$niface"
				echo "WIRELESS_AUTH_MODE='psk'" >> "$niface"
			else
				#use custom wpa_supplicant.conf
				mkdir -p $prefix/etc/wpa_supplicant/
				cp -f /etc/wpa_supplicant/wpa_supplicant.conf $prefix/etc/wpa_supplicant/wpa_supplicant.conf
				echo "WIRELESS_WPA_CONF='/etc/wpa_supplicant/wpa_supplicant.conf'" >> "$niface"
			fi
		fi
	fi
}

function writeManagerConfig
{
	local IFS=";"
	local HOST
	local ACTIVATION_KEY
	[ -z "$SUSEMANAGER" ] && return 1
	
	echo "$SUSEMANAGER" | if read HOST ACTIVATION_KEY ; then
		if [ -f /mnt/etc/sysconfig/suse_manager_client_registration ] ;then
			if ! grep -q "ACTIVATION_KEY=.*$ACTIVATION_KEY" /mnt/etc/sysconfig/suse_manager_client_registration ; then
				sed -i -e "s|MANAGER_HOST=.*|MANAGER_HOST='$HOST'|" /mnt/etc/sysconfig/suse_manager_client_registration
				sed -i -e "s|ACTIVATION_KEY=.*|ACTIVATION_KEY='$ACTIVATION_KEY'|" /mnt/etc/sysconfig/suse_manager_client_registration
				rm -f /mnt/etc/sysconfig/rhn/systemid #trigger new registration
			fi
		else
			Echo "WARNING: Image is built without Manager registration support. Skipping."
		fi
	fi
}
