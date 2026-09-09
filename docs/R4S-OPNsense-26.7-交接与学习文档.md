# NanoPi R4S × OPNsense 26.7 — 交接与学习文档

> 用途：给接手同事快速建立全貌、复现关键结论、继续下一步工作。
> 覆盖：双网口识别 bug、网卡断流、吞吐调优、13.1 驱动内核移植、构建/验证工具链、遗留任务。
> 文档配套公开仓库：https://github.com/Quan-0505/OPNsense-For-R4S（README + build-src + Releases）

---

## 1. 项目背景与目标

在 **NanoPi R4S**（RK3399，双千兆：原生 GMAC `dwc0` / PCIe RTL8111H `re0`）上部署 **OPNsense 26.7.3**（FreeBSD 15.1 系, arm64），目标是：

1. 双网口都能用（原厂镜像只有 1 个口）
2. 稳定不掉线
3. 吞吐尽量逼近老版 22.7（FreeBSD 13.1 时代）实测的 ~900 Mbps

**当前状态（2026-09）**：
- 稳定配置：LAN=re0 / WAN=dwc0，原生驱动，~800 Mbps（约 85% 线速）
- 13.1 if_dwc 驱动已完成内核移植并产出测试固件（是否破 800 待实测，见 §7）

---

## 2. 硬件与系统速览

| 项 | 值 |
|---|---|
| SoC | Rockchip RK3399（A72×2 + A53×4） |
| 网口 A | 原生 GMAC（RTL8211E PHY）→ FreeBSD `dwc0` |
| 网口 B | PCIe RTL8111H → FreeBSD `re0`（**两个网口物理身份不同，接线/测试务必区分**） |
| 系统 | OPNsense 26.7.3（FreeBSD 15.1-RELEASE-p3, arm64） |
| 网络 | WAN=dwc0 接上级路由（DHCP）；LAN=re0 192.168.2.1/24 |
| 控制通道 | SSH 为主（GUI 新 SPA 在 headless 浏览器易崩）；板无视频输出，串口才是带外通道 |

**关键认知：两个网口物理不同**
- 机壳标 WAN/靠电源侧口 = dwc0（原生 GMAC，无 TSO、单队列）
- 机壳标 LAN 口 = re0（PCIe RTL8111H，iflib，原生支持 TSO）
- 一切测试/复现先确认物理口 ↔ 接口名对应关系。

---

## 3. 三大问题与根因（最重要的一节）

### 3.1 双网口识别（re0 消失）—— u-boot 回归，不是驱动

**现象**：26.7.x 只出现 dwc0；dmesg：`pcib0: Gen1 link training timeouted`；PCIe 上无 RTL8111H。

**根因（对比实验实锤）**：差异在 **u-boot 版本**，不在 FreeBSD 内核：

| 镜像 | u-boot | FreeBSD | 结果 |
|---|---|---|---|
| 22.7 (personalbsd) | 2020.07 | 13.1 | 双口正常（900 Mbps） |
| 26.7.3 (matheusber) | 2025.10 | 15.1 | re0 消失 |
| 26.7.3 + u-boot 2020.07 | 2020.07 | 15.1 | re0 恢复 ✅ |

- 13.1 与 15.1 内核**都含** Rockchip PCIe 驱动 → "驱动引入回归"假说证伪。
- 上游线索：FreeBSD-arm 2022 年同报错（无解）；matheusber/opnsense issue #5。

**修复**：把镜像 u-boot 区（两个镜像分区均始于 16 MiB，互换扇区 64–32767 即可）换成 **U-Boot 2020.07**。配方见 §6 / 仓库 `build-src/scripts/m_uboot2020.sh`。

**衍生教训**：当年为了修 re0 识别还内建过 vendor Realtek 驱动——事后证明**完全非必要**，还引入了 §3.2 的断流问题。

### 3.2 网卡断流 —— vendor Realtek 驱动 vs 原生驱动

**现象**：高负载甚至空闲时网口反复 DOWN/UP、web 间歇不可达；dmesg 大量 `link state changed`。

**根因 1（已修复）**：vendor `realtek-re-kmod198`（v1.98）在 FreeBSD 15.1 上**空闲也周期性掉链**，且读 EEPROM 失败导致 MAC 随机。换回 FreeBSD 原生 iflib `if_re` 后：零抖动、MAC 稳定、获得 TSO 等原生能力。
- 备份策略：`/boot/kernel/if_re.ko.base`（原生）、`if_re.ko.vendor198`（vendor）。

**根因 2（环境特性，勿误判为 bug）**：LAN 口偶发掉线若与 **PC 睡眠/唤醒时刻**精确同步（dmesg 时间戳对照），是 PC 网卡电源管理在睡眠后重协商所致，非固件问题。处置：PC 网卡电源管理/EEE 关闭即可；活跃使用中掉线才继续查线缆/协商。

