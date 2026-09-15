<div align="center">

# OPNsense for NanoPi R4S

<p><strong>A field record of the fixes and tuning that make OPNsense 26.7.3 run reliably on the NanoPi R4S</strong></p>

<p>
  <a href="https://github.com/Quan-0505/OPNsense-For-R4S/releases"><img src="https://img.shields.io/github/v/release/Quan-0505/OPNsense-For-R4S?style=for-the-badge" alt="Release" /></a>
  <a href="#quick-start">Quick Start</a> |
  <a href="#problems-solved">Problems Solved</a> |
  <a href="#performance-and-limits">Performance and Limits</a> |
  <a href="#repository-layout">Repository Layout</a> |
  <a href="#disclaimer">Disclaimer</a>
</p>

</div>

**English** &nbsp;|&nbsp; **[简体中文](./README.md)**

---

## Quick Start

The finished firmware (with the u-boot 2020.07 fix included) has been published to GitHub Releases:

```text
下载：https://github.com/Quan-0505/OPNsense-For-R4S/releases
文件：OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz
SHA256：2663f1068716f2abe15ac13d2fe45dffce8a27ffc75f345064f544aa360644e1
```

```bash
# 校验并解压（Windows 用 7-Zip）
sha256sum OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz
unxz OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz

# 写入 ≥8GB TF 卡（balenaEtcher / Rufus；或 Linux:）
dd if=OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img of=/dev/sdX bs=1m conv=sync
```

After boot, the default is `https://192.168.1.1` (root / opnsense; change the password in the wizard). For the complete
deployment and verification procedure, see
[`build-src/OPNsense-26.7-R4S-deploy-guide.md`](build-src/OPNsense-26.7-R4S-deploy-guide.md).

> Common personalization: after logging in, it is recommended to enable **System → Settings → Power** (powerd) and to
> pin a fixed MAC to both NIC ports (the standard R4S has no EEPROM, so the MAC address changes). See the tuning
> sections below for details.

---

## Problems Solved

