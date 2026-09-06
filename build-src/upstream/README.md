# upstream — OPNsense 编译框架源码（matheusber/opnsense）

本目录收录编译修复版镜像所使用的 **matheusber/opnsense 源码包**（原始、未修改镜像）。

- 文件：`matheusber-opnsense.zip`
- SHA256：`4a07304962ae4337008614ab4a311a064c0b4da40ed8c194281297d31f69d64b`
- 来源：matheusber 的 arm64 OPNsense 构建框架（`opnsense-main/`，含
  `arm64-opnsense-build/` 分步构建脚本与 edk2/引导文件等）
- 上游：https://github.com/matheusber/opnsense
- 用途：26.7.3 官方 R4S 镜像的构建基线；本仓库 `scripts/` 中的
  `build0_prepare.sh ~ build3_verify.sh` 即围绕该框架的取用/修复/验证流水线

> 说明：
> - 本包为**上游原样镜像**，版权归原作者 matheusber；仅作复现与追溯用。
> - 未入库的大件（可复现，无需随仓库分发）：`aux-26.7.3-aarch64.tar`
>   （FreeBSD pkg 编译缓存，含 rust/go/cmake 等）与 `fbsd.raw.xz`
>   （FreeBSD base 镜像），均来自官方/可再生物源。
> - 我们对成品镜像的改动（u-boot 2020.07 移植、驱动回退、标签定制）都记录在
>   `scripts/` 与仓库根 README，未改动上游源码本身。
