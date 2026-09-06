#!/bin/sh
# Step 2: run INSIDE the FreeBSD 15.1 build VM.
# vtbd0 = FreeBSD system disk; vtbd1 = R4S 26.7.3 image (patch target, RW);
# vtbd2 = OP5P 26.7.3 image (source of the vendor realtek-re-kmod198 driver, RO).
set -u
log() { echo "### $*"; }

log "disks"
ls /dev/vtbd* 2>/dev/null
mkdir -p /mnt/r4s /mnt/op5p /work
cd /work

# --- find & mount the UFS root of a disk image ---
mount_ufs_root() { # $1 device base e.g. vtbd1 ; $2 mountpoint ; $3 rw|ro
  for dev in $(ls /dev/${1}* 2>/dev/null); do
    case "$dev" in
      *s[0-9]*[a-h]|*p[0-9]*|*p[0-9][0-9]*|*s[0-9][0-9]*[a-h])
        t=$(fstyp "$dev" 2>/dev/null) || continue
        if [ "$t" = "ufs" ]; then
          if [ "$3" = "ro" ]; then mount -o ro "$dev" "$2" && { echo "$dev -> $2 (ro)"; return 0; }
          else mount "$dev" "$2" && { echo "$dev -> $2 (rw)"; return 0; }; fi
        fi ;;
    esac
  done
  echo "FAIL: no ufs root found under $1"; return 1
}

mount_ufs_root vtbd1 /mnt/r4s rw || exit 1
mount_ufs_root vtbd2 /mnt/op5p ro || echo "(op5p mount failed, will try aux tar)"

echo "=== r4s /boot/modules listing (before) ==="
ls -la /mnt/r4s/boot/modules/ | head -40
echo "=== op5p: looking for vendor realtek driver ==="
find /mnt/op5p -iname 'if_re.ko*' -o -iname '*realtek*' 2>/dev/null | head -20

SRC_KO=""
for c in /mnt/op5p/boot/modules/if_re.ko /mnt/op5p/boot/kernel/if_re.ko; do
  [ -f "$c" ] && SRC_KO="$c" && break
done

if [ -z "$SRC_KO" ]; then
  echo "vendor if_re.ko not found on op5p root; scanning aux tar"
  # aux tar lives on host at /build/dl/aux-26.7.3-aarch64.tar — fetch via host NAT is not
  # available; instead we re-download it here (smaller than images).
  curl -sSL -o aux.tar https://github.com/matheusber/opnsense/releases/download/26.7.3/aux-26.7.3-aarch64.tar
  echo "aux listing (realtek):"
  tar tf aux.tar | grep -i realtek | head
fi

if [ -n "$SRC_KO" ]; then
  echo "=== vendor driver found: $SRC_KO ==="
  ls -la "$SRC_KO"
  echo "--- strings checks ---"
  strings "$SRC_KO" | grep -iE 'realtek|1\.98|198|if_re' | head -10

  echo "=== apply to r4s root ==="
  RKO=/mnt/r4s/boot/modules/if_re.ko
  if [ -f "$RKO" ]; then cp -p "$RKO" "${RKO}.base"; echo "backup: ${RKO}.base"; fi
  cp -p "$SRC_KO" "$RKO"
  chown root:wheel "$RKO"; chmod 555 "$RKO"
  echo "replaced: $(ls -la $RKO)"

  echo "=== loader.conf.local ==="
  LCL=/mnt/r4s/boot/loader.conf.local
  if [ -f "$LCL" ] && grep -q 'if_re_load' "$LCL"; then
    echo "already contains if_re_load"
  else
    { echo "# --- r4s fixed build: vendor Realtek driver 1.98 (re0/RTL8111H) ---"
      echo 'if_re_load="YES"'
      echo 'if_re_name="/boot/modules/if_re.ko"'
    } >> "$LCL"
  fi
  cat "$LCL"
else
  echo "!!! no vendor driver available anywhere; loader change skipped"
fi

echo "=== sync /etc/rc from opnsense/core (matheusber caveat) ==="
curl -sSL -o /tmp/rc.core https://raw.githubusercontent.com/opnsense/core/master/src/etc/rc
if [ -s /tmp/rc.core ]; then
  if ! cmp -s /tmp/rc.core /mnt/r4s/etc/rc; then
    cp -p /mnt/r4s/etc/rc /mnt/r4s/etc/rc.orig-26.7.3
    cp -p /tmp/rc.core /mnt/r4s/etc/rc
    chmod 555 /mnt/r4s/etc/rc
    echo "etc/rc replaced (backup rc.orig-26.7.3)"
  else
    echo "etc/rc already current"
  fi
fi

echo "=== bake check tools into /root of image ==="
cat > /mnt/r4s/root/niccheck.sh << 'EOF'
#!/bin/sh
echo "===== NIC check (fixed build) ====="
echo "--- ifconfig ---"
ifconfig | grep -E '^[a-z0-9]+[0-9]*:|ether|media:' | head -40
echo "--- pciconf ---"
pciconf -lv 2>/dev/null | grep -A3 -iE 'realtek|ethernet'
echo "--- dmesg nic ---"
dmesg | grep -iE 're0|dwc0|if_re|realtek' | head -20
echo "--- module ---"
kldstat | grep -E 'if_re|kernel'
echo "if two interfaces (re0 + dwc0) are listed above, the fix is working."
EOF
chmod 755 /mnt/r4s/root/niccheck.sh
cat > /mnt/r4s/root/README-REPAIR.txt << 'EOF'
R4S fixed build (26.7.3 base)
- baked in: Realtek vendor driver realtek-re-kmod198 (v1.98) loaded via
  /boot/loader.conf.local (if_re_load) so the PCIe RTL8111H port shows up as re0.
- stock base driver backed up at /boot/modules/if_re.ko.base
- /etc/rc synced with opnsense/core master (see /etc/rc.orig-26.7.3)
After first boot run: /root/niccheck.sh  -> expect re0 AND dwc0.
If re0 is still missing, capture /root/niccheck.sh output + `dmesg` and report back.
Revert driver: cp /boot/modules/if_re.ko.base /boot/modules/if_re.ko && remove
if_re_load lines from /boot/loader.conf.local, then reboot.
EOF
echo "baked files:"
ls -la /mnt/r4s/root/niccheck.sh /mnt/r4s/root/README-REPAIR.txt

echo "=== sync & unmount ==="
sync
umount /mnt/r4s
umount /mnt/op5p 2>/dev/null
echo "STEP2 DONE"
