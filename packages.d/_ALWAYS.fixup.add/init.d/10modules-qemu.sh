#!/bin/sh
# Not normally run as a shell script - sourced by the /init script
#
# Ensure that the block devices are available
#
# Copyright (C) 2017 Hamish Coleman <hamish@zot.org>

# FIXME
# - this list could get long and unmaintainable
# - if we load the wrong module on a different system, we might get errors
#   (which are both unsightly and making checking for real errors harder)
#
# TODO
# - running with our own kernel will allow us to be sure to build-in the right
#   drivers for block devices

modprobe virtio_blk
modprobe virtio_pci