| Symptom | Root Cause | Fix | Section |
|---|---|---|---|
| Only one NIC on 26.7.x (RTL8111H disappears) | **u-boot version regression** (2025.10 PCIe link training times out, while 2020.07 is fine) | Image switched to u-boot 2020.07 (the v2 firmware in this repo) | [Dual-NIC Detection](#dual-nic-detection-bug) |
| Intermittent NIC stalls, unstable web UI | Vendor Realtek 1.98 driver drops the link while idle | Reverted to the native FreeBSD iflib `if_re` | [Link-Drop Bug](#link-drop-bug) |
| Speed test reaches only ~300 Mbps | CPU frequency locked at 600 MHz (powerd missing) | Enable `powerd` | [CPU Frequency Scaling](#cpu-frequency-scaling) |
| Throughput around ~500 Mbps | Interface hardware settings not applied correctly | Enable "Hardware Settings: Override Global Settings" in the GUI | [Interface Hardware Settings](#interface-hardware-settings) |

---

## Dual-NIC Detection Bug

**Symptom**: `dwc0` (the RK3399 native GMAC) works fine, but the PCIe port RTL8111H (`re0`) disappears; dmesg reports
`pcib0: Gen1 link training timeouted: 0x00080001`; under `pciconf` the device is not on the bus.
The same board works fine under Linux/OpenWrt, and it also worked fine back in the OPNsense 22.7 era.

**Root cause (confirmed by a controlled comparison experiment)**:

| Image | u-boot | Result |
|---|---|---|
| 22.7 (personalbsd 20220825) | **2020.07** | Both ports work |
| 26.7.3 (matheusber) | 2025.10 | re0 disappears |
| 26.7.3 + u-boot 2020.07 | 2020.07 | **re0 comes back** |

Both FreeBSD kernels **do include** the Rockchip PCIe driver — the "the driver introduced a regression" hypothesis is
disproved; the difference lies in the state in which u-boot initializes the RK3399 PCIe PHY/clocks. Corresponding
upstream reports: [same error on FreeBSD-arm in 2022](https://marc.info/?l=freebsd-arm&m=164487492409386&w=1),
[matheusber issue #5](https://github.com/matheusber/opnsense/issues/5).

**Fix artifact**: `OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz` (this repo's Releases; u-boot 2020.07 + the
native iflib if_re driver are already baked in, with no vendor module preloaded).
Porting recipe (both images' partitions start at 16 MiB, so swapping the raw sectors is enough):

```bash
dd if=opnsense227-r4s.img of=uboot2020.bin bs=512 skip=64 count=$((32768-64))
dd if=uboot2020.bin of=26.7.3-fixed.img bs=512 seek=64 conv=notrunc
```

## Link-Drop Bug

The vendor Realtek `realtek-re-kmod198` (v1.98) **drops the link periodically even while idle** on FreeBSD 15.1
(dmesg is full of `link state changed`), and EEPROM reads fail, which makes the MAC address random. After reverting to
the native iflib `if_re`, there is zero jitter while idle, the MAC is stable, and native capabilities such as TSO are
available. A fallback backup is kept on the device at `/boot/kernel/if_re.ko.base` (the vendor backup is `.vendor198`).

**Lesson**: the real cure for the detection problem is u-boot 2020.07; the vendor driver was never necessary.

## CPU Frequency Scaling

OPNsense ARM images do not run `powerd` by default → the RK3399's six cores are locked at 600 MHz → pf+NAT throughput
is bottlenecked by the CPU.

```bash
sysrc powerd_enable=YES && service powerd start   # 持久化启用
sysrc powerd_flags="-a hadp"                      # 自适应（推荐）
sysrc powerd_flags="-a max"                       # 性能模式（实测与 hadp 同吞吐）
```

## Interface Hardware Settings

GUI: Interfaces → WAN/LAN → **Hardware Settings: Override Global Settings** (`hw_settings_overwrite=1`).
OPNsense then re-applies the driver parameters according to each interface's capabilities (reconfiguring manually with
`configctl` resets the unload parameters, so a proper save through the GUI is the right way). Once it takes effect,
`dwc0` has `RXCSUM,TXCSUM,VLAN_MTU,LINKSTATE,RXCSUM_IPV6,TXCSUM_IPV6`.

---

## Performance and Limits

**Current steady state: stable + ~800 Mbps (85% of line rate)**, with the configuration in [`build-src/FIXED-BUILD-26.7.3-R4S.md`](build-src/FIXED-BUILD-26.7.3-R4S.md).

- 800 Mbps is the driver ceiling of `if_dwc` (RK3399 GMAC) on FreeBSD 15.1: the 13.1-era driver was 43 KB and was
  slimmed down to 16 KB in 15.1, while the same hardware once reached 900 Mbps on 22.7
- Independent of CPU frequency (max mode measures the same 800) and of the NICs' roles (swap experiments land in the same range)
- RSS does not help: both re0 and dwc0 are **single-queue** (no hardware distribution); `soreceive_stream` is already enabled by default in 15.1

**Two ways past 800**:

1. **Use a USB3 gigabit NIC as WAN** (AX88179 / RTL8153, with offload, can approach line rate) — low cost and immediately achievable
2. **Backfill the 13.1 `if_dwc` driver into the kernel** (13.1 version 43 KB vs 15.1 version 16 KB) — fixes the root
   cause but requires cross-compiling the kernel + reflashing, a large amount of work

**Verified but gainless / inapplicable tunings**: `net.isr.*` (already 4 threads bound by default), TCP buffer
enlargement (the default 8 MB is enough; enlarging it causes more jitter instead, rolled back), `hw.ibrs_disable`
(Intel only), smaller MSS (slower instead), RSS (not supported on a single queue).

---

## Repository Layout

```text
OPNsense-For-R4S/
├── README.md                       本文件（问题/根因/修复/调优总览）
└── build-src/                      编译与验证资产
    ├── scripts/                    build0-3 编译流水线、m_uboot2020 移植、
    │                               compare* 回归解剖、dl227 下载、
    │                               inspect_img 镜像解析、patch_cpu_label 定制等
    ├── results/                    22.7 vs 26.7 对比实验原始输出
    ├── FIXED-BUILD-26.7.3-R4S.md   修复版构建清单与校验（v1/v2）
    └── OPNsense-26.7-R4S-deploy-guide.md  部署背景研究
```

The finished firmware (`OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz`, about 1.25 GB) exceeds Git's
100 MB single-file limit, so it is distributed through
[Releases](https://github.com/Quan-0505/OPNsense-For-R4S/releases) (the per-file limit for release assets is 2 GiB);
the whole process can be reproduced with the scripts under `build-src/`.

---

## Disclaimer

All images and scripts in this repository are **experimental work**, provided as-is with no warranty of any kind,
express or implied; flashing and configuring carry risk, so assess it yourself and keep a rollback image. The
trademarks involved (OPNsense, NanoPi, Rockchip, Realtek) belong to their respective owners.
