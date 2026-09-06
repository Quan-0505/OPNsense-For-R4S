#!/bin/bash
# m4: finalize new root: mirror sync, fstab, grub install on /dev/sdb
set -u
log(){ echo "### $*"; }

log "verify /build restore entry count (expect 88358)"
find /mnt/newbuild | wc -l
du -sh /mnt/newbuild

log "pass2 mirror rsync (--delete)"
rsync -aAXHx --numeric-ids --delete / /mnt/newroot/ > /root/rsync2.log 2>&1
echo "rsync2 exit: $?"
tail -1 /root/rsync2.log

log "write new fstab"
cat > /mnt/newroot/etc/fstab <<'EOF'
# /etc/fstab: static file system information.
# Managed by migration to 130G disk (2026-09-03)
UUID=69bc1124-7c5f-4907-8d27-32308884323a /               ext4    errors=remount-ro 0       1
UUID=6e94a2e0-1811-45e8-a2ad-e7fd9492c2f6 none            swap    sw              0       0
UUID=4e19919d-969d-480b-8c3e-4c0189161c69 /build          ext4    defaults        0       2
/dev/sr0        /media/cdrom0   udf,iso9660 user,noauto     0       0
EOF
cat /mnt/newroot/etc/fstab

log "chroot bind mounts"
mount --bind /dev /mnt/newroot/dev
mount --bind /dev/pts /mnt/newroot/dev/pts 2>/dev/null || true
mount -t proc proc /mnt/newroot/proc
mount -t sysfs sys /mnt/newroot/sys

log "grub install on /dev/sdb (inside chroot)"
chroot /mnt/newroot /bin/bash -c 'grub-install --target=i386-pc --recheck /dev/sdb 2>&1 | tail -4'
echo "grub-install exit: $?"

log "update-grub (regenerate grub.cfg with new UUIDs)"
chroot /mnt/newroot /bin/bash -c 'update-grub 2>&1 | tail -6'
echo "update-grub exit: $?"

log "verify grub.cfg root uuid"
grep -o 'root=UUID=[a-f0-9-]*' /mnt/newroot/boot/grub/grub.cfg | head -3

log "unmount chroot"
umount /mnt/newroot/dev/pts 2>/dev/null || true
umount /mnt/newroot/dev
umount /mnt/newroot/proc
umount /mnt/newroot/sys

log "final state"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
df -h /mnt/newroot /mnt/newbuild | tail -3
log "M4 DONE"
