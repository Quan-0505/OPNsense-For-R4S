<div align="center">

# OPNsense for NanoPi R4S

<p><strong>让 NanoPi R4S 稳定跑满 OPNsense 26.7.3 的实战修复与调优档案</strong></p>

<p>
  <a href="https://github.com/Quan-0505/OPNsense-For-R4S/releases"><img src="https://img.shields.io/github/v/release/Quan-0505/OPNsense-For-R4S?style=for-the-badge" alt="Release" /></a>
  <a href="#快速开始">快速开始</a> |
  <a href="#解决的问题">解决的问题</a> |
  <a href="#性能与边界">性能与边界</a> |
  <a href="#仓库结构">仓库结构</a> |
  <a href="#免责声明">免责声明</a>
</p>

</div>

---

## 快速开始

固件成品（含 u-boot 2020.07 修复）已发布到 GitHub Releases：

```text
下载：https://github.com/Quan-0505/OPNsense-For-R4S/releases
文件：OPNsense-26.7.3-fixed-uboot2020-R4S.img.xz
SHA256：ab724fcca797eb972403f5297bd03ec46574b874fa622d7308fdbe8f51a12b55
```

```bash
# 校验并解压（Windows 用 7-Zip）
sha256sum OPNsense-26.7.3-fixed-uboot2020-R4S.img.xz
unxz OPNsense-26.7.3-fixed-uboot2020-R4S.img.xz

# 写入 ≥8GB TF 卡（balenaEtcher / Rufus；或 Linux:）
dd if=OPNsense-26.7.3-fixed-uboot2020-R4S.img of=/dev/sdX bs=1m conv=sync
```

启动后默认 `https://192.168.1.1`（root / opnsense，向导中改密）。完整部署与验证流程见
[`build-src/OPNsense-26.7-R4S-deploy-guide.md`](build-src/OPNsense-26.7-R4S-deploy-guide.md)。

> 常见个性化：登录后建议开启 **System → Settings → Power**（powerd）并给两个网口固定 MAC
> （标准版 R4S 无 EEPROM，MAC 会变）。详见下文调优章节。

---

## 解决的问题

