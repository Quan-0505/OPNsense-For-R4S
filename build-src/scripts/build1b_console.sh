#!/bin/bash
# Step 1b: relaunch VM on an interactive console (tmux) and bootstrap root ssh key.
set -u
cd /build/fbsd
PID=$(cat vm.pid 2>/dev/null); [ -n "$PID" ] && kill "$PID" 2>/dev/null
sleep 2
tmux kill-session -t fbsd 2>/dev/null

echo "### boot qemu under tmux (console interactive)"
tmux new-session -d -s fbsd \
  'qemu-system-x86_64 -enable-kvm -m 2048 -smp 4 \
   -drive file=/build/fbsd/disk.raw,if=virtio,format=raw \
   -drive file=/build/fbsd/seed.iso,media=cdrom,format=raw \
   -drive file=/build/images/r4s.img,if=virtio,format=raw \
   -drive file=/build/images/op5p.img,if=virtio,format=raw,readonly=on \
   -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
   -device virtio-net-pci,netdev=n0 \
   -display none -serial mon:stdio -monitor none'
echo "vm restarted in tmux session 'fbsd'"

echo "### wait for login prompt"
FOUND=0
for i in $(seq 1 150); do
  if tmux capture-pane -t fbsd -p 2>/dev/null | grep -q 'login:'; then FOUND=1; break; fi
  sleep 1
done
echo "login prompt: $FOUND"
tmux capture-pane -t fbsd -p | tail -3

echo "### login as root"
tmux send-keys -t fbsd 'root' Enter
sleep 4
if tmux capture-pane -t fbsd -p | grep -q 'Password:'; then
  echo "(password prompt detected - sending empty)"
  tmux send-keys -t fbsd Enter
  sleep 3
fi
tmux capture-pane -t fbsd -p | tail -4

echo "### inject ssh key"
tmux send-keys -t fbsd "mkdir -p /root/.ssh && echo '$(cat vmkey.pub)' > /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && echo KEYSETUP_OK" Enter
sleep 4
tmux capture-pane -t fbsd -p | tail -4

echo "### verify ssh from host"
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 \
     -i /build/fbsd/vmkey -p 2222 root@127.0.0.1 'uname -srm; echo SSH_ROOT_OK' 2>/dev/null | grep -q SSH_ROOT_OK; then
    echo "VM SSH OK"; break
  fi
  sleep 2
done
echo "STEP1B DONE"
