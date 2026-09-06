#!/bin/bash
# m4b: remove leftover whole-disk ext4 signature, reinstall grub properly, verify
set -u
log(){ echo "### $*"; }

log "wipe leftover filesystem signatures on /dev/sdb (keeps MBR/partitions)"
wipefs -a /dev/sdb
echo "wipefs exit: $?"
lsblk -o NAME,SIZE,FSTYPE /dev/sdb

log "bind mounts"
mount --bind /dev /mnt/newroot/dev
mount -t proc proc /mnt/newroot/proc
mount -t sysfs sys /mnt/newroot/sys

log "grub-install (no pipe, real exit code)"
chroot /mnt/newroot /usr/sbin/grub-install --target=i386-pc --recheck /dev/sdb
echo "GRUB_INSTALL_EXIT=$?"

log "verify MBR stage1 signature"
dd if=/dev/sdb bs=512 count=1 2>/dev/null | grep -c GRUB
ls -la /mnt/newroot/boot/grub/i386-pc/core.img

log "update-grub"
chroot /mnt/newroot /usr/sbin/update-grub > /root/ug.log 2>&1
echo "UPDATE_GRUB_EXIT=$?"
grep -c 'root=UUID=69bc1124' /mnt/newroot/boot/grub/grub.cfg

umount /mnt/newroot/dev
umount /mnt/newroot/proc
umount /mnt/newroot/sys
log "M4B DONE"
