#!/bin/bash
# run22b: decompress 22.7, boot VM with both images, run compare22b
set -u
cd /build/fbsd
[ -f /build/images/opnsense227-r4s.img ] || xz -dk /build/images/OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825.img.xz -c > /build/images/opnsense227-r4s.img
ls -la /build/images/opnsense227-r4s.img /build/images/opnsense2673-fixed.img 2>&1

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

for i in $(seq 1 240); do
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 -i vmkey -p 2222 freebsd@127.0.0.1 'uname -r' >/dev/null 2>&1 && { echo "ssh ok"; break; }
  sleep 3
done
scp -i vmkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2222 /root/compare22b.sh freebsd@127.0.0.1:/home/freebsd/ >/dev/null 2>&1
ssh -i vmkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 freebsd@127.0.0.1 'sudo sh /home/freebsd/compare22b.sh' 2>&1 | tee /build/compare22b-result.txt | tail -110
echo RUN22B_DONE
