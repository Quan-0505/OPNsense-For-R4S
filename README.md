# OPNsense for NanoPi R4S

NanoPi R4S (RK3399, 2×Gigabit) 上部署 OPNsense 26.7.3 的**实战问题修复与性能调优总结**。

本仓库记录从"编译修复版镜像 → 真机验证 → 稳定性排障 → 吞吐优化"的完整过程、根因链与终态配置，供同款设备用户复现与避坑。

---

## TL;DR（结论速览）

| 问题 | 根因 | 修复 |
|---|---|---|
| 26.7.x 只识别一个网口（re0/RTL8111H 消失） | **u-boot 版本回归**：2025.10 下 RK3399 PCIe 链路训练超时（`Gen1 link training timeouted`），2020.07 正常 | 镜像 u-boot 区（扇区 64–32767）换回 **U-Boot 2020.07**（v2 镜像） |
| 网卡间歇性断流、web 不稳定 | **vendor Realtek 1.98 驱动**（空闲也会周期性掉链） | 换回 **FreeBSD 原生 iflib if_re** 驱动 |
| 测速只有 ~300Mbps | **CPU 锁频 600MHz**（OPNsense 镜像默认没跑 powerd） | 启用 `powerd`（自适应/性能模式） |
| 吞吐 ~500Mbps | 接口硬件参数未正确应用（configd 手动重配会重置卸载） | GUI 接口页开启 **"硬件设置：覆盖全局设置"**（hw_settings_overwrite=1） |
| 吞吐上限 ~800Mbps | **dwc0（RK3399 GMAC）在 FreeBSD 15.1 的驱动天花板**（13.1 时代可达 900） | 见下文"吞吐上限分析" |

**终态：稳定 + ~800Mbps（85% 线速）**。想跑满 900+ 需换 USB3 千兆网卡当 WAN 或内核回填 13.1 的 if_dwc 驱动。

---

## 环境

- 硬件：NanoPi R4S（标准版，无 EEPROM → MAC 随机，建议 GUI 手动固定）
- 系统：OPNsense CE 26.7.3（FreeBSD 15.1-RELEASE-p3, arm64）
- 网络：WAN = dwc0（RK3399 原生 GMAC，DHCP 接上级路由）/ LAN = re0（RTL8111H PCIe，192.168.2.1/24）

## 一、双网口识别问题（issue #5 同型）

### 现象
- 26.7.x 镜像只有 `dwc0`，PCIe 口 RTL8111H（`re0`）不出现
- dmesg: `pcib0: Gen1 link training timeouted: 0x00080001`
- `pciconf -lv`：PCI 总线上**没有** Realtek 设备（驱动绑不上）
- 同板 Linux/OpenWrt 正常；**OPNsense 22.7 时代正常**

### 根因定位（对比实验）
| 镜像 | u-boot | FreeBSD | 结果 |
|---|---|---|---|
| 22.7（personalbsd 20220825） | **2020.07** | 13.1 | ✅ 双口正常（900Mbps） |
| 26.7.3（matheusber） | 2025.10 | 15.1 | ❌ re0 消失 |
| 26.7.3 + u-boot 2020.07 | 2020.07 | 15.1 | ✅ re0 恢复 |

