# call it unconditionally, just to be sure
umountServicePartition


if [ $LOCAL_BOOT = "no" ] && [ $systemIntegrity = "clean" ];then
	if [ ! -z "$DISK" ];then
		updateLUKSDeviceFstab /config
	fi
fi

applyHWTypeConfig

writeManagerConfig

if [ $LOCAL_BOOT = "no" ];then
	count=0
	IFS="," ; for i in $IMAGE;do
		count=$(($count + 1))
		field=0
		IFS=";" ; for n in $i;do
			case $field in
				0) field=1 ;;
				1) imageName=$n   ; field=2 ;;
				2) imageVersion=$n; field=3 ;;
				3) imageServer=$n ; field=4 ;;
				4) imageBlkSize=$n; field=5 ;;
				5) imageZipped=$n ;
			esac
		done
		break; # we currently don't support more images than one
	done
	IFS=$IFS_ORIG
	Echo "Notify of new image: image/$imageName"
	echo "image/$imageName" > bootversion.$DHCPCHADDR
	echo "$imageVersion"   >> bootversion.$DHCPCHADDR
	echo "IPADDR=$IPADDR"  >> bootversion.$DHCPCHADDR
	echo "HWBIOS=$HWBIOS"  >> bootversion.$DHCPCHADDR
	echo "HWTYPE=$HWTYPE"  >> bootversion.$DHCPCHADDR
	echo "POS_MAC=$(echo $(hwinfo --netcard |grep "HW Address:" |cut -d : -f 2- ) )" |sed -e "s| |,|g" >> bootversion.$DHCPCHADDR
	POS_CFG_HASH="`md5sum $CONFIG|cut -d ' ' -f 1`"
	echo "POS_CFG_HASH=$POS_CFG_HASH"  >> bootversion.$DHCPCHADDR
	if [ -n "$ROLLBACK_CONFIG" ]; then
		echo "POS_ROLLBACK=1"  >> bootversion.$DHCPCHADDR
	fi
	putFile bootversion.$DHCPCHADDR upload/bootversion.$DHCPCHADDR
	rm -f bootversion.$DHCPCHADDR
fi

if [ -n "$kiwidebug" ]; then
	uploadLog
fi

stopHaveged

if [ -n "$WLAN_DEV" ]; then
	#stop wpa_supplicant
	killall wpa_supplicant

	appendWirelessPXENetwork /config
fi

if [ "x$POS_IFCFG_UPDATE" == "xno" ]; then
	#do not configure network
	rm -f /config/etc/sysconfig/network/ifcfg-$PXE_IFACE
elif [ "x$POS_IFCFG_UPDATE" == "xforce" -a $systemIntegrity != "clean" \
		-a -n "$PXE_IFACE" ]; then #with no working PXE_IFACE keep the original config even with force
	find /mnt/etc/sysconfig/network/ -name "ifcfg-*" -a \! -name "ifcfg-lo" -exec rm -f {} \;
	setupDefaultPXENetwork /mnt
	appendWirelessPXENetwork /mnt
fi

censorLog

