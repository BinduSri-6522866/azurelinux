#!/bin/bash

set -ex

# TODO: figure out why we are missing systemd-machine-id-commit service, which should automate this
if [ "$1" == "commit-machine-id" ]; then
    MACHINEID=`cat /etc/machine-id`
    echo $MACHINEID
    # if machine-id has a mount point, unmount it
    if grep -q /etc/machine-id /proc/mounts; then
        umount /etc/machine-id
    fi
fi

mount -t overlay overlay -o lowerdir=/etc,upperdir=/overlays/etc/upper,workdir=/overlays/etc/work /etc
# Workaround for https://dev.azure.com/mariner-org/ECF/_workitems/edit/7349/
chmod o+rx /etc

if [ "$1" == "commit-machine-id" ]; then
    echo Committing machine-id
    echo $MACHINEID > /etc/machine-id
    cat /etc/machine-id
fi