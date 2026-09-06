# R4S OPNsense 26.7.3 修复版（Fixed Build）说明

> 基线：matheusber/opnsense 发布的 `OPNsense-26.7.3-arm-aarch64-R4S.img`（SHA256 已验证与原版一致）。
> 在 FreeBSD 15.1 VM 内对镜像做外科修复后重打包，**未改动内核/应用版本，可放心与原版等价回退**。

## ⭐ 终版结论（2026-09-06 真机验证）

本机实测：**仅换驱动不够**——这台 R4S 属"PCIe 链路训练失败型"（dmesg `Gen1 link training timeouted`，
RTL8111H 不上总线）。对 22.7 与 26.7.3 镜像逐项对比后锁定根因 = **u-boot 版本回归**：

| 镜像 | u-boot | 26.7 内核训练结果 |
|---|---|---|
| 22.7（personalbsd 20220825，GPT） | **2020.07** | 成功（双口正常） |
| 26.7.3（matheusber，MBR） | 2025.10 | **超时失败**（re0 消失） |
| 26.7.3 + 换 u-boot 2020.07 | 2020.07 | ✅ 成功（re0 出现，实测） |

（两版内核均含 Rockchip PCIe 控制器驱动 → "FreeBSD 引入驱动导致回归"假说被证伪；差异纯在 u-boot 对
RK3399 PCIe PHY/时钟的初始化。移植法：两镜像分区均始于 16MiB，直接互换原始扇区 64–32767 即可，
不动分区表与文件系统。）

**推荐烧录镜像 = v2（含 u-boot 2020.07），见下方"文件与校验"。v1（仅驱动内建）对这台板无效。**

## 为什么要做修复版

