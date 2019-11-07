uploadLog

# Log to the branch server that we have failed (TE)
/etc/init.d/syslog start
/usr/sbin/busybox logger -t "KIWI Imaging" "Failed!"
