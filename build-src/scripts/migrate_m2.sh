#!/bin/bash
# m2: repartition sdb -> sdb1 / (24G), sdb2 /build (~rest), sdb3 swap (1G)  [DESTRUCTIVE - approved]
set -u
log(){ echo "### $*"; }

log "pre-check: nothing should be using /dev/sdb besides /build mount"
mount | grep -E '/dev/sdb' || echo "only /build expected"
fuser -vm /build 2>&1 | head -5 || true

log "umount /build"
umount /build && echo "umounted OK"

log "wipe + create partition table (msdos)"
parted -s /dev/sdb -- mklabel msdos
parted -s /dev/sdb -- mkpart primary ext4 1MiB 24GiB
parted -s /dev/sdb -- set 1 boot on
parted -s /dev/sdb -- mkpart primary ext4 24GiB -1GiB
parted -s /dev/sdb -- mkpart primary linux-swap -1GiB 100%
parted -s /dev/sdb print | tail -12

log "wait for kernel partitions"
sleep 2
lsblk /dev/sdb -o NAME,SIZE,TYPE,FSTYPE

log "mkfs"
mkfs.ext4 -F -q -L root /dev/sdb1
mkfs.ext4 -F -q -L build /dev/sdb2
mkswap /dev/sdb3
swapon /dev/sdb3 && echo "swap on (temp)"
blkid /dev/sdb1 /dev/sdb2 /dev/sdb3

log "mount new"
mkdir -p /mnt/newroot /mnt/newbuild
mount /dev/sdb1 /mnt/newroot
mount /dev/sdb2 /mnt/newbuild
df -h /mnt/newroot /mnt/newbuild | tail -3
log "M2 DONE"