| 症状 | 根因 | 处置 | 章节 |
|---|---|---|---|
| 26.7.x 只有单网口（RTL8111H 消失） | **u-boot 版本回归**（2025.10 PCIe 训练超时 vs 2020.07 正常） | 镜像换用 u-boot 2020.07（本仓库 v2 固件） | [双网口识别](#双网口识别-bug) |
| 网口间歇断流、Web 不稳 | vendor Realtek 1.98 驱动空闲掉链 | 换回 FreeBSD 原生 iflib `if_re` | [断流 bug](#断流-bug) |
| 测速仅 ~300 Mbps | CPU 锁频 600 MHz（缺 powerd） | 启用 `powerd` | [CPU 调频](#cpu-调频) |
| 吞吐 ~500 Mbps | 接口硬件参数未正确应用 | GUI 开启"硬件设置：覆盖全局设置" | [接口硬件设置](#接口硬件设置) |

---

## 双网口识别 bug

**现象**：`dwc0`（RK3399 原生 GMAC）正常，PCIe 口 RTL8111H（`re0`）消失；dmesg 报
`pcib0: Gen1 link training timeouted: 0x00080001`；`pciconf` 下设备不在总线上。
同板 Linux/OpenWrt 正常，OPNsense 22.7 时代也正常。

**根因（对比实验实锤）**：

| 镜像 | u-boot | 结果 |
|---|---|---|
| 22.7（personalbsd 20220825） | **2020.07** | 双口正常 |
| 26.7.3（matheusber） | 2025.10 | re0 消失 |
| 26.7.3 + u-boot 2020.07 | 2020.07 | **re0 恢复** |

两版 FreeBSD 内核**均含** Rockchip PCIe 驱动——"驱动引入回归"假说被证伪，差异在 u-boot
对 RK3399 PCIe PHY/时钟的初始化状态。对应上游：[FreeBSD-arm 2022 年同报错](https://marc.info/?l=freebsd-arm&m=164487492409386&w=1)、
[matheusber issue #5](https://github.com/matheusber/opnsense/issues/5)。

**修复产物**：`OPNsense-26.7.3-fixed-uboot2020-R4S.img.xz`（本仓库 Releases）。
移植配方（两镜像分区均始于 16 MiB，互换原始扇区即可）：

```bash
dd if=opnsense227-r4s.img of=uboot2020.bin bs=512 skip=64 count=$((32768-64))
dd if=uboot2020.bin of=26.7.3-fixed.img bs=512 seek=64 conv=notrunc
```

## 断流 bug

vendor Realtek `realtek-re-kmod198`（v1.98）在 FreeBSD 15.1 上**空闲也周期性掉链**
（dmesg 大量 `link state changed`），且读 EEPROM 失败导致 MAC 随机。换回原生 iflib
`if_re` 后静置零抖动、MAC 稳定、获得 TSO 等原生能力。设备上保留回退备份
`/boot/kernel/if_re.ko.base`（vendor 备份 `.vendor198`）。

**教训**：识别问题的真正解药是 u-boot 2020.07，vendor 驱动从始至终非必需。

## CPU 调频

OPNsense ARM 镜像默认不跑 `powerd` → RK3399 六核锁 600 MHz → pf+NAT 吞吐被 CPU 卡死。

```bash
sysrc powerd_enable=YES && service powerd start   # 持久化启用
sysrc powerd_flags="-a hadp"                      # 自适应（推荐）
sysrc powerd_flags="-a max"                       # 性能模式（实测与 hadp 同吞吐）
```

## 接口硬件设置

GUI：Interfaces → WAN/LAN → **硬件设置：覆盖全局设置**（`hw_settings_overwrite=1`）。
OPNsense 会按每接口能力重新应用驱动参数（手动 `configctl` 重配会重置卸载参数，GUI 正规
保存才是正路）。生效后 `dwc0` 具备
`RXCSUM,TXCSUM,VLAN_MTU,LINKSTATE,RXCSUM_IPV6,TXCSUM_IPV6`。

---

## 性能与边界

**当前终态：稳定 + ~800 Mbps（85% 线速）**，配置见 [`build-src/FIXED-BUILD-26.7.3-R4S.md`](build-src/FIXED-BUILD-26.7.3-R4S.md)。

- 800 Mbps 是 `if_dwc`（RK3399 GMAC）在 FreeBSD 15.1 的驱动天花板：13.1 时代驱动 43 KB、
  15.1 精简为 16 KB，同硬件 22.7 曾达 900 Mbps
- 与 CPU 频率无关（max 模式实测同 800）、与网卡角色无关（互换实验同区间）
- RSS 无效：re0 / dwc0 均为**单队列**（无硬件分发）；`soreceive_stream` 15.1 默认已开

**突破 800 的两条路**：

1. **USB3 千兆网卡当 WAN**（AX88179 / RTL8153，带卸载，可近线速）——低成本立即可达
2. **内核回填 13.1 的 `if_dwc` 驱动**（13.1 版 43 KB vs 15.1 版 16 KB）——治本但需交叉
   编译内核 + 重新刷机，工程量大

**已验证但无增益/不适用的调优**：`net.isr.*`（默认已 4 线程绑定）、TCP 缓冲放大（默认
8 MB 已足，调大反而波动，已回滚）、`hw.ibrs_disable`（Intel 专用）、MSS 调小（反而降速）、
RSS（单队列不支持）。

---

## 仓库结构

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

产物固件因超出 GitHub 单文件限制（100 MB）发布在
[Releases](https://github.com/Quan-0505/OPNsense-For-R4S/releases)（≤2 GB/文件），
可凭 `build-src` 脚本自行复现。

---

## 免责声明

本仓库全部镜像与脚本均为**实验性成果**，按原样提供、无任何明示或暗示保证；刷机与配置
操作有风险，请自行评估并保留可回退镜像。涉及的商标（OPNsense、NanoPi、Rockchip、Realtek）
归各自权利人所有。
