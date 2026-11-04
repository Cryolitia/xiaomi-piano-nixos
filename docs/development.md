# 维护与验证

硬件配置、可替换的软件包和验证镜像分别维护。设备模块只设置硬件所需默认值；桌面、用户、语言和磁盘策略放在 `configurations/` 和 `images/`。内存容量统一由 `hardware.xiaomi.piano.memoryGiB` 控制；有依据的布局数据放在设备树包中，不复制一份完整硬件模块。

## 来源

`flake.lock` 固定全部提交及 NAR 哈希：

- nixpkgs 提供 NixOS、GNOME、systemd-boot 和常规用户空间。
- Linux 基线与 SunUEFI 的有序补丁共同组成 Piano 内核；补丁还按原 `series.json` 的 SHA256 校验。
- SunUEFI 提供经过适配的设备树覆盖、BSP 代码、UCM、固件覆盖清单，以及 Linux 启动应用和 PumpLib 源码。
- debian-piano 提供板级初始化和音频拓扑构建来源；piano-firmware 提供设备固件。
- piano-mesa 提供 A830v1 设备 ID 补丁；AudioReach 提供音频拓扑源码。

本仓库的 Nix 配置使用 MIT 许可。被引用的内核、BSP、字体及固件分别遵循其原许可；专有固件不因通过 Nix 获取而改变许可。包会保留相关许可文件，不将构建产物提交到仓库。

## 启动与硬件边界

Linux 设备树的内存表由本项目按已验证容量选择；已有 SunUEFI 负责面板选择和 Gunyah 资源交接，不会替换内存表。Linux 载荷采用它支持的 Android boot header v2 容器；这个 `boot.img` 装的是 Linux 内核、initrd 和设备树，不是要刷入 Android BOOT 分区的引导镜像。

ESP 使用 512 MiB FAT32、4096 字节逻辑扇区和 `SUNUEFI_ESP` 标签，目标是已有的 `sunuefi_esp` 分区。启动链为 SunUEFI → systemd-boot → `EFI/Piano/LinuxBoot.efi` → 驻留核心加载 `EFI/Piano/stable/boot.img`。systemd-boot 来自 nixpkgs；Linux 启动应用复用固定 SunUEFI 源码及 PumpLib，以 Clang/LLD 独立构建，不编译 UEFI 固件或 Android 模块。`boot-files` 保持为仅更新 Linux 载荷的目录，整套镜像和独立 ESP 输出共用相同的打包实现。

构建会拒绝超过现有交接窗口的载荷：initrd 16 MiB、总容器 64 MiB、设备树约 2 MiB。验证配置使用 nixos-unstable 的 systemd initrd 和 XZ 压缩，不引入旧 Debian initramfs 对 `/usr/lib` 的要求。

initrd 用单个服务逐一加载 SMMU、pinctrl、CPUCP mailbox、UFS PHY 和 UFS 驱动，避免 systemd 的黑名单检查与并发模块加载改变次序。stage1 和 stage2 从各自 systemd 的 `80-drivers.rules` 派生规则，只排除 SoC 总线的默认 modalias 加载，保留其他 udev 操作。显示、触摸、无线和 ADSP 按现有板级顺序初始化，普通 modalias 自动加载不能抢先启动这些 DMA 主设备。BSP 适配保留实时 sysfs DMA、时钟及资源检查，不把某次采集的机器状态作为通用硬件事实。当前内核序列只有 MiPPS 用户态传输接口，因此验证配置采用普通 PD 降压充电，不自动启用未经接入的快充认证或直充。

## 检查

```sh
nix flake check --all-systems --no-build
nix eval .#nixosConfigurations.piano-gnome.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.piano-24gb-gnome.config.system.build.pianoImage.drvPath
nix build .#kernel
nix build .#esp-image
nix build .#gnome-image
```

完整镜像构建需要原生或远端 `aarch64-linux` builder。x86_64 主机上的评估通过，不能替代 ARM64 编译或实机启动。首次上机应确认显示、触摸、键盘、无线、蓝牙、音频、充电及挂起恢复，并保存实际镜像 SHA256 和日志。

升级来源时，先更新对应 flake 输入，再核对内核版本、补丁摘要、设备树处理、固件协议版本和 BSP 源码转换。所有配置都从同一包集取得内核和模块，不能混用旧 ESP 的内核与新 root 中的模块。
