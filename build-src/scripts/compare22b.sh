#!/bin/sh
# compare22b: mount 22.7 (vtbd1, GPT) + 26.7 fixed (vtbd2) and compare kernels/u-boot/dtb
set -u
log(){ echo "### $*"; }

mount_any_root() { # $1 devbase, $2 mountpoint
  mkdir -p "$2"
  for cand in $(ls /dev/${1}p* /dev/${1}s* 2>/dev/null); do
    t=$(fstyp "$cand" 2>/dev/null)
    if [ "$t" = "ufs" ]; then
      if mount -o ro "$cand" "$2" 2>/dev/null; then
        if [ -d "$2/boot/kernel" ]; then echo "ROOT: $cand -> $2"; return 0; fi
        umount "$2"
      fi
    fi
  done
  # whole-disk ufs fallback (some images are raw fs)
  t=$(fstyp /dev/$1 2>/dev/null)
  if [ "$t" = "ufs" ] && mount -o ro /dev/$1 "$2" 2>/dev/null; then
    echo "ROOT: /dev/$1 (whole) -> $2"; return 0
  fi
  echo "NO ROOT for $1"; return 1
}

log "== partition maps =="
gpart show vtbd1 2>&1 | head -25
gpart show vtbd2 2>&1 | head -10

mount_any_root vtbd1 /mnt/a || true
mount_any_root vtbd2 /mnt/b || true

for d in a b; do
  echo "##### IMAGE $d"
  [ -d /mnt/$d/boot/kernel ] || { echo "no /boot/kernel"; continue; }
  K=/mnt/$d/boot/kernel/kernel
  ls -la $K | awk '{print "kernel:",$5,"bytes"}'
  for s in "Rockchip PCIe controller" "Gen1 link training" "OFW PCI bus" "pci_host_generic"; do
    echo "  '$s': $(strings $K | grep -c "$s")"
  done
  echo "  boot layout:"; ls /mnt/$d/boot/ | tr '\n' ' '; echo
  echo "  dtb r4s/rk3399:"; find /mnt/$d/boot -iname '*r4s*.dtb' -o -iname 'rk3399-nanopi*.dtb' 2>/dev/null
  echo "  loader.conf pcie-ish:"; grep -iE 'pci|hint' /mnt/$d/boot/loader.conf 2>/dev/null | head -10
done

log "== u-boot strings =="
for dev in vtbd1 vtbd2; do
  echo "$dev:"; dd if=/dev/$dev bs=512 skip=16384 count=3000 2>/dev/null | strings | grep -m2 'U-Boot 20'
done

umount /mnt/b 2>/dev/null; umount /mnt/a 2>/dev/null
echo CMP22B_DONE
