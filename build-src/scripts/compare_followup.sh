#!/bin/sh
# follow-up: find & mount 22.7 root properly, then kernel/DTB comparisons
set -u
log(){ echo "### $*"; }
mkdir -p /mnt/a

log "22.7 image (vtbd1) partition map"
gpart show vtbd1 2>&1 | head -30
ls /dev/vtbd1*

log "try mounting candidates to find root (has /boot/kernel)"
for cand in vtbd1s1a vtbd1s2a vtbd1p1 vtbd1p2 vtbd1p3 vtbd1s1 vtbd1s2; do
  [ -e /dev/$cand ] || continue
  t=$(fstyp /dev/$cand 2>/dev/null)
  echo "candidate $cand type=$t"
  if [ "$t" = "ufs" ]; then
    mkdir -p /mnt/x && umount /mnt/x 2>/dev/null
    if mount -o ro /dev/$cand /mnt/x 2>/dev/null; then
      if [ -d /mnt/x/boot/kernel ]; then
        echo "ROOT FOUND: $cand"
        umount /mnt/x
        mount -o ro /dev/$cand /mnt/a && echo "mounted root at /mnt/a"
        break
      fi
      umount /mnt/x
    fi
  fi
done

log "== 22.7 kernel driver check =="
K=/mnt/a/boot/kernel/kernel
ls -la $K 2>&1 | head -2
for s in "Rockchip PCIe controller" "Gen1 link training" "OFW PCI bus" "pci_host_generic" "designware"; do
  echo "  '$s': $(strings $K 2>/dev/null | grep -c "$s")"
done

log "== 22.7 boot dir / dtb =="
ls /mnt/a/boot/ 2>/dev/null | head -25
find /mnt/a/boot -iname '*r4s*.dtb' -o -iname 'rk3399*.dtb' 2>/dev/null | head
log "== 22.7 loader.conf =="
grep -vE '^#|^$' /mnt/a/boot/loader.conf 2>/dev/null | head -20

umount /mnt/a 2>/dev/null
echo FUP_DONE
