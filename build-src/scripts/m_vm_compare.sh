#!/bin/bash
# compare22: prepare images, boot dissect VM with BOTH images attached, run inside-compare
set -u
log(){ echo "### $*"; }
cd /build/fbsd

log "ensure 22.7 R4S xz downloaded, decompress both images"
for i in $(seq 1 300); do
  [ -s /build/images/OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825.img.xz ] && break; sleep 2
done
[ -f /build/images/opnsense227-r4s.img ] || xz -dk /build/images/OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825.img.xz -c > /build/images/opnsense227-r4s.img
[ -f /build/images/opnsense2673-fixed.img ] || xz -dk /build/images/OPNsense-26.7.3-fixed-R4S.img.xz -c > /build/images/opnsense2673-fixed.img
ls -la /build/images/opnsense227-r4s.img /build/images/opnsense2673-fixed.img

log "stop old qemu, boot VM with both images (ro)"
pkill -x qemu-system-x86_64 2>/dev/null; sleep 2
tmux kill-session -t fbsd 2>/dev/null
tmux new-session -d -s fbsd \
  'qemu-system-x86_64 -enable-kvm -m 2048 -smp 4 \
   -drive file=/build/fbsd/disk.raw,if=virtio,format=raw \
   -drive file=/build/fbsd/seed.iso,media=cdrom,format=raw \
   -drive file=/build/images/opnsense227-r4s.img,if=virtio,format=raw,readonly=on \
   -drive file=/build/images/opnsense2673-fixed.img,if=virtio,format=raw,readonly=on \
   -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
   -device virtio-net-pci,netdev=n0 \
   -display none -serial mon:stdio -monitor none'

log "wait ssh"
for i in $(seq 1 240); do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 \
     -i vmkey -p 2222 freebsd@127.0.0.1 'uname -r' > /dev/null 2>&1; then echo "ssh ok"; break; fi
  sleep 3
done

log "upload + run inside-compare"
scp -i vmkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2222 \
  /root/compare_insides.sh freebsd@127.0.0.1:/home/freebsd/ >/dev/null 2>&1
ssh -i vmkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 \
  freebsd@127.0.0.1 'sudo sh /home/freebsd/compare_insides.sh' 2>&1 | tee /build/compare-result.txt | tail -150
echo "COMPARE_DONE"
