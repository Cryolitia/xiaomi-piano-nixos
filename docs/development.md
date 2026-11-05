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

ESP 使用 512 MiB FAT32、4096 字节逻辑扇区和 `SUNUEFI_ESP` 标签，目标是已有的 `sunuefi_esp` 分区。`loader/entries/nixos-*.conf` 使用 `linux`、`initrd`、`devicetree` 和 `options`；载荷使用 nixpkgs systemd-boot 模块的 `/EFI/nixos/<store 名称>-<文件名>.efi` 平铺布局。初始离线 ESP 从系统的 `boot.json` 及其设备树扩展生成入口；后续更新、代际选择和清理完全使用 NixOS 自带的 systemd-boot 模块。本项目不构建 UEFI 固件或 Android 模块。

验证镜像统一通过 `gnome-image` 或 `gnome-24gb-image` 构建，一个 `result/` 同时提供 root 和 ESP 的原始镜像、稀疏镜像，以及统一的清单和摘要。`result/boot-files/` 提供同次构建的离线 Linux 启动文件及摘要。镜像打包保留启动载荷的基本架构和格式检查，并读回验证 FAT32 中的启动文件；运行时由标准模块消费每代 bootspec，`nixos-rebuild` 会连同设备树一起更新启动文件。

标准 EFI 启动需要 SunUEFI 提供完整 RAM/保留区的 EFI 内存描述、设备树修正协议和标准内核退出处理。只有 128 MiB raw 载荷支持的旧固件不满足这些条件。内核、initrd 和 DTB 独立加载，受 FAT32 单文件及 ESP 容量约束；不再使用 Android boot 容器的 16/128 MiB 限制。验证配置保留完整的 nixos-unstable systemd initrd 和 XZ 压缩。

initrd 用单个服务逐一加载 SMMU、pinctrl、CPUCP mailbox、UFS PHY 和 UFS 驱动，避免 systemd 的黑名单检查与并发模块加载改变次序。stage1 和 stage2 从各自 systemd 的 `80-drivers.rules` 派生规则，只排除 SoC 总线的默认 modalias 加载，保留其他 udev 操作。显示、触摸、无线和 ADSP 按现有板级顺序初始化，普通 modalias 自动加载不能抢先启动这些 DMA 主设备。BSP 适配保留实时 sysfs DMA、时钟及资源检查，不把某次采集的机器状态作为通用硬件事实。当前内核序列只有 MiPPS 用户态传输接口，因此验证配置采用普通 PD 降压充电，不自动启用未经接入的快充认证或直充。

## 显示、传感器与无线身份

设备树将遗留 MMSS 节点转换为标准 SM8750 interconnect provider，并为 MDSS 提供 `mdp0-mem` 和 `cpu-cfg` 路径。DPU 沿父 MDSS 取得这些路径，通过现有 RPMh/BCM 驱动申请显示带宽。显示仍提供七档固定刷新率。连续 VRR 还需要面板允许的逐帧周期范围、双 DSI AVR 同步及 DRM 驱动实现；原厂 P81 的固定 DFPS 列表不能替代这些条件。[原厂 P81 配置](https://github.com/MiCode/vendor_qcom_opensource_display-devicetree/blob/cc4e65ad4bd54e26b60f5a8ee76bbc3cca6821b9/display/dsi-panel-p81-35-02-0b-dualdsi-dsc-lcd-video.dtsi)

传感器使用 FastRPC、libssc 和标准 SensorProxy。导入程序读取 GPT 活动槽位，通过 liblp 校验 super 元数据，再建立只读 ODM/vendor 映射、只读挂载 persist 并复制同机配置与校准数据。服务按 ADSP、配置导入、sensors PD、SensorProxy 的顺序启动。`hardware.sensor.iio.enable = false` 关闭整条 SSC 服务链；板载 SSC 不使用内核未提供的 `hid-sensor-hub`，只对该 initrd 模块作逐项排除，其余缺失模块仍会阻止构建。

GNOME 负责旋转显示和触控、笔输入坐标；不另设旋转守护程序。自动旋转需要未锁定方向、有效加速度计和内置屏幕，并遵循 GNOME 的触摸模式策略：没有 tablet-mode switch 时，枚举到鼠标或触控板会退出触摸模式。普通键盘不触发这一限制。

指纹模块注册 QTEE/UIO 控制接口，提供 `piano-fingerprint-ctl` 的现有初始化和事件诊断命令。签名 TA 与模型按清单校验，供客户端读取的副本保留未压缩形式，不改变其他内核固件的压缩策略。GNOME 指纹录入和解锁尚未接入：Piano 的 `gfpia` 需要真实 HAT 验签及 QTEE 协议支持，现有面向旧 QSEECOM 的 Goodix libfprint 后端不能直接使用。后续还需 Linux 独立的 Gatekeeper/HAT 签发、FTS 文件服务隔离和完整录入、匹配、保存、取消流程；给 TA 传入 Linux 目录本身不能证明存储已隔离。初始化也有持久化请求，因此原生客户端命令不能当作严格只读采集。[参考后端及协议研究](https://github.com/wrobelda/goodix-fp-spi-linux)

板载无线驱动没有取得有效 MAC 时会随机生成地址。启用 NetworkManager 的系统默认使用其标准 `stable` 地址策略，让同一连接配置在保留 NetworkManager 身份数据时跨重启保持地址；连接配置中明确填写的原厂地址优先。蓝牙初始化复用现有 MGMT 程序：优先读取只读 persist 的原厂公共地址，缺失时才从 SoC 身份派生稳定地址，不写原厂分区。

## 验证镜像的日志采集

`configurations/diagnostics.nix` 只由 GNOME 验证配置导入，集中设置无线调试、日志保存与 USB 采集；单独导入硬件模块不启用这些服务。内核包在原 BSP 补丁之后回移两项 ath12k 上游修复：保留 MSDU 扩展描述符中的 DMA 地址高位，以及检查发送统计数组的索引范围。补丁的来源记录在 `packages/kernel/` 对应文件中。

验证内核编入 ath12k 调试接口、trace 和固件转储；默认 `debug_mask=0x1072`，不自动打开逐包 trace。udev 在内核已经生成 devcoredump 后启动归档服务，只读快照并保存到 Linux 自己的状态目录。日志策略和归档服务均不修改原厂分区。现有 ramoops 与 UEFI 共用控制台内存布局，因此此处不改变它的地址和分配方式。

`configurations/usb-debug.nix` 复用固定 BSP 来源中的 NCM/ACM 脚本及 Type-C 就绪规则，不另建 gadget。ADSP 提供 GLINK/UCSI 后才允许 USB 服务绑定控制器；radio 在 ADSP 之后最多等待 USB 枚举 15 秒。USB 不可用时继续启动，无需连接电脑才能使用镜像。ACM 控制台依赖工作队列和 USB 中断，不能保证全局硬锁死后的输出。采集命令见[安装说明](install.md#通过-usb-采集故障)。

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