### 3.3 吞吐 ~300 Mbps —— CPU 锁频（缺 powerd）

**现象**：NAT 只有 ~300Mbps。
**根因**：OPNsense ARM 镜像默认**没跑 powerd** → RK3399 全核锁 600 MHz。
**修复（已持久化）**：
```sh
sysrc powerd_enable=YES && service powerd start
sysrc powerd_flags="-a hadp"   # 自适应，推荐日常
# sysrc powerd_flags="-a max"  # 性能模式；实测与 hadp 同吞吐，无必要
```

---

## 4. 吞吐上限分析与调优终态

### 4.1 从 500 到 800：接口硬件覆盖

**关键操作（GUI 正规路径）**：Interfaces → WAN/LAN → **"硬件设置：覆盖全局设置"**（`hw_settings_overwrite=1`）。
- 手动 `configctl interface reconfigure` 会重置卸载参数；**GUI 保存才是正路**。
- 生效后 dwc0：`RXCSUM,TXCSUM,VLAN_MTU,LINKSTATE,RXCSUM_IPV6,TXCSUM_IPV6`。

### 4.2 ~800 = 平台驱动天花板（当前判断）

证据链（均已实测）：
- CPU 频率不敏感：powerd max（A72@1800MHz）下仍 800；
- 网卡角色不敏感：WAN/LAN 互换实验同区间；
- **22.7（13.1 内核）同物理口跑 900** → 回归在 FreeBSD 驱动/协议栈层。
- 指向：`if_dwc`（RK3399 GMAC 驱动）在 **13.1→15.1 之间被大幅重写精简**：
  - 13.1：单体 43 KB（含 DMA 收发的完整实现）
  - 15.1：核心 16 KB + 独立 DMA（dwc1000_*）+ 各 SoC 前端（rk/aw/socfpga…）
- RSS 无效（两张卡都单队列）；`soreceive_stream` 15.1 默认已开。

### 4.3 终端稳定配置（复现用）

```text
LAN = re0   192.168.2.1/24（固定 MAC；标准版 R4S 无 EEPROM，MAC 会变）
WAN = dwc0  DHCP（上级路由）
re0 驱动   = FreeBSD 原生 iflib if_re（非 vendor）
powerd     = 开启，-a hadp
接口       = LAN/WAN 均开"覆盖全局设置"
dwc 卸载   = RX/TX CSUM + IPv6 变体已开（68000b）
```

---

## 5. 固件产物与校验（Release 全记录）

| 文件 | 说明 | SHA256 |
|---|---|---|
| `OPNsense-26.7.3-fixed-uboot2020-native-driver-R4S.img.xz` | **v2.1 当前稳定发布**：u-boot2020 + 原生 if_re（无 vendor 预载），刷入即稳定态 | `2663f1068716f2abe15ac13d2fe45dffce8a27ffc75f345064f544aa360644e1` |
| `OPNsense-26.7.3-dwc13-stable267-R4S.img.xz` | **13.1 if_dwc 内核移植实验固件**（stable/26.7 内核） | `ac4f5bcf431779ffbcf371d3229df1cec45d4e32cb96327cd01b3fb6249dc153`（内核 `c3d70a90…`） |
| v2（历史） | u-boot2020 + vendor 驱动烘焙（会断流，已下线） | `ab724fcc…` |

