# 维护与验证

硬件配置、可替换的软件包和验证镜像分别维护。设备模块只设置硬件所需默认值；桌面、用户、语言和磁盘策略放在 `configurations/` 和 `images/`。内存容量统一由 `hardware.xiaomi.piano.memoryGiB` 控制；板级设备树覆盖、内存布局和绑定修正统一放在 SunUEFI 的 `linux/dts/`、`config/memory-layouts/` 及共享构建工具中；本仓库仅选择容量并调用它们。

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

initrd 只包含根文件系统所需驱动及其依赖，由标准 udev coldplug 自动加载；stage2 使用同一套普通 modalias 机制。设备树表达时钟、电源域、GPIO 和 IOMMU 关系，驱动通过延迟探测等待资源。本项目不再修改 `80-drivers.rules`、设置板级模块黑名单或用专用服务加载存储、显示、键盘、声卡和无线模块。未适配设备在共享设备树中禁用；继承的 CoreSight 追踪节点按 Linux AMBA 外设 ID 识别并禁用，避免寄存器探测阻塞启动。媒体节点由共享构建策略选择，保留 SunUEFI 其他发行版已有的媒体能力。

内核在 identity 映射附着前后检查实际 SMMU 路由与上下文；实际 DMA 请求设备的 `iommus` 或 `iommu-map` 配置失败时直接拒绝探测，不降级到无 IOMMU 的 DMA；PCI 主桥本身不使用描述下游请求设备的 `iommu-map`。控制器在启用 PHY 前通过标准 PCI 电源控制接口完成端点供电；供应者未就绪时由延迟探测等待。Adreno 的 GPU、GMU 通过标准延迟附着机制保留初始状态，在驱动分配缓冲区之前同步建立自己的分页域；附着失败会阻止对应驱动初始化。共享设备树归一化会移除 USB3 PHY 的空 `iommus` 列表，将不经过 IOMMU 与映射配置失败区分开。

蓝牙电源序列尚未就绪时保留 `-EPROBE_DEFER`；没有 OF compatible 的 RPMsg 通道使用标准通道别名加载驱动。CPU boost 在 Piano 的 SCMI cpufreq 驱动注册时默认启用，沿用原有 thermal 和 QoS 限制。MCA 是板载电源端点的唯一驱动，内核排除匹配同一 GLINK 端点的 BATTMGR；充电参数通过标准 modprobe 配置提供。

ASoC 处理声卡组件的延迟探测，DRM 管理显示、面板和背光，键盘驱动自行完成上电、固件与 HID 注册。保留的 `piano-adsp` 只在 native DSI 完成接管后启动 remoteproc，避免当前 ADSP 固件影响 bootloader 留下的显示电源；驱动和下游 GLINK/GPR 服务仍自动加载。触摸的常驻 THP 解码器继续提供 evdev 事件，在 SPI 驱动绑定后由 udev 启动。蓝牙缺失的本机公共地址由 BlueZ 启动前的标准 MGMT 操作补齐，USB configfs 与 Type-C 插拔继续由原有服务处理。

相机和视频设备沿用普通 modalias 与延迟探测。CAMSS 和 Iris 在内核中选择 DMA 映射域；不再由启动脚本修改 IOMMU group。`v4l2loopback` 随同一代内核构建，常驻 C 程序 `piano-camerad` 负责传感器曝光、白平衡、对焦和 ISP 输出，向 PipeWire 发布前后摄像头；应用关闭后停止采集。服务以 root/video 运行，控制 socket 只供 video 组访问。WirePlumber 隐藏内部 CAMSS 入口，避免同时出现原始 ISP 与对外摄像头。

