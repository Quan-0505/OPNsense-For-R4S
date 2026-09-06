# NanoPi R4S 部署 OPNsense 26.7 指南（2026 年核查版）

结论先行：**不需要自己编译**。社区维护者 matheusber 已经为 NanoPi R4S(R4SE) 构建并发布了
OPNsense 26.7.3 的 aarch64 镜像，直接下载写卡即可。本文同时给出"为什么没有官方镜像"
和"想自己编译时的两条可行路径"。

---

## 1. 背景核查

| 项目 | 结论 | 依据 |
|---|---|---|
| 26.7 是否最新 | 是。CE 26.7 于 2026-07-15 发布，当前补丁版 26.7.3（2026-08-27，含 hotfix _8） | [官方 release notes](https://docs.opnsense.org/releases/CE_26.7.html) |
| 26.7 基于 | FreeBSD 15.1、OpenSSL 3.5、PHP 8.5 | 同上 |
| 官方是否发布 ARM 镜像 | **否**。官方 26.7 镜像目录只有 amd64（dvd/nano/serial/vga） | [官方镜像列表](https://mirror.ntct.edu.tw/opnsense/releases/26.7/) |
| OPNsense 是否"支持"R4S | 官方**构建系统**支持（`opnsense/tools` 仓库内有 `device/R4S.conf`，与 RPI/ROCKPRO64 并列），但不公开发布 ARM 二进制 | [opnsense/tools 设备配置](https://deepwiki.com/opnsense/tools/8.2-device-configurations) |
| R4S 硬件 | RK3399（2×A72+4×A53）、4GB LPDDR4 可选、**无板载 eMMC（只能 TF 卡启动）**、双千兆：原生口 RTL8211E + PCIe 口 RTL8111H | [FriendlyELEC Wiki](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R4S/zh) |
| R4S 标准版 / 企业版 | 仅企业版带全球唯一 MAC 的 EEPROM；标准版按硬件 ID 自动生成 MAC。网卡芯片相同，镜像通用 | 同上 |

> 参考的 Reddit 帖（r/opnsense 的 NanoPi R4S 4GB + 22.7）思路与此相同：
> 官方无 ARM 镜像 → 用社区构建的 aarch64 镜像 + dd 写 TF 卡。现在 26.7 时代
> 有同样现成的社区产物，无需再从 22.7 时代的老镜像手动折腾。

---

## 2. 现成镜像（推荐路径）

维护者：matheusber/opnsense（[仓库](https://github.com/matheusber/opnsense)），镜像目标
NanoPi R4S / R4SE / R5S / Orange Pi 5 Plus，从官方 opnsense 源码按官方 tools 流程构建，
R4S 镜像使用 FreeBSD ports 的 u-boot。

**Release（最新 26.7.3）**：https://github.com/matheusber/opnsense/releases/tag/26.7.3

R4S 资产（Assets 里）：
- `OPNsense-26.7.3-arm-aarch64-R4S.img.xz`（约 1.24 GB）
- 直链：https://github.com/matheusber/opnsense/releases/download/26.7.3/OPNsense-26.7.3-arm-aarch64-R4S.img.xz
- SHA256（img.xz）：`bcbc58c430dc8d7207d19aeccfc8497bece1954fac163cfc4d053a1c60c9db96`
- 配套签名 `.sig` 与同版本 `base/kernel/aux-*-aarch64` tar（自建更新仓库用，见 §5）

维护者实测声明：R4SE 已实机验证；R4S 本体为同系列板（镜像标注 R4S(E)）。

### 烧录步骤

1. 解压：`unxz OPNsense-26.7.3-arm-aarch64-R4S.img.xz`（Windows 可用 7-Zip）。
2. 校验（以解压后的 `.img` 为准重算；GitHub 展示的是 .xz 的哈希，先验 .xz 更省事）：
   ```powershell
   # PowerShell
   Get-FileHash .\OPNsense-26.7.3-arm-aarch64-R4S.img.xz -Algorithm SHA256
   ```
3. 写 TF 卡（≥8GB，Class10 以上）。
   - Windows：用 **balenaEtcher** 或 **Rufus**（整卡写入，别选"制作启动盘"类选项），
     或管理员运行 win32diskimager。
   - Linux/macOS：
     ```bash
     sudo dd if=OPNsense-26.7.3-arm-aarch64-R4S.img of=/dev/sdX bs=1m status=progress conv=sync
     ```
     先 `lsblk`/`diskutil list` 确认盘符，别写错盘。
4. 插入 R4S 的 microSD 槽，5V/3A 电源（普通充电头即可，**不支持 USB-PD 协商**）上电。
5. 首启：电脑网线接 R4S 网口，浏览器访问 https://192.168.1.1（OPNsense 默认 LAN；
   若不通就换另一个网口试；账号密码 root/opnsense，向导会要求修改）。R4S 无 HDMI，
   排障请用调试串口（3-pin，1500000 bps 见 wiki；FreeBSD/u-boot 输出常见 115200，
   乱码就换 1500000）。

### 该镜像已知注意事项（来自发布说明 + 维护者 issue 区）

- 发布者提示镜像内 `/etc/rc` 应换成 opnsense/core 仓库里的新版（发布者尚未同步），
  根分区自动扩容正常。属小瑕疵；要动手替换需在刷入后、或先挂载镜像改好再刷。
- R5S / Orange Pi 5 Plus 的首启"网线全拔"caveat 与 R4S 无关。
- **双网卡识别问题（R4S 非 R4SE 需重点留意）**：
  FreeBSD 15.1 下 R4S 的两个口对应 `dwc0`（RK3399 原生 GMAC/DesignWare 驱动，
  即友善文档里的 eth0，RTL8211E 侧）与 `re0`（PCIe 的 RTL8111H，if_re 驱动）。
  已有用户报告部分 R4S 上 `re0` 不出现（dmesg/pciconf 只有 RK3399 PCIe Root Port、
  无 Realtek 设备），26.1/26.7.1/25.1.3 均复现；R4SE（发布者实机）则两个口都正常。
  已知解决办法（[issue #5](https://github.com/matheusber/opnsense/issues/5) 内方法，
  把示例路径换成 FreeBSD 15 的包目录 `pkg.freebsd.org/FreeBSD:15:aarch64/...`）：
  用 Realtek 官方驱动 `realtek-re-kmod198` 替换内核自带 if_re 后 `re0` 即出现。
  若刷完只看到一个网口：先连串口看 dmesg，再按上述方法装驱动；不要误判为硬件损坏。
- 网口与驱动/默认分配的对应关系可能与机壳标注不同（有人报告检测到的口被 OPNsense
  默认指派成 LAN 而物理上是 WAN 侧），以 `ifconfig`/控制台 assignments 为准，
  两网口都接电脑试即可。
- 社区镜像无官方背书：下载后核对 SHA256 与签名、只在可信网络/隔离环境首次启用。

---

## 2.5 NanoPi R3S 有 26.7 吗？—— 目前没有，且不建议

**结论：R3S 没有任何现成 OPNsense 26.7 镜像，也没有任何可用的构建配置，短期不现实。**

核查依据：

1. **无镜像、无 device 配置**：OPNsense 官方 `opnsense/tools` 的 ARM 设备配置只有
   RPI / ROCKPRO64 / R4S / 通用 ARM64（无 R3S）；社区镜像维护者 matheusber 只做
   R4S(E)/R5S/Orange Pi 5 Plus。全网未见 R3S 的 OPNsense 镜像或构建记录。
2. **FreeBSD 对 RK3566 的板级支持仍在"能启动、驱动不齐"阶段**（截至 2026 年初，
   FreeBSD 论坛 rk3566 实测帖）：
   - 可启动（Radxa Zero 3E 同 RK3566），串口 1500000 正常；
   - **pinctrl 驱动不完整**：2026-02 仍需靠社区大补丁才能启用多余 UART；
   - **以太网驱动（if_eqos）在 1000baseT 全双工下 TX 有缺陷**：需强制 rgmii +
     std delays 变通，实测约 380 Mbit/s 且带重传（Linux 同机 940+ Mbit/s），
     MAC 每次重启随机；
   - R3S 第二网口是 PCIe 扩展（RTL8111H 一类），FreeBSD 侧 PCIe+re 链路同样有上面
     R4S 的驱动可靠性风险。
   - 上述多为 FreeBSD main/15.x 状态，OPNsense 26.7 用的 FreeBSD 15.1 分支只会更保守。
3. **R3S 参考系是 OpenWrt**：友善官方生态（FriendlyWrt/OpenWrt/Debian）对 R3S 支持良好；
   若只是要"双千兆小路由"，R3S 留在 OpenWrt 是合理选择，OPNsense 无必要硬上。

结论性建议：ARM 上跑 26.7 选 R4S(E)（本指南主线）；要更快的 RK3568 平台可关注 R5S
（matheusber 在维护，2.5G 驱动用 Realtek 1.98，但镜像仍在完善、要求 EDK2 引导）。
R3S 等 FreeBSD 上游把 RK3566 的 pinctrl/eqos 修稳再说。

---

## 3. 官方镜像为什么"没有 ARM"？

OPNsense CE 的策略：官方只发布 amd64 安装镜像与 aarch64 之外的官方仓库；
ARM 设备由 `opnsense/tools` 构建系统以设备配置（`device/R4S.conf` 等）支持，
但镜像与 aarch64 软件源需自行构建或依赖社区发布。FreeBSD 15.1 已含 RK3399 平台支持，
这是 26.7 能跑在 R4S 上的前提。

---

## 4. 自己编译（两条路径，含现实评估）

共同前提：**需要一台 FreeBSD 主机/虚拟机**（官方 tools 仅支持在 FreeBSD 上运行；
amd64 FreeBSD 可交叉构建 aarch64，但慢；社区实践用 arm64 构建机）。

### 路径 A：官方 opnsense/tools + device/R4S.conf（最"正统"）

有人在 AWS Graviton（arm64）FreeBSD 虚拟机上按官方 tools 的 make 步骤成功产出
`OPNsense-<时间戳>-arm-aarch64-R4S.img` 并 dd 正常启动
（[论坛佐证](https://forum.opnsense.org/index.php?action=printpage;topic=38745.0)）。

```sh
git clone https://github.com/opnsense/tools
cd tools
# 按 docs/ 流程：make update → make base → make kernel → make ports →
# make plugins → make core → make packages → make image（选择 R4S 设备配置）
```

### 路径 B：matheusber 的构建脚本（同一构建流程的成品化包装）

仓库 `arm64-opnsense-build/` 目录内按官方流程编号了 1.1→9 的脚本
（fetch/fingerprint/base/kernel/ports/plugins/core/packages/sign/arm），
`env.sh` 已对齐 26.7.3，照 README 顺序在 FreeBSD 15.1 上执行即可复现其 release 产物。
参考：https://github.com/matheusber/opnsense/tree/main/arm64-opnsense-build

### 现实评估

- 构建机要求：FreeBSD 15.x，数十 GB 磁盘 + 充足内存；纯 aarch64 全量构建
  （含 qemu-user 交叉编译 ports/插件）在发布者机器上约 **3 天**。
- 产出还包括自建 aarch64 仓库问题（见 §5）。
- **结论：为"跑最新版"这个目标，自编译的投入产出比远低于直接刷 §2 的现成 26.7.3 镜像；
  自编译只在你需要改内核/驱动/裁剪时才有意义。**

> 本环境（Windows 沙盒，无 FreeBSD）无法直接产出可刷入镜像，也不适合挂 3 天的构建农场；
> 若确实要走自编译，建议用一台 arm64 云主机（Graviton/鲲鹏类）跑 FreeBSD VM 按路径 B 执行。

---

## 5. 后续升级与插件（重要预期管理）

- OPNsense **不提供官方的 CE aarch64 软件源**，所以社区镜像装好后，GUI 的
  "固件 → 更新/插件"默认并不能直接拉官方仓库。
- matheusber 每个 release 附带 `base-26.7.3-aarch64.txz`、`kernel-*.txz`、
  `aux-*.tar`（"may be used for repository creation"）——即自建仓库的素材；
  也可以在刷入后手工 `pkg`/更新 txz 做小版本跟进，或等待发布者更新镜像。
- 新装完请记住：这是**社区维护**版本，别把更新预期等同于官方 amd64 的自动 OTA。

---

## 6. 关键链接汇总

- 26.7 发布说明：https://docs.opnsense.org/releases/CE_26.7.html
- 官方 26.7 镜像目录（仅 amd64）：https://mirror.ntct.edu.tw/opnsense/releases/26.7/
- matheusber/opnsense 仓库：https://github.com/matheusber/opnsense
- 26.7.3 Release 页（含 R4S 镜像）：https://github.com/matheusber/opnsense/releases/tag/26.7.3
- opnsense/tools（device/R4S.conf）：https://github.com/opnsense/tools
- FriendlyELEC NanoPi R4S 中文 Wiki：https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R4S/zh
- OPNsense 论坛 ARM 长期讨论帖：https://forum.opnsense.org/index.php?topic=22262.0
- OPNsense 论坛 R4S 专帖：https://forum.opnsense.org/index.php?topic=20332.0
- matheusber issue #5（R4S 只识别一个网口 / realtek-re-kmod198 办法）：
  https://github.com/matheusber/opnsense/issues/5
- FriendlyELEC NanoPi R3S 中文 Wiki：https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R3S/zh
- FreeBSD 论坛 rk3566 标签（含 2025-11「NanoPi R3S 双网口跑 FreeBSD 路由可行吗」的
  无人回答提问、Zero 3E 实测与 pinctrl/eqos 补丁讨论）：
  https://forums.freebsd.org/tags/rk3566/
