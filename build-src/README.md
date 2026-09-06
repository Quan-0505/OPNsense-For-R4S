# build-src — OPNsense R4S 编译与验证资产

本目录收录 26.7.3 修复版镜像从**编译、修复、对比诊断到环境迁移**所用的全部脚本与证据。
完整结论与说明见仓库根 `README.md`。

## 布局

```
build-src/
├── scripts/                        编译/修复/诊断/环境迁移/定制脚本
│   ├── build0_prepare.sh           构建主机准备（拉取 opnsense/tools 等）
│   ├── build1_vm.sh / build1b_console.sh / build1c_fresh.sh
│   │                               FreeBSD 构建 VM 启动与初始化（qemu + cloud-init seed）
│   ├── build2_fix.sh / build2b_finish.sh / build3_verify.sh
│   │                               镜像外科修复（vendor 驱动内建）→ 验证
│   ├── m_uboot2020.sh              ★ u-boot 2020.07 移植镜像制作（扇区 64-32767 互换）
│   ├── m_vm_compare.sh / m_run22b.sh / compare*.sh / compare_followup.sh
│   │                               22.7 vs 26.7 内核/u-boot/DTB 对比解剖（回归定位）
│   ├── dl227.sh / dl227b.sh / scan_pb.sh   22.7 参考镜像下载与 personalbsd 页面扫描
│   ├── inspect_img.py              镜像分区/引导结构解析
│   ├── patch_cpu_label.sh          ★ 首页 CPU 型号定制（ARM Cortex-A53 → Rockchip RK3399）
│   └── migrate_m*.sh               构建主机 20G→130G 磁盘迁移（/build 保留）
├── results/
│   ├── compare-result.txt          22.7/26.7 内核驱动字符串对比输出
│   └── compare22b-result.txt       GPT 布局下完整对比（u-boot 版本差异实锤）
├── FIXED-BUILD-26.7.3-R4S.md       修复版构建清单与校验（v1/v2）
└── OPNsense-26.7-R4S-deploy-guide.md  部署背景研究与刷机指南
```

## 说明

- **不在本仓库的内容**：镜像成品（xz，1.2-1.3GB 超出 GitHub 单文件限制，见仓库
  Releases）与 FreeBSD 构建 VM 磁盘（6GB）。需要者可凭 `m_uboot2020.sh` + 官方/22.7
  镜像自行复现，校验值见 `FIXED-BUILD-26.7.3-R4S.md`。
- `patch_cpu_label.sh`：修改
  `/usr/local/opnsense/mvc/app/controllers/OPNsense/Diagnostics/Api/CpuUsageController.php`
  的 `getCPUTypeAction()`，当 `hw.model` 含 `Cortex` 时把首页 CPU 标签显示为
  `Rockchip RK3399`；运行前会自动备份（`.bak-rk3399`）。注意：OPNsense 升级会覆盖该文件，
  升级后需重新执行。
- 部分脚本含构建主机路径（`/build`、`/root`、qemu 参数），按各自环境调整后使用。
- `migrate_*` 针对 Debian 构建主机磁盘迁移，非 OPNsense 必需，仅保留环境复现记录。
- 所有脚本为实验性记录，无凭据、按原样提供。
