#!/bin/sh
# Step 3: verify patched r4s image (runs inside FreeBSD VM)
set -u
echo "### fsck (read-only) on patched r4s root partition"
fsck_ufs -n /dev/vtbd1s2a 2>&1 | tail -6

echo "### structural checks (mount ro)"
mkdir -p /mnt/v
mount -o ro /dev/vtbd1s2a /mnt/v

echo "--- /boot/loader.conf.local ---"
cat /mnt/v/boot/loader.conf.local

echo "--- key files ---"
ls -la /mnt/v/boot/modules/if_re.ko \
       /mnt/v/boot/kernel/if_re.ko \
       /mnt/v/boot/kernel/if_re.ko.base \
       /mnt/v/etc/rc \
       /mnt/v/etc/rc.orig-26.7.3 \
       /mnt/v/root/niccheck.sh \
       /mnt/v/root/README-REPAIR.txt 2>&1

echo "--- /etc/rc sanity (header + checksum vs core) ---"
head -1 /mnt/v/etc/rc
sh -n /mnt/v/etc/rc && echo "rc syntax OK"
sha256 /mnt/v/etc/rc /mnt/v/boot/modules/if_re.ko 2>/dev/null

echo "--- README head ---"
head -3 /mnt/v/root/README-REPAIR.txt

umount /mnt/v
echo "STEP3 DONE"
