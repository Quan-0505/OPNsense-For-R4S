#!/bin/bash
# m4c: zero the pre-partition gap (removes stray ext4 sig), reinstall grub, verify MBR
set -u
log(){ echo "### $*"; }

log "zero sectors 1..2047 (MBR gap, keeps sector0 MBR + partitions intact)"
dd if=/dev/zero of=/dev/sdb bs=512 seek=1 count=2047 conv=notrunc status=none
echo "dd exit: $?"
# confirm blkid no longer sees a whole-disk fs
blkid /dev/sdb || echo "no whole-disk signature (good)"

log "bind mounts"
mount --bind /dev /mnt/newroot/dev
mount -t proc proc /mnt/newroot/proc
mount -t sysfs sys /mnt/newroot/sys

log "grub-install"
chroot /mnt/newroot /usr/sbin/grub-install --target=i386-pc --recheck /dev/sdb
echo "GRUB_INSTALL_EXIT=$?"

log "verify"
echo "MBR 'GRUB' count: $(dd if=/dev/sdb bs=512 count=1 2>/dev/null | grep -ac GRUB)"
ls -la /mnt/newroot/boot/grub/i386-pc/core.img

umount /mnt/newroot/dev
umount /mnt/newroot/proc
umount /mnt/newroot/sys
log "M4C DONE"
