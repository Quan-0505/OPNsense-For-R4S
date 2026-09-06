#!/bin/bash
# m0: stop the FreeBSD build VM cleanly + report state (non-destructive)
echo "--- stop qemu vm ---"
tmux kill-session -t fbsd 2>/dev/null
for i in 1 2 3 4 5; do
  pid=$(pgrep -x qemu-system-x86_64 | head -1)
  [ -z "$pid" ] && break
  kill "$pid" 2>/dev/null
  sleep 1
done
echo "qemu processes left: $(pgrep -cx qemu-system-x86_64 2>/dev/null || echo 0)"
echo "--- disk state ---"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo "--- /build usage ---"
du -sh /build
echo "--- root usage ---"
df -h / | tail -1
echo "M0 DONE"
