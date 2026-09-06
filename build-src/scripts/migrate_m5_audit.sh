#!/bin/bash
# m5: final read-only boot-readiness audit of the new 130G disk (replayable)
set -u
log(){ echo "### $*"; }

log "fsck -n /dev/sdb1 (root) and /dev/sdb2 (build)"
fsck.ext4 -n -f /dev/sdb1 2>&1 | tail -3
echo "fsck sdb1 exit: $?"
fsck.ext4 -n -f /dev/sdb2 2>&1 | tail -3
echo "fsck sdb2 exit: $?"

log "kernels/initrds present in new /boot"
ls -la /mnt/newroot/boot/ | grep -E 'vmlinuz|initrd'
ls /mnt/newroot/boot/vmlinuz-* 2>/dev/null | wc -l

log "grub.cfg referenced files all exist?"
python3 - <<'PY'
import re, os
p = "/mnt/newroot/boot/grub/grub.cfg"
cfg = open(p, encoding="utf-8", errors="replace").read()
refs = set()
for m in re.finditer(r'(\S*?(?:vmlinuz|initrd\.img)\S*)', cfg):
    t = m.group(1).strip('"')
    if t and t not in refs:
        refs.add(t)
missing = [r for r in refs if not os.path.exists("/mnt/newroot" + r if r.startswith("/") else "/mnt/newroot/boot/" + r)]
print(f"distinct kernel/initrd refs: {len(refs)}")
for r in sorted(refs):
    full = "/mnt/newroot" + r if r.startswith("/") else "/mnt/newroot/boot/" + r
    print(("OK  " if os.path.exists(full) else "MISS") + "  " + r)
print("MISSING:", missing if missing else "none")
PY

log "grub modules dir + core present"
ls /mnt/newroot/boot/grub/i386-pc/core.img /mnt/newroot/boot/grub/i386-pc/*.mod 2>/dev/null | wc -l

log "root boot-critical config"
grep -E '^GRUB_DEFAULT|^GRUB_TIMEOUT' /mnt/newroot/etc/default/grub

log "swap/build fstab targets exist as devices"
ls -la /dev/disk/by-uuid/ 2>/dev/null | grep -E '69bc1124|4e19919d|6e94a2e0'
log "M5 DONE"
