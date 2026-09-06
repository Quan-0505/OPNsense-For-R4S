#!/bin/bash
# make uboot2020 transplant image: 26.7.3-fixed rootfs/kernel + 22.7(2020.07) u-boot raw area
set -u
cd /build/images || exit 1
SRC22=opnsense227-r4s.img      # 3.0G GPT, u-boot 2020.07 raw sectors 64..32767
BASE=opnsense2673-fixed.img    # 4.0G MBR, u-boot 2025.10 raw sectors 64..32767
OUT=OPNsense-26.7.3-fixed-uboot2020-R4S.img

echo "### extract u-boot raw area from 22.7 (sectors 64..32767, keep MBR/GPT/partitions)"
dd if=$SRC22 of=/tmp/uboot2020.bin bs=512 skip=64 count=$((32768-64)) status=none
ls -la /tmp/uboot2020.bin
echo "check markers in extracted blob:"
dd if=/tmp/uboot2020.bin bs=512 count=32000 2>/dev/null | strings | grep -m1 'U-Boot 20'

echo "### build patched image"
rm -f $OUT
cp --reflink=auto $BASE $OUT
dd if=/tmp/uboot2020.bin of=$OUT bs=512 seek=64 conv=notrunc status=none
echo "verify patched u-boot:"
dd if=$OUT bs=512 skip=16384 count=3000 2>/dev/null | strings | grep -m1 'U-Boot 20'
echo "verify partition table untouched (MBR sig + part offsets):"
fdisk -l $OUT 2>/dev/null | grep -E 'Disk |sdb1|sdb2|Device|sda1' | head -6
echo "### repack"
rm -f $OUT.xz
xz -T0 -9k $OUT
sha256sum $OUT.xz
ls -la $OUT.xz
echo TRANSPLANT_DONE
