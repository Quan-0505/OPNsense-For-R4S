#!/bin/bash
cd /build/images || exit 1
rm -f OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825.img.xz OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4SE-20220825.img.xz
for name in OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4S-20220825 OPNsense-22.7-OpenSSL-aarch64-NanoPi-R4SE-20220825; do
  echo "### fresh download $name"
  for i in $(seq 1 6); do
    curl -sS -L --retry 3 -o "$name.img.xz" "https://personalbsd.org/images/OPNsense/$name.img.xz" && break
    echo "retry $i"; sleep 3
  done
  sz=$(stat -c%s "$name.img.xz")
  echo "size: $sz"
  xz -t "$name.img.xz" && echo "XZ_OK $name" || echo "XZ_FAIL $name"
done
