#!/bin/sh
# Not normally run as a shell script - sourced by the /init script
#
# Ensure that the block devices are available
#
# Copyright (C) 2017 Hamish Coleman <hamish@zot.org>

modprobe virtio_blk

