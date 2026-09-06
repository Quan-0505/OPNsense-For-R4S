#!/bin/bash
# m2b: repartition sdb with sfdisk -> sdb1 / (24GiB), sdb2 /build (rest-1GiB), sdb3 swap (1GiB)
set -u
log(){ echo "### $*"; }

TOTAL=$(blockdev --getsz /dev/sdb)
S1_START=2048
S1_SIZE=$((24*1024*1024*1024/512))          # 24GiB
S2_START=$((S1_START + S1_SIZE))
SWAP_SIZE=$((1*1024*1024*1024/512))          # 1GiB
S2_SIZE=$((TOTAL - S2_START - SWAP_SIZE))
S3_START=$((S2_START + S2_SIZE))
log "total=$TOTAL sectors; sdb1=$S1_START+$S1_SIZE; sdb2=$S2_START+$S2_SIZE; sdb3=$S3_START+$SWAP_SIZE"

sfdisk -Y dos /dev/sdb <<EOF
label: dos
unit: sectors
1 : start=$S1_START, size=$S1_SIZE, type=83, bootable
2 : start=$S2_START, size=$S2_SIZE, type=83
3 : start=$S3_START, size=$SWAP_SIZE, type=82
EOF
echo "sfdisk exit: $?"

sleep 2
partx -u /dev/sdb 2>/dev/null || true
sleep 1
lsblk /dev/sdb -o NAME,SIZE,TYPE,FSTYPE

log "mkfs"
mkfs.ext4 -F -q -L root /dev/sdb1 && echo "sdb1 ok"
mkfs.ext4 -F -q -L build /dev/sdb2 && echo "sdb2 ok"
mkswap /dev/sdb3 && echo "sdb3 ok"
swapon /dev/sdb3 && echo "swap on"
blkid /dev/sdb1 /dev/sdb2 /dev/sdb3

log "mount new"
mkdir -p /mnt/newroot /mnt/newbuild
mount /dev/sdb1 /mnt/newroot
mount /dev/sdb2 /mnt/newbuild
df -h /mnt/newroot /mnt/newbuild | tail -3
log "M2B DONE"
