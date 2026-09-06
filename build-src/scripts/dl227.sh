#!/bin/bash
cd /build/images || exit 1
for name in OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825 OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4SE-20220825; do
  echo "### $name"
  for i in $(seq 1 10); do
    curl -sS -L -C - -o "$name.img.xz" "https://personalbsd.org/images/OPNsense/$name.img.xz" && break
    echo "retry $i"; sleep 2
  done
done
ls -la OPNsense-22.7*.img.xz
echo "--- validate ---"
xz -t OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825.img.xz && echo R4S_XZ_OK
xz -t OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4SE-20220825.img.xz && echo R4SE_XZ_OK
