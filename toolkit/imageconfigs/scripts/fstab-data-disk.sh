#!/bin/bash

set -euxo pipefail

cat /etc/fstab

if ! grep -q "/dev/disk/cloud/azure_resource-part1" /etc/fstab; then
    echo "Adding /dev/disk/cloud/azure_resource-part1 to /etc/fstab"
    echo "/dev/disk/cloud/azure_resource-part1    /mnt    auto    defaults,nofail,x-systemd.after=cloud-init.service,_netdev,comment=cloudconfig  0       2" >> /etc/fstab
    cat /etc/fstab
else
    echo "/dev/disk/cloud/azure_resource-part1 already exists in /etc/fstab"
fi