FFmpeg 的硬件编解码补丁通过设备模块的 nixpkgs overlay 应用于 FFmpeg 7、9 的普通、headless、full 变体及默认别名，保留各包原有源码与构建选项。使用这些库的包得到同一套修复；自行内置编解码库的应用仍由其自身构建决定。当前媒体设备树会同时启用 CAMCC、CAMBIST；同 SoC 的显示灭屏复位报告尚无确定驱动修复，不能用仅枚举出摄像头来代替采集与灭屏恢复验证。[上游原始报告](https://lists.openwall.net/linux-kernel/2026/10/12/599)

## 显示、传感器与无线身份

设备树将遗留 MMSS 节点转换为标准 SM8750 interconnect provider，并为 MDSS 提供 `mdp0-mem` 和 `cpu-cfg` 路径。DPU 沿父 MDSS 取得这些路径，通过现有 RPMh/BCM 驱动申请显示带宽。显示仍提供七档固定刷新率。连续 VRR 还需要面板允许的逐帧周期范围、双 DSI AVR 同步及 DRM 驱动实现；原厂 P81 的固定 DFPS 列表不能替代这些条件：原厂 120/60、90/50/48/30、144 分属三组时序和 DDIC 配置，不能把全局最低的 30 Hz 当作 120 Hz 时序的连续下限。[原厂 P81 配置](https://github.com/MiCode/vendor_qcom_opensource_display-devicetree/blob/cc4e65ad4bd54e26b60f5a8ee76bbc3cca6821b9/display/dsi-panel-p81-35-02-0b-dualdsi-dsc-lcd-video.dtsi)

设备模块通过 `/etc/machine-info` 声明真实 `CHASSIS=tablet`，保留 Gunyah 的虚拟化信息，避免 GNOME 把平板按虚拟机电源策略关机。启用 GNOME 时，`modules/piano/gnome.nix` 为现有 Mutter、Shell、Settings Daemon 和控制中心补齐“锁定屏幕”电源键动作，默认用于用户会话和 GDM：亮屏时短按锁屏灭屏，熄屏时短按唤醒且不解锁。Shell 在按下时记录显示状态，松开时由现有 Power daemon 统一完成锁屏与 DPMS，防止自动唤醒、按键松开和锁屏动画互相覆盖。设置中仍可选择原有动作，不新增电源键守护程序。更新后需要完整的新 GNOME 会话，不能用旧 Shell 的热更新代替。

系统挂起独立于屏幕灭屏。PCIe PHY 的 `piano_skip_bcr` 同时约束初始化、错误回收和退出；PMIC GLINK altmode worker 使用上游的 freezable workqueue 修复，避免在设备恢复前访问 Type-C 硬件。该修复不覆盖 UCSI 到 DWC3 的同步角色通知路径。调试闹钟应按 `/sys/class/rtc/rtc*/name` 选择 `rtc-pm8xxx` 对应设备；清醒状态的闹钟中断不能证明 deep 挂起能恢复。[上游 GLINK 修复](https://github.com/torvalds/linux/commit/c7c56b6ec077cb96657494b8c18c2c78625035b1)

传感器使用 FastRPC、libssc 和标准 SensorProxy。导入程序读取 GPT 活动槽位，通过 liblp 校验 super 元数据，再建立只读 ODM/vendor 映射、只读挂载 persist 并复制同机配置与校准数据。服务按 ADSP、配置导入、sensors PD、SensorProxy 的顺序启动。`hardware.sensor.iio.enable = false` 关闭整条 SSC 服务链；板载 SSC 不使用内核未提供的 `hid-sensor-hub`，只对该 initrd 模块作逐项排除，其余缺失模块仍会阻止构建。

GNOME 负责旋转显示和触控、笔输入坐标；不另设旋转守护程序。自动旋转需要未锁定方向、有效加速度计和内置屏幕，并遵循 GNOME 的触摸模式策略：Nanosic 键盘 MCU 的持久输入设备把 `keyboard_attached` 转为标准 `SW_TABLET_MODE`，取下键盘为平板模式，装回后退出。键盘和触控板的 HID 设备移除时，这个模式开关仍保留。

指纹模块注册 QTEE/UIO 控制接口，提供 `piano-fingerprint-ctl` 的现有初始化和事件诊断命令。签名 TA 与模型按清单校验，供客户端读取的副本保留未压缩形式，不改变其他内核固件的压缩策略。GNOME 指纹录入和解锁尚未接入：Piano 的 `gfpia` 需要真实 HAT 验签及 QTEE 协议支持，现有面向旧 QSEECOM 的 Goodix libfprint 后端不能直接使用。后续还需 Linux 独立的 Gatekeeper/HAT 签发、FTS 文件服务隔离和完整录入、匹配、保存、取消流程；给 TA 传入 Linux 目录本身不能证明存储已隔离。初始化也有持久化请求，因此原生客户端命令不能当作严格只读采集。[参考后端及协议研究](https://github.com/wrobelda/goodix-fp-spi-linux)

板载无线驱动没有取得有效 MAC 时会随机生成地址。启用 NetworkManager 的系统默认使用其标准 `stable` 地址策略，让同一连接配置在保留 NetworkManager 身份数据时跨重启保持地址；连接配置中明确填写的原厂地址优先。蓝牙初始化复用现有 MGMT 程序：优先读取只读 persist 的原厂公共地址，缺失时才从 SoC 身份派生稳定地址，不写原厂分区。

## 验证镜像的日志采集

`configurations/diagnostics.nix` 只由 GNOME 验证配置导入，集中设置无线调试、日志保存与 USB 采集；单独导入硬件模块不启用这些服务。内核包在原 BSP 补丁之后保留 ath12k 的两项上游发送修复和专用 DMA 池，并加入 identity 附着检查、蓝牙电源延迟探测、RPMsg 别名及 CPU boost 默认策略。补丁均保存在 `packages/kernel/patches/`，内核构建只引用真正使用的补丁与配置片段，设备树和 UEFI 改动不触发无关重编。

验证内核编入 ath12k 调试接口、trace 和固件转储；默认 `debug_mask=0x1072`，不自动打开逐包 trace。udev 在内核已经生成 devcoredump 后启动归档服务，只读快照并保存到 Linux 自己的状态目录。日志策略和归档服务均不修改原厂分区。现有 ramoops 与 UEFI 共用控制台内存布局，因此此处不改变它的地址和分配方式。

`configurations/usb-debug.nix` 复用固定 BSP 来源中的 NCM/ACM 脚本及 Type-C 就绪规则，不另建 gadget。ADSP 提供 GLINK/UCSI 后才允许 USB 服务绑定控制器；无线按自身硬件依赖自动启动，不等待 USB。USB 不可用时其他硬件仍正常探测，无需连接电脑才能使用镜像。ACM 控制台依赖工作队列和 USB 中断，不能保证全局硬锁死后的输出。采集命令见[安装说明](install.md#通过-usb-采集故障)。

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
