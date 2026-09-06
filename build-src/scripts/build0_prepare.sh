#!/bin/bash
# Step 0: prepare build host — apt tools, format+mount 50G disk, download sources
set -u
log() { echo "### $*"; date; }

log "apt install"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq qemu-system-x86 qemu-utils cloud-image-utils genisoimage sshpass tmux 2>&1 | tail -3
echo "qemu: $(qemu-system-x86_64 --version | head -1)"

log "lsblk before format"
lsblk /dev/sdb

log "mkfs /dev/sdb (50G new disk)"
mkfs.ext4 -F -L build /dev/sdb

log "mount /build + fstab"
mkdir -p /build
mount /dev/sdb /build
if ! grep -q '/build' /etc/fstab; then
  uuid=$(blkid -s UUID -o value /dev/sdb)
  echo "UUID=$uuid /build ext4 defaults 0 2" >> /etc/fstab
fi
df -h /build

log "downloads"
mkdir -p /build/dl
cd /build/dl
echo "  fbsd vm raw..."
curl -sSL -o fbsd.raw.xz https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-ufs.raw.xz && echo ok-fbsd
echo "  aux-26.7.3-aarch64..."
curl -sSL -o aux-26.7.3-aarch64.tar https://github.com/matheusber/opnsense/releases/download/26.7.3/aux-26.7.3-aarch64.tar && echo ok-aux
echo "  r4s img 26.7.3..."
curl -sSL -o OPNsense-26.7.3-arm-aarch64-R4S.img.xz https://github.com/matheusber/opnsense/releases/download/26.7.3/OPNsense-26.7.3-arm-aarch64-R4S.img.xz && echo ok-img
echo "  matheusber repo zip..."
curl -sSL -o matheusber-opnsense.zip https://github.com/matheusber/opnsense/archive/refs/heads/main.zip && echo ok-repo
ls -la /build/dl
log "step0 DONE"
