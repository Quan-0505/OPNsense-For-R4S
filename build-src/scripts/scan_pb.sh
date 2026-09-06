#!/bin/bash
# scan personalbsd subpages for R4S / OPNsense / image links
for p in 1026 900 727 313 2; do
  echo "===== page_id=$p ====="
  for url in "https://personalbsd.org/?page_id=$p" "https://personalbsd.org/?p=$p"; do
    body=$(curl -sL --max-time 25 -A 'Mozilla/5.0' "$url")
    [ -z "$body" ] && continue
    echo "$body" | iconv -f utf-16 -t utf-8 2>/dev/null | grep -oiE 'href="[^"]+"' | grep -iE 'r4s|opnsense|img\.xz|aarch64|22\.|21\.|20\.' | sort -u | head -40
  done
done
echo SCAN_DONE
