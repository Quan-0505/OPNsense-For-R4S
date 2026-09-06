#!/bin/bash
# Step 1 (run on the Debian host): decompress sources, build & boot FreeBSD 15.1 VM (KVM).
set -u
cd /build || exit 1
mkdir -p fbsd images dl
cd dl

echo "### ensure downloads complete"
for f in fbsd-cidata.raw.xz OPNsense-26.7.3-arm-aarch64-R4S.img.xz OPNsense-26.7.3-arm-aarch64-OP5P_MBR.img.xz aux-26.7.3-aarch64.tar matheusber-opnsense.zip; do
  if [ ! -s "$f" ]; then
    echo "missing $f - fetching"
    case $f in
      fbsd-cidata.raw.xz) url="https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-BASIC-CLOUDINIT-ufs.raw.xz" ;;
      OPNsense-26.7.3-arm-aarch64-R4S.img.xz) url="https://github.com/matheusber/opnsense/releases/download/26.7.3/OPNsense-26.7.3-arm-aarch64-R4S.img.xz" ;;
      OPNsense-26.7.3-arm-aarch64-OP5P_MBR.img.xz) url="https://github.com/matheusber/opnsense/releases/download/26.7.3/OPNsense-26.7.3-arm-aarch64-OP5P_MBR.img.xz" ;;
      aux-26.7.3-aarch64.tar) url="https://github.com/matheusber/opnsense/releases/download/26.7.3/aux-26.7.3-aarch64.tar" ;;
      matheusber-opnsense.zip) url="https://github.com/matheusber/opnsense/archive/refs/heads/main.zip" ;;
    esac
    curl -sSL -o "$f" "$url" || echo "FETCH FAIL $f"
  fi
done

echo "### decompress images"
[ ! -f /build/fbsd/disk.raw ] && xz -dk fbsd-cidata.raw.xz && mv fbsd-cidata.raw /build/fbsd/disk.raw
[ ! -f /build/images/r4s.img ] && xz -dk OPNsense-26.7.3-arm-aarch64-R4S.img.xz && mv OPNsense-26.7.3-arm-aarch64-R4S.img /build/images/r4s.img
[ ! -f /build/images/op5p.img ] && xz -dk OPNsense-26.7.3-arm-aarch64-OP5P_MBR.img.xz && mv OPNsense-26.7.3-arm-aarch64-OP5P_MBR.img /build/images/op5p.img

cd /build/fbsd
du -h disk.raw /build/images/r4s.img /build/images/op5p.img

echo "### ssh keypair"
if [ ! -f vmkey ]; then ssh-keygen -q -t ed25519 -N '' -f vmkey; fi

echo "### cloud-init seed (NoCloud, label cidata)"
rm -rf seed && mkdir -p seed/seedconfig
cat > seed/seedconfig/meta-data << EOF
instance-id: fbsd-build-01
local-hostname: fbsd-build
EOF
cat > seed/seedconfig/user-data << EOF
#cloud-config
ssh_pwauth: true
disable_root: false
users:
  - name: root
    lock_passwd: false
    ssh_authorized_keys:
      - $(cat vmkey.pub)
chpasswd:
  expire: false
  users:
    - name: root
      password: <replace-with-your-own>
runcmd:
  - [ sh, -c, "sysrc sshd_enable=YES; service sshd onestart" ]
EOF
if command -v cloud-localds >/dev/null 2>&1; then
  cloud-localds -v seed.iso seed/seedconfig/user-data seed/seedconfig/meta-data
else
  genisoimage -output seed.iso -volid cidata -joliet -rock seed/seedconfig
fi

echo "### boot VM (3 drives: system / r4s-rw / op5p-ro)"
if [ -f vm.pid ]; then kill "$(cat vm.pid)" 2>/dev/null; sleep 2; fi
qemu-system-x86_64 -enable-kvm -m 2048 -smp 4 \
  -name fbsd-build \
  -drive file=/build/fbsd/disk.raw,if=virtio,format=raw \
  -drive file=/build/fbsd/seed.iso,media=cdrom,format=raw \
  -drive file=/build/images/r4s.img,if=virtio,format=raw \
  -drive file=/build/images/op5p.img,if=virtio,format=raw,readonly=on \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=n0 \
  -daemonize -pidfile /build/fbsd/vm.pid -display none \
  -serial file:/build/fbsd/console.log
echo "vm pid: $(cat /build/fbsd/vm.pid 2>/dev/null)"

echo "### wait for ssh"
for i in $(seq 1 300); do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
     -i /build/fbsd/vmkey -p 2222 root@127.0.0.1 'uname -r' > /tmp/vmver 2>/dev/null; then
    echo "VM ssh OK: $(cat /tmp/vmver)"; break
  fi
  sleep 2
done
tail -8 /build/fbsd/console.log
echo "STEP1 DONE"