部分 R4S（非 R4SE）在 26.1/26.7.x 上出现"只识别到一个网口"：RK3399 原生 GMAC（`dwc0`）正常，
PCIe 口的 RTL8111H（`re0`）不出现（[matheusber issue #5](https://github.com/matheusber/opnsense/issues/5)）。
社区实证过的有效手段是换用 Realtek 官方驱动 **realtek-re-kmod198（v1.98）**替代 FreeBSD 自带 if_re。
原版 R4S 镜像没带该驱动（官方 R4S.conf 无 PRODUCT_ADDITIONS，只有 R5S/OP5P 有），本修复版把它内建进去。

## 内建修复清单（与原版镜像的差异）

| 位置 | 改动 | 证据 |
|---|---|---|
| `/boot/modules/if_re.ko` | 原为空 → 写入 vendor 驱动 561,096B（1.98.00，kmod 构建标签 1501000=FreeBSD 15.1.0，与 26.7.3 内核同源） | strings: "Realtek PCIe GbE Family Controller" / "1.98.00" |
| `/boot/kernel/if_re.ko` | FreeBSD base 驱动(71,560B) → 备份为 `if_re.ko.base`，原位换成 vendor 驱动 | ls -la |
| `/boot/loader.conf.local` | 新增 `if_re_load="YES"` + `if_re_name="/boot/modules/if_re.ko"`（开机预载 vendor 驱动） | 文本 |
| `/etc/rc` | 与 opnsense/core master 同步（差异 340 行，发布者自述的 caveat），原文件备份为 `/etc/rc.orig-26.7.3` | diff 计数 |
| `/root/niccheck.sh` | 首启一键双网口自检脚本 | 文件 |
| `/root/README-REPAIR.txt` | 本说明精简版 + 回退方法 | 文件 |
| `/root/if_re-vendor-1.98.ko` | vendor 驱动备份一份在系统内，方便手工 kldload | 文件 |

## 验证记录（2026-09-03，可回放终端输出）

**✅ 已在本环境机器级验证：**
- 原版 26.7.3 镜像 `.xz` SHA256 = `bcbc58c4…`（与发布值一致）
- 修复版 `.xz` SHA256 = `1f960fef…`；本地解压后 raw SHA256 = `fe15243cac1d8b78099f9185691dcc97f654a70705cb325cf46b2cb8978bda84`，与远端 patched raw 一致 → 压缩/传输字节无损
- patched 镜像 UFS 分区 `fsck_ufs -n` 无任何错误（76958 files, 0.0% fragmentation）
- 结构核对（镜像内只读挂载）：`/boot/loader.conf.local` 预载两行在位；`/boot/modules/if_re.ko` 与 `/boot/kernel/if_re.ko` 均为 vendor 561,096B；`/boot/kernel/if_re.ko.base`（71560B 原版）留档；`/etc/rc` 已替换且 `sh -n` 语法通过、原文件 `/etc/rc.orig-26.7.3` 留档；`/root/niccheck.sh`、`README-REPAIR.txt` 在位
- vendor 驱动来源：同批次 26.7.3 OP5P 镜像（kmod 构建标签 1501000 = FreeBSD 15.1.0，与 R4S 内核同源），strings 确认 "Realtek PCIe GbE Family Controller / 1.98.00"

**⚠️ 本环境无法验证、需你的真机确认：**
- aarch64 镜像的实际引导（本机只有 x86 VM，无法起 arm64）
- re0 是否在你的具体 R4S 上出现——驱动级病因已覆盖；若属 PCIe 枚举级（上游 issue #5 未定案部分），可能仍无效，请按下方"如果 re0 仍然不出现"采集日志回传

## 文件与校验

**v2（推荐，双网口修复版，含 u-boot 2020.07）：**
- 文件：`OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz`（1,315,668,508 B ≈ 1.23 GB，v2.1：在 v2 基础上改烘焙原生 iflib if_re、移除 vendor 预载）
- SHA256：`2663f1068716f2abe15ac13d2fe45dffce8a27ffc75f345064f544aa360644e1`
- 内容 = v1 全部修复 + u-boot 区替换为 22.7 的 U-Boot 2020.07（扇区 64–32767）；分区表/文件系统未动
- 真机验证（2026-09-06）：re0 UP（1000baseT FD）、vendor 驱动 1.98.00 生效、无 Gen1 训练超时、系统正常引导

**v1（仅驱动内建；对"枚举型"故障无效，留档）：**
- 文件：`OPNsense-26.7.3-fixed-R4S.img.xz`（1,315,759,140 B）
- SHA256：`1f960fef65ea874440d4e80a735d29597548fff8f5432b7d5e5d8c247e7ebe23`

## 烧录（与官方镜像完全一致）

1. 校验 SHA256。
2. 解压：`unxz OPNsense-26.7.3-fixed-R4S.img.xz`（Windows 用 7-Zip）。
3. 写 ≥8GB TF 卡（balenaEtcher / Rufus / win32diskimager；Linux: `dd if=... of=/dev/sdX bs=1m conv=sync`）。
4. 插入 R4S，5V/3A 上电；网线接 LAN 口访问 `https://192.168.1.1`（root/opnsense，向导会要求改密）。

## 首启验证（关键）

```sh
/root/niccheck.sh
```

期望输出里同时出现 **`re0`（PCIe RTL8111H）** 和 **`dwc0`（原生 GMAC）** 两个物理接口。
确认后即可按需分配 WAN/LAN；也可在 GUI 用 `ifconfig`/控制台 assignment 核对物理口对应关系。

## 如果 re0 仍然不出现

说明你的板子属于 PCIe 枚举层面问题（部分批次 R4S 在 FreeBSD/u-boot 下链路不训练，
driver 换装无法覆盖；上游 issue #5 仍在排查）。请收集并回传：

```sh
dmesg | grep -iE 'pci|re0|dwc0|realtek'
pciconf -lv
kldstat
```

配套处理选项：换 FreeBSD ports 更新版 u-boot-nanopi-r4s 覆写到 SD 保留区（seek 64 / 16384），
或换 R4SE/另一块 R4S 验证是否为板级差异。

## 回退到原版驱动（如不需要 vendor 驱动）

```sh
cp /boot/kernel/if_re.ko.base /boot/kernel/if_re.ko
rm /boot/modules/if_re.ko
# 注释掉 /boot/loader.conf.local 中 if_re_load / if_re_name 两行
reboot
```

## 镜像再打包方法（可复现）

在 FreeBSD 15.1 环境把原版 R4S 镜像与任一含 vendor 驱动的 26.7.3 OP5P/R5S 镜像挂为磁盘，
按上面"内建修复清单"执行即可；本修复全程未做源码级编译。
