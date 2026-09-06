#!/bin/sh
# compare_insides: run INSIDE the FreeBSD dissect VM.
# vtbd1 = OPNsense 22.7 R4S image (ro), vtbd2 = OPNsense 26.7.3 fixed image (ro)
set -u
log(){ echo "### $*"; }
mkdir -p /mnt/a /mnt/b

# mount ufs root of each (MBR: s2a)
mount -o ro /dev/vtbd1s2a /mnt/a && echo "22.7 mounted"
mount -o ro /dev/vtbd2s2a /mnt/b && echo "26.7 mounted"

log "== 1. kernel driver presence (per image) =="
for d in a b; do
  echo "### image $d"
  for s in "Rockchip PCIe controller" "Gen1 link training" "OFW PCI bus" "pci_host_generic"; do
    echo "  '$s': $(strings /mnt/$d/boot/kernel/kernel | grep -c "$s")"
  done
  echo "  kernel size: $(ls -la /mnt/$d/boot/kernel/kernel | awk '{print $5}')"
  echo "  modules dir files: $(ls /mnt/$d/boot/modules 2>/dev/null | wc -l), kernel dir files: $(ls /mnt/$d/boot/kernel | wc -l)"
done

log "== 2. if_re / realtek handling in each image =="
for d in a b; do
  echo "--- image $d"
  ls -la /mnt/$d/boot/modules/if_re.ko /mnt/$d/boot/kernel/if_re.ko 2>&1 | head -4
  ls /mnt/$d/usr/local/share/licenses/ 2>/dev/null | grep -i realtek || echo "no realtek pkg record"
done

log "== 3. u-boot version from raw sectors (vtbd1=22.7, vtbd2=26.7) =="
for dev in vtbd1 vtbd2; do
  echo "--- $dev (seek 16384 itb)"
  dd if=/dev/$dev bs=512 skip=16384 count=2000 2>/dev/null | strings | grep -m1 'U-Boot 20'
done

log "== 4. dtb present? compare pcie node =="
for d in a b; do
  echo "--- image $d boot files"
  ls /mnt/$d/boot/ 2>/dev/null | head -20
  find /mnt/$d/boot -name '*.dtb' 2>/dev/null | head
done

log "== 5. loader.conf (pcie-related & console) =="
for d in a b; do
  echo "--- image $d /boot/loader.conf"
  grep -vE '^#|^$' /mnt/$d/boot/loader.conf 2>/dev/null | head -30
done

umount /mnt/b 2>/dev/null; umount /mnt/a 2>/dev/null
echo INSIDE_COMPARE_DONE
