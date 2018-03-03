#!/bin/sh
# Not normally run as a shell script - sourced by the /init script
#
# Finish up our pre-boot by starting systemd

exec /lib/systemd/systemd
