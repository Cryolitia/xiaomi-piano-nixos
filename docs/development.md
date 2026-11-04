# 维护与验证

硬件配置、可替换的软件包和验证镜像分别维护。设备模块只设置硬件所需默认值；桌面、用户、语言和磁盘策略放在 `configurations/` 和 `images/`。内存容量统一由 `hardware.xiaomi.piano.memoryGiB` 控制；有依据的布局数据放在设备树包中，不复制一份完整硬件模块。

## 来源

`flake.lock` 只固定 nixpkgs。内核、固件、BSP 和 Mesa 等包在各自定义中获取固定提交与 SHA256 的源码；多个包共用的 SunUEFI 来源统一维护在 `packages/sunuefi-source.nix`：

- nixpkgs 提供 NixOS、GNOME、systemd-boot 和常规用户空间。
- Linux 基线与 SunUEFI 的有序补丁共同组成 Piano 内核；补丁还按原 `series.json` 的 SHA256 校验。
- SunUEFI 提供经过适配的设备树覆盖、BSP 代码、UCM、固件覆盖清单，以及稀疏镜像打包工具。
- debian-piano 提供板级初始化和音频拓扑构建来源；piano-firmware 提供设备固件。
- piano-mesa 提供 A830v1 设备 ID 补丁；AudioReach 提供音频拓扑源码。

本仓库的 Nix 配置使用 MIT 许可。被引用的内核、BSP、字体及固件分别遵循其原许可；专有固件不因通过 Nix 获取而改变许可。包会保留相关许可文件，不将构建产物提交到仓库。

## 启动与硬件边界

Linux 设备树的内存表由本项目按容量选择。启动链为 SunUEFI → systemd-boot → Linux EFI stub：systemd-boot 按标准 BLS 启动项加载匹配的内核、initrd 和设备树，命令行指向对应的 NixOS 系统。SunUEFI 通过标准设备树修正协议保留本次启动的面板、Gunyah 参数和内存预留，并在 `ExitBootServices` 时完成硬件退出。

ESP 使用 512 MiB FAT32、4096 字节逻辑扇区和 `SUNUEFI_ESP` 标签，目标是已有的 `sunuefi_esp` 分区。`loader/entries/nixos-*.conf` 使用 `linux`、`initrd`、`devicetree` 和 `options`；载荷使用 nixpkgs systemd-boot 模块的 `/EFI/nixos/<store 名称>-<文件名>.efi` 平铺布局。初始离线 ESP 从系统的 `boot.json` 及其设备树扩展生成入口；后续更新、代际选择和清理完全使用 NixOS 自带的 systemd-boot 模块。`installBootLoader` 只包装写入前的分区身份检查，不另行实现更新器。本项目不构建 UEFI 固件或 Android 模块。

验证镜像统一通过 `gnome-image` 或 `gnome-24gb-image` 构建，一个 `result/` 同时提供 root 和 ESP 的原始镜像、稀疏镜像，以及统一的清单和摘要。`result/boot-files/` 提供同次构建的离线 Linux 启动文件及摘要。镜像打包校验 EFI-stub、initrd、设备树、BLS 路径和 FAT32 读回；运行时由标准模块消费每代 bootspec，`nixos-rebuild` 会连同设备树一起更新启动文件。

标准 EFI 启动需要 SunUEFI 提供完整 RAM/保留区的 EFI 内存描述、设备树修正协议和标准内核退出处理。只有 128 MiB raw 载荷支持的旧固件不满足这些条件。内核、initrd 和 DTB 独立加载，受 FAT32 单文件及 ESP 容量约束；不再使用 Android boot 容器的 16/128 MiB 限制。验证配置保留完整的 nixos-unstable systemd initrd 和 XZ 压缩。

initrd 用单个服务逐一加载 SMMU、pinctrl、CPUCP mailbox、UFS PHY 和 UFS 驱动，避免 systemd 的黑名单检查与并发模块加载改变次序。stage1 和 stage2 从各自 systemd 的 `80-drivers.rules` 派生规则，只排除 SoC 总线的默认 modalias 加载，保留其他 udev 操作。显示、触摸、无线和 ADSP 按现有板级顺序初始化，普通 modalias 自动加载不能抢先启动这些 DMA 主设备。BSP 适配保留实时 sysfs DMA、时钟及资源检查，不把某次采集的机器状态作为通用硬件事实。当前内核序列只有 MiPPS 用户态传输接口，因此验证配置采用普通 PD 降压充电，不自动启用未经接入的快充认证或直充。

## 检查

运行本机的脚本格式、单行复合语句检查和模块接口检查：

```sh
nix flake check
```

Python 规则统一放在 `ruff.toml`。`--no-build` 只评估检查项，不会执行 Ruff；跨架构评估和完整构建仍可分别运行：

```sh
nix flake check --all-systems --no-build
nix eval .#nixosConfigurations.piano-gnome.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.piano-24gb-gnome.config.system.build.pianoImage.drvPath
nix build .#kernel
nix build .#gnome-image
```

完整镜像构建需要原生或远端 `aarch64-linux` builder。x86_64 主机上的评估通过，不能替代 ARM64 编译或实机启动。首次上机应确认显示、触摸、键盘、无线、蓝牙、音频、充电及挂起恢复，并保存实际镜像 SHA256 和日志。

升级 nixpkgs 时更新 `flake.lock`；升级其他来源时修改对应软件包的 fetch 定义，SunUEFI 共用来源只改一处。随后核对内核版本、补丁摘要、设备树处理、固件协议版本和 BSP 源码转换。所有配置都从同一包集取得内核和模块，不能混用旧 ESP 的内核与新 root 中的模块。
