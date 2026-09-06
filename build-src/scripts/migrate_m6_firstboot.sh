#!/bin/bash
# m6: first-boot verification on the 130G disk (run on the migrated system)
set -u
log(){ echo "### $*"; }

log "whoami/hostname/uptime"
hostname; uptime
log "booted root device"
findmnt / -o SOURCE,FSTYPE,SIZE -n
log "lsblk (expect ONLY sdb now, no sda)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
log "df"
df -hT | grep -vE 'tmpfs|udev|overlay' | grep -E '/$|/build|Filesystem'
log "swap"
swapon --show
log "fstab on booted root"
cat /etc/fstab
log "dmesg filesystem errors"
dmesg | grep -iE 'ext4.*error|I/O error|mount.*fail' | head -5 || echo "no fs errors in dmesg"
journalctl -b -p err --no-pager 2>/dev/null | grep -iE 'ext4|mount' | head -5 || true

log "grub.cfg referenced kernel/initrd files exist?"
python3 - <<'PY'
import re, os
p = "/boot/grub/grub.cfg"
cfg = open(p, encoding="utf-8", errors="replace").read()
refs = set()
for m in re.finditer(r'(\S*?(?:vmlinuz|initrd\.img)\S*)', cfg):
    t = m.group(1).strip('"')
    if t: refs.add(t)
missing = [r for r in refs if not os.path.exists(r if r.startswith("/") else "/boot/" + r)]
print(f"refs={len(refs)} missing={missing if missing else 'none'}")
PY

log "build data present?"
echo "entries: $(find /build | wc -l)  (expect 88358)"
du -sh /build
ls /build | head -10
echo "DaedNext:"; ls /build/DaedNext | head -3
echo "fixed image:"; ls -la /build/images/OPNsense-26.7.3-fixed-R4S.img.xz 2>/dev/null || echo "not in images (check dl)"

log "root data present?"
ls /root/migrate_m0.sh /etc/hostname 2>&1
echo "M6 DONE"
