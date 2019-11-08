# call it unconditionally, it could block filesystem check and partitioning
umountServicePartition

setupDataPartFilesystem

if mountServicePartition ; then
	syncServicePartition
	installServiceGrub
	export DO_NOT_INSTALL_BOOTLOADER=yes

	SERVICE_FREE_SPACE=`df -BK /srv/SLEPOS |grep /srv/SLEPOS |sed -e "s|.*[0-9]*K *[0-9]*K *\([0-9]*\)K *[0-9]*%.*|\1|"`
	fetchImageSize
	if [ -n "$SERVICE_FREE_SPACE" -a -n "$needBytes" -a "0" -lt "$needBytes" -a "$(( SERVICE_FREE_SPACE * 1024 ))" -gt "$needBytes" ]; then
		mkdir -p /srv/SLEPOS/image
		export FETCH_FILE_TEMP_DIR=/srv/SLEPOS/image
	fi
	export KIWI_LOCAL_CACHE_DIR=/srv/SLEPOS
fi

#now we have installed the kernel with correct params - now we can reboot
#let's download the system image using the new kernel params (for example
#kiwiservertye does matter)
#
# if have POS_KERNEL_PARAMS_HASH or we will have it after reboot
if ( [ -n "$POS_KERNEL_PARAMS_HASH" ] || echo "$POS_KERNEL_PARAMS" |grep -q "POS_KERNEL_PARAMS_HASH=" ) && \
     [ -n "$POS_KERNEL_PARAMS_HASH_VERIFY" -a \
     "$POS_KERNEL_PARAMS_HASH" !=    "$POS_KERNEL_PARAMS_HASH_VERIFY" ] ; then

	Echo "Kernel parameters have changed"
	if [ -f /sbin/kexec -a \
	     -f "/srv/SLEPOS/boot/$POS_KERNEL" -a \
	     -f "/srv/SLEPOS/boot/$POS_INITRD" ];then
		kexec -l "/srv/SLEPOS/boot/$POS_KERNEL" \
			--append="$POS_KERNEL_PARAMS" --initrd="/srv/SLEPOS/boot/$POS_INITRD"
		if [ $? = 0 ];then
			#======================================
			# go for gold
			#--------------------------------------
			exec kexec -e
		fi
		Echo "Kexec failed"
	fi

	umountServicePartition
	
	Echo "reboot to load new kernel parameters: consoles at Alt-F3/F4"
	Echo "reboot in 10 sec..."; sleep 10
	/sbin/reboot -f -i
fi
