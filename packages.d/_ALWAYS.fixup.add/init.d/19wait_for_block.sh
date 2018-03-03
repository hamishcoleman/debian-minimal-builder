#!/bin/sh
# Not normally run as a shell script - sourced by the /init script
#
# Pause for long enough for the block devices to enumerate
#
# Copyright (C) 2017 Hamish Coleman <hamish@zot.org>

# Ideally, we woulc be able to use something like "udevadm settle", but that
# is not going to be working this early in the boot

# FIXME
# - on a system with no block devices (or the wrong modules loaded) this means
#   we have an even longer wait for the bootup to finish :-(

# Mount proc
if [ ! -f /proc/partitions ]; then
    mount -t proc proc /proc
fi

# Wait for up to 20 seconds for block devices to appear
count=0
while [ "$(grep -cv ram /proc/partitions)" -lt 3 ] && [ $count -lt 20 ]; do
    echo Waiting for block devices
    count=$((count+1))
    sleep 1s
done

