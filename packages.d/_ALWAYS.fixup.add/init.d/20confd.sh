# Apply configurations from conf.d
#
# Copyright (C) 2018 Benedict Lau <benedict.lau@groundupworks.com>

CONFDIR=conf.d

try_partition() {
    # Create file system node from partition
    mknod /dev/$1 b $2 $3 2>/dev/null

    # Mount partition as read-only
    mount /dev/$1 /mnt -o ro
    S=$?

    if [ $S -ne 0 ]; then
        echo "Error: mount /dev/$1 to /mnt as read-only failed"
        return $S
    fi

    # Find conf.d in root of partition and process in alphabetical order
    if [ -d "/mnt/$CONFDIR" ]; then
        # Extract each tar.gz archive into /etc overwriting existing files
        for conf in /mnt/$CONFDIR/*.tar.gz; do
            echo Applying configurations from /dev/$1: $conf
            tar --warning=no-timestamp --extract -f $conf -C /etc
            S=$?

            if [ $S -ne 0 ]; then
                echo "Error: extract $conf from /dev/$1 into /etc failed"
                return $S
            fi
        done

        # Execute each sh script
        for conf in /mnt/$CONFDIR/*.sh; do
            echo Executing configurations from /dev/$1: $conf
            . $conf
            S=$?

            if [ $S -ne 0 ]; then
                echo "Error: execute $conf from /dev/$1 failed"
                return $S
            fi
        done
    fi

    # Unmount partition
    umount /mnt
    S=$?

    if [ $S -ne 0 ]; then
        echo "Error: umount /dev/$1 from /mnt failed"
        return $S
    fi

    return 0
}

# Mount proc
mount -t proc proc /proc

cat /proc/partitions | while read major minor size name; do
    # Check each partition matching sd*[0-9] (e.g. sda1) or mmcblk*p* (e.g. mmcblk0p1)
    case $name in
        vd*[0-9]|sd*[0-9]|mmcblk*p*)
            echo Checking for configuration files on $name
            try_partition $name $major $minor
            S=$?

            if [ $S -ne 0 ]; then
                echo "Error: processing of configuration files on $name failed"
            fi
            ;;
    esac
done