- 两版内核**都包含** Rockchip PCIe 控制器驱动（"FreeBSD 引入驱动导致回归"假说**证伪**）
- 差异纯在 u-boot 对 RK3399 PCIe PHY/时钟的初始化状态
- 上游线索：[FreeBSD-arm 2022 年同报错（无解）](https://marc.info/?l=freebsd-arm&m=164487492409386&w=1)、[matheusber issue #5](https://github.com/matheusber/opnsense/issues/5)

### 修复产物
`OPNsense-26.7.3-fixed-uboot2020-R4S.img.xz`
SHA256: `ab724fcca797eb972403f5297bd03ec46574b874fa622d7308fdbe8f51a12b55`

移植方法（两个镜像分区均始于 16MiB，互换原始扇区即可，不动分区表/文件系统）：
```bash
dd if=opnsense227-r4s.img of=uboot2020.bin bs=512 skip=64 count=$((32768-64))
dd if=uboot2020.bin of=26.7.3-fixed.img bs=512 seek=64 conv=notrunc
```

## 二、网卡断流（比性能更优先的 bug）

### 现象
- 高负载/空闲时网口反复 DOWN→UP，web 间歇性不可达，偶发整机重启
- dmesg 大量 `link state changed to DOWN/UP`（含双口同时掉线）

### 根因
**vendor Realtek 驱动 `realtek-re-kmod198`（v1.98）**：当初为修 re0 识别而内建，
实测该驱动在 FreeBSD 15.1 上**空闲也周期性掉链**，且存在读 EEPROM 失败（MAC 随机）。

### 修复
换回 FreeBSD 原生 iflib `if_re`（设备上备份 `/boot/kernel/if_re.ko.base`），移除 loader.conf 的 vendor 预载。
- 修复后静置 7 分钟+ **零抖动**
- 附加收益：MAC 恢复稳定读取（`58:9c:fc:10:58:72`）、获得 TSO4 等原生卸载
- **教训**：当初识别问题的真正解药是 u-boot 2020.07，vendor 驱动从未必要

## 三、性能优化记录

### 3.1 CPU 锁频（300→500+）
- 现象：六核全锁 **600MHz**（最低档）
- 根因：OPNsense ARM 镜像默认未启用 `powerd`，cpufreq_dt 停在 u-boot 默认频率
- 修复：`sysrc powerd_enable=YES && service powerd start`
  - 自适应：`sysrc powerd_flags="-a hadp"`
  - 性能模式：`sysrc powerd_flags="-a max"`（实测吞吐无差异，日常建议 hadp）
- 验证：负载下 600→1416→1800MHz（A72 大核）

### 3.2 接口硬件参数（500→750-800）
- GUI：Interfaces → WAN（及 LAN）→ 勾选 **"硬件设置：覆盖全局设置"**（`hw_settings_overwrite=1`）
- 效果：OPNsense 以每接口硬件能力重新应用驱动参数（手动 configd 重配会重置卸载参数，GUI 正规保存才是正路）
- 终态 dwc0：`options=68000b<RXCSUM,TXCSUM,VLAN_MTU,LINKSTATE,RXCSUM_IPV6,TXCSUM_IPV6>`

### 3.3 吞吐上限 ~800Mbps 分析
- 与 CPU 频率无关（max 模式实测同 800）
- 与哪块网卡做 WAN 无关（角色互换实验同 ~500-800 区间，且曾诱发断流误判）
- **根因**：`if_dwc` 驱动在 FreeBSD 13.1（43KB）→ 15.1（16KB）被**大幅重写精简**；dwc0 单队列、无 TSO；RSS 无效（单队列无硬件分发）
- 22.7（13.1）时代 dwc0 WAN 实测 900Mbps

### 破 800 的两条路
1. **USB3 千兆网卡当 WAN**（AX88179/RTL8153，~30-50 元，带卸载，实测可近线速）——推荐、可当天落地
2. **内核回填 13.1 的 if_dwc 驱动**（13.1 版 43KB vs 15.1 版 16KB，需交叉编译内核 + 刷机）——治本但重工程

### 已尝试但无效/不适用的调优
- `net.isr.*`：本就 4 线程绑定 hybrid，RSS 不适用（单队列）
- `net.inet.tcp.soreceive_stream`：15.1 默认已开启
- TCP 缓冲放大（maxsockbuf/recvbuf）：默认 8MB 已足够，调大反而有波动风险 → **已回滚**
- `hw.ibrs_disable`：Intel 专用，ARM 无意义
- MSS 调小（1240）：降低吞吐，跳过

## 四、终端配置（稳定 + 800Mbps）

```text
接口：LAN = re0  192.168.2.1/24   （GUI 手动固定 MAC）
      WAN = dwc0  DHCP（上级路由）
驱动：re0 = FreeBSD 原生 iflib if_re（非 vendor）
      dwc0 = if_dwc（原生，校验和卸载已开）
powerd：powerd_enable=YES，powerd_flags="-a hadp"（负载自动拉满）
硬件覆盖：LAN/WAN 均开启"覆盖全局设置"
```

## 五、常见坑速查

1. **测速波动大**（450/550/800/500 都出现过）：先测 2-3 次 + 换节点，再归因参数
2. **不要手改 /conf/config.xml + 远程重启**：曾导致整机失联需重刷（GUI 正规路径更安全；如需 CLI 用 configctl + 保留串口/物理恢复手段）
3. **下载 22.7 参考镜像要校验完整性**：personalbsd 服务器传输易截断（对照 Content-Length 或 xz -t）
4. **标准版 R4S 无 EEPROM**：MAC 随机（vendor 驱动读 EEPROM 失败尤甚），WAN 口建议固定 MAC
5. **供电**：满载功耗 ~8-10W，链路抖动先查电源（5V/3A 质量电源 + 短粗线）与网线
6. **重启**：v2 镜像（u-boot 2020.07）重启正常（多次 uptime 验证）；早期失联系配置手术所致

## 六、参考资料

- [matheusber/opnsense（26.7.3 R4S 镜像来源）](https://github.com/matheusber/opnsense)
- [FreeBSD-arm: RockPro64 PCI "Gen1 link training timeouted"（2022，无解）](https://marc.info/?l=freebsd-arm&m=164487492409386&w=1)
- [22.7 参考镜像（personalbsd.org，u-boot 2020.07）](https://personalbsd.org/?page_id=2)
- [OPNsense 性能调优参考 1](https://blog.51cto.com/fxn2025/6056226)
- [OPNsense RSS 调优参考（R4S 单队列不适用）](https://pfchina.org/opnsense%E8%B0%83%E6%95%B4%E7%BD%91%E5%8D%A1%E5%8F%82%E6%95%B0%E6%8F%90%E5%8D%87%E7%BD%91%E7%BB%9C%E5%90%9E%E5%90%90%E9%87%8F/)

---

*免责声明：镜像与操作均为实验性成果，按原样提供，不提供任何保证；刷机有风险，请自行评估。*
