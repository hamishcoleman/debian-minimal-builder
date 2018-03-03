#!/bin/sh
# Not normally run as a shell script - sourced by the /init script
#
# Apply configurations from conf.d
#
# Copyright (C) 2018 Benedict Lau <benedict.lau@groundupworks.com>

CONFDIR=conf.d

try_partition() {
    echo "Checking for configuration files on $name"

    # Create file system node from partition
    mknod "/dev/$1" b "$2" "$3" 2>/dev/null

    # Mount partition as read-only
    mount "/dev/$1" /mnt -o ro
    S=$?

    if [ $S -ne 0 ]; then
        echo "Error: mount /dev/$1 to /mnt as read-only failed"
        return $S
    fi

    # Find conf.d in root of partition and process in alphabetical order
    if [ -d "/mnt/$CONFDIR" ]; then
        # Extract each tar.gz archive into /etc overwriting existing files
        for conf in /mnt/$CONFDIR/*.tar.gz; do
            if [ ! -r "$conf" ]; then
                continue
            fi

            echo "Applying configurations from /dev/$1: $conf"
            tar --warning=no-timestamp --extract -f "$conf" -C /etc
            S=$?

            if [ $S -ne 0 ]; then
                echo "Error: extract $conf from /dev/$1 into /etc failed"
                return $S
            fi
        done

        # Execute each sh script
        for script in /mnt/$CONFDIR/*.sh; do
            if [ -x "$script" ]; then
                echo "Executing configurations from /dev/$1: $script"
                # shellcheck disable=SC1090
                . "$script"
                S=$?

                if [ $S -ne 0 ]; then
                    echo "Error: execute $script from /dev/$1 failed"
                    return $S
                fi
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
if [ ! -f /proc/partitions ]; then
    mount -t proc proc /proc
fi

found_any=0
while read -r major minor size name; do
    # Check each partition matching sd*[0-9] (e.g. sda1) or mmcblk*p* (e.g. mmcblk0p1)
    case $name in
        vd*[0-9]|sd*[0-9]|mmcblk*p*)
            found_any=1
            try_partition "$name" "$major" "$minor"
            S=$?

            if [ $S -ne 0 ]; then
                echo "Error: processing of configuration files on $name failed"
            fi
            ;;
    esac

    echo "$size" >/dev/null # make size look used to shellcheck
done </proc/partitions

if [ "$found_any" = "0" ]; then
    echo Error: No partitions were found, are the right modules loaded?
fi
