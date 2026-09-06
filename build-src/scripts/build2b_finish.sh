#!/bin/sh
# Step 2b: finish rc sync + make vendor driver win on every load path.
set -u
log() { echo "### $*"; }
mkdir -p /mnt/r4s /mnt/op5p
mount /dev/vtbd1s2a /mnt/r4s
mount -o ro /dev/vtbd2s2a /mnt/op5p

log "kernel dir if_re check"
ls -la /mnt/r4s/boot/kernel/ | grep -i if_re || echo "no if_re in /boot/kernel"
ls -la /mnt/r4s/boot/modules/

log "sync /etc/rc from opnsense/core (via fetch)"
fetch -q -o /tmp/rc.core https://raw.githubusercontent.com/opnsense/core/master/src/etc/rc 2>/dev/null
if [ -s /tmp/rc.core ]; then
  if ! cmp -s /tmp/rc.core /mnt/r4s/etc/rc; then
    cp -p /mnt/r4s/etc/rc /mnt/r4s/etc/rc.orig-26.7.3
    cp -p /tmp/rc.core /mnt/r4s/etc/rc
    chmod 555 /mnt/r4s/etc/rc
    log "etc/rc replaced (backup rc.orig-26.7.3); diff lines: $(diff /tmp/rc.core /mnt/r4s/etc/rc.orig-26.7.3 2>/dev/null | wc -l)"
  else
    log "etc/rc already current"
  fi
else
  log "fetch of core rc failed"
fi

log "ensure vendor module in /boot/kernel too (backup base)"
if [ -f /mnt/r4s/boot/kernel/if_re.ko ]; then
  cp -p /mnt/r4s/boot/kernel/if_re.ko /mnt/r4s/boot/kernel/if_re.ko.base
  log "backed up kernel if_re.ko -> if_re.ko.base"
fi
cp -p /mnt/op5p/boot/modules/if_re.ko /mnt/r4s/boot/kernel/if_re.ko 2>/dev/null || true
# also keep a copy of vendor driver inside the image for manual reload
cp -p /mnt/op5p/boot/modules/if_re.ko /mnt/r4s/root/if_re-vendor-1.98.ko 2>/dev/null
ls -la /mnt/r4s/boot/modules/ /mnt/r4s/boot/kernel/ | grep if_re
sync
umount /mnt/r4s
log "STEP2B DONE"