> 产物因 >100 MB 走 GitHub **Releases**（≤2 GB/文件）。旧版本地存档在 `build\`。

---

## 6. 构建与验证工具链（给"继续工作"的人）

### 6.1 环境

- 构建主机（Debian）上跑 **FreeBSD VM（qemu/KVM）** 做镜像手术与内核编译；VM 资产在 5.44 的 `/build/fbsd/`（disk.raw + vmkey + seed）。
- 手术原理：镜像用 **UFS**，Linux 不能 rw 挂载 → 在 FreeBSD VM 里 `mount /dev/vtbdXs2a` 操作。
- 仓库 `build-src/`：build0~3 流水线、`m_uboot2020.sh`（u-boot 移植）、compare*/dl227/scan_pb（回归解剖）、inspect_img、patch_cpu_label（首页 CPU 型号定制）。

### 6.2 ⚠️ 血泪教训（务必遵守）

1. **VM 磁盘上的构建产物不可跨会话信任**：非干净关机（直接 pkill qemu）后 UFS 可能丢数据，fsck 也不一定找回 → **单次常驻 VM 内完成"抓源→补丁→编译→换核"，结束时先 poweroff 再杀进程**。
2. **中断过的 obj 会产生损坏 .o**（如 `al_eth.o: section header table goes past the end`）→ 不要逐个删，`rm -rf` 该 GENERIC obj 目录后全量重编（本项目 ~15 分钟）。
3. csh 不认 `2>&1`/`2>/dev/null`（要 `>&`）；ssh 远程多步一律写脚本文件再跑，别拼内联。
4. 4GB 镜像 xz -9 重压约 20 分钟；下载校验 Content-Length/xz -t（22.7 镜像服务器易截断）。

### 6.3 13.1 if_dwc 移植要点（已在 stable/26.7 成功编译）

替换文件（13.1 单体四件套）：`sys/dev/dwc/{if_dwc.c,if_dwc.h,if_dwcvar.h,if_dwc_if.m}`。
配套改动：
1. 删 15.1 组件：`sys/conf/files` 里 dwc1000_*/if_dwc_aw/cvitek 行；`sys/conf/files.arm64` 里 rk/socfpga 行；`std.rockchip` 删 `device dwc_rk`、`std.altera` 删 `device dwc_socfpga`（保留 `device dwc`）。
2. 13.1 源码补丁（对应 15.1 API 漂移）：
   - 加 `#include <net/if_private.h>`（15.1 把 `struct ifnet` 定义挪到了这）
   - `IF_LLADDR(ifp)` → `(uint8_t *)if_getlladdr(ifp)`
   - `if_bpfmtap(ifp, m)` → `BPF_MTAP(ifp, m)`
   - `DRIVER_MODULE(...)` 改新 5 参签名：`DRIVER_MODULE(dwc, simplebus, dwc_driver, 0, 0);`（同 miibus）
   - 删死代码：dwc_rxfinish_locked 里未用的 `struct ifnet *ifp;` 声明与 `ifp = sc->ifp;`（编译报 "set but not used"），以及 `static devclass_t dwc_devclass;`
3. 编译：`make -j4 buildkernel TARGET=arm64 TARGET_ARCH=aarch64 KERNCONF=GENERIC WITH_KERNEL_SYMBOLS=NO`（源树 = opnsense/src stable/26.7 或 freebsd-src releng/15.1 均可）。

### 6.4 冒烟验证流程（每次出内核必做）

1. VM 挂载镜像 rw → 替换 `/boot/kernel/kernel` → 干净关机 → 重压 xz → sha 双端核对。
2. 只读回读验证（挂载 ro 检查 loader.conf.local / 内核文件大小与 sha）——防"换了没换上"。
3. 真机用**空闲 SD** 烧录测试：ifconfig 双口、dmesg、speedtest。

---

## 7. 下一步工作（按优先级）

1. **实测 13.1 内核固件**（§5 实验固件）：能否启动、dwc0 是否正常、测速是否 >800。
   - >800 → 发布正式 Release（更新 README/文档/sha）
   - ≤800 且稳定 → 接受 800 基线收工（结论：差异不在驱动本处）
   - 起不来/dwc0 缺失 → 回传 dmesg，迭代移植代码
2. **若追求"fork 即编译"**：以 maurice-w/opnsense-vm-images（opnsense/tools fork，含 AMD64VM/ARM64VM 设备与完整教程）为蓝本，把本次改动固化成**可参数化一键构建**（tools 的 `make update SETTINGS=26.7 ... DEVICE=...` 路线），并把移植补丁整理成正式 diff 入库。
3. **低成本备选路线**：USB3 千兆网卡当 WAN（带卸载，实测可近线速 ~930）——若内核提速失败且 800 不够用，这是性价比最高的替代。
4. **发布整理**：README 同步新固件 sha/文档；补 LICENSE；考虑英文版。
5. 长期：跟进 FreeBSD 上游 if_dwc 演进（dwc1000 系列），确认重写是否修复 13.1 时代的问题、或上游是否接受此移植。

---

## 8. 速查命令

```sh
# 设备（R4S root 登录后）
sysctl dev.cpu.4.freq_levels        # 看 A72 频率档
ps aux | grep powerd                 # powerd 运行与参数
ifconfig dwc0 re0                    # options=... 里看卸载是否开
configctl interface reconfigure lan  # 仅重建接口（注意会重置部分参数，回 GUI 再保存）
dmesg | grep -E 'link state changed'# 掉线时间线（对 PC 唤醒时刻）

# 构建机
# 单会话原则：boot VM → fetch/src → patch → build → swap → poweroff → 再动 qemu
sha256sum 镜像.xz                   # 发布前双端核对
```

---

*实验性成果，按原样提供；刷机有风险，保留可回退镜像。* 详尽的构建流水线脚本与原始对比证据见仓库 `build-src/`。
