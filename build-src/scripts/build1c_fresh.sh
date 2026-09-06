#!/bin/bash
# Step 1c: fresh VM disk + nuageinit seed with a freebsd user; wait for ssh; verify root via sudo.
set -u
cd /build/fbsd
PID=$(cat vm.pid 2>/dev/null); [ -n "$PID" ] && kill "$PID" 2>/dev/null
sleep 2
tmux kill-session -t fbsd 2>/dev/null

echo "### fresh disk.raw"
rm -f disk.raw
xz -dk /build/dl/fbsd-cidata.raw.xz && mv /build/dl/fbsd-cidata.raw disk.raw
du -h disk.raw

echo "### ssh keypair"
[ -f vmkey ] || ssh-keygen -q -t ed25519 -N '' -f vmkey
PUB=$(cat vmkey.pub)

echo "### nuageinit seed (user freebsd)"
rm -rf seed && mkdir -p seed/seedconfig
cat > seed/seedconfig/meta-data << EOF
instance-id: fbsd-build-01
local-hostname: fbsd-build
EOF
cat > seed/seedconfig/user-data << EOF
#cloud-config
hostname: fbsd-build
fqdn: fbsd-build.local
ssh_pwauth: true
users:
  - name: freebsd
    shell: /bin/sh
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    ssh_authorized_keys:
      - $PUB
write_files:
  - path: /root/.ssh/authorized_keys
    permissions: '0600'
    content: |
      $PUB
  - path: /etc/rc.conf.d/sshd
    permissions: '0644'
    content: |
      sshd_enable="YES"
packages:
  - sudo
runcmd:
  - service sshd enable
  - service sshd start
EOF
rm -f seed.iso
if command -v cloud-localds >/dev/null 2>&1; then
  cloud-localds -v seed.iso seed/seedconfig/user-data seed/seedconfig/meta-data
else
  genisoimage -output seed.iso -volid cidata -joliet -rock seed/seedconfig
fi

echo "### boot VM"
tmux new-session -d -s fbsd \
  'qemu-system-x86_64 -enable-kvm -m 2048 -smp 4 \
   -drive file=/build/fbsd/disk.raw,if=virtio,format=raw \
   -drive file=/build/fbsd/seed.iso,media=cdrom,format=raw \
   -drive file=/build/images/r4s.img,if=virtio,format=raw \
   -drive file=/build/images/op5p.img,if=virtio,format=raw,readonly=on \
   -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
   -device virtio-net-pci,netdev=n0 \
   -display none -serial mon:stdio -monitor none'

echo "### wait for ssh (freebsd)"
for i in $(seq 1 240); do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 \
     -i /build/fbsd/vmkey -p 2222 freebsd@127.0.0.1 'echo VMSSH_OK' 2>/dev/null | grep -q VMSSH_OK; then
    echo "ssh OK after $((i*3))s"; break
  fi
  sleep 3
done

echo "### verify root via sudo"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
  -i /build/fbsd/vmkey -p 2222 freebsd@127.0.0.1 'echo SUDO_ROOT_OK | sudo -i sh -c "cat"' 2>&1 | grep -E 'SUDO_ROOT_OK|incorrect|denied' | head -3
echo "STEP1C DONE"
