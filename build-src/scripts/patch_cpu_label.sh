#!/bin/sh
# Patch dashboard CPU label: show 'Rockchip RK3399' instead of raw hw.model (Cortex-A53)
F=/usr/local/opnsense/mvc/app/controllers/OPNsense/Diagnostics/Api/CpuUsageController.php
cp -p "$F" "$F.bak-rk3399"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = """        $sysctls = json_decode((new Backend())->configdRun('system sysctl values hw.model,kern.smp.cpus,kern.smp.cores'), true);

        return [sprintf(
            gettext('%s (%s cores, %s threads)'),
            $sysctls['hw.model'],
            $sysctls['kern.smp.cores'],
            $sysctls['kern.smp.cpus']
        )];"""
new = """        $sysctls = json_decode((new Backend())->configdRun('system sysctl values hw.model,kern.smp.cpus,kern.smp.cores'), true);
        $cpu_model = $sysctls['hw.model'];
        /* cosmetic label: NanoPi R4S (RK3399) shows 'ARM Cortex-A53 r0p4' from hw.model */
        if (str_contains($cpu_model, 'Cortex')) {
            $cpu_model = 'Rockchip RK3399';
        }

        return [sprintf(
            gettext('%s (%s cores, %s threads)'),
            $cpu_model,
            $sysctls['kern.smp.cores'],
            $sysctls['kern.smp.cpus']
        )];"""
if old not in s:
    print("OLD BLOCK NOT FOUND - no change")
    sys.exit(2)
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print("patched")
PY
echo "--- php lint ---"
php -l "$F"
echo "--- patched snippet ---"
sed -n '38,58p' "$F"
echo CPU_LABEL_PATCH_DONE
