# 维护与验证

硬件配置、可替换的软件包和验证镜像分别维护。设备模块只设置硬件所需默认值；桌面、用户、语言和磁盘策略放在 `configurations/` 和 `images/`。板级设备树覆盖和绑定修正统一放在 SunUEFI 的 `linux/dts/` 及共享构建工具中，本仓库调用这些工具生成统一的工厂基准设备树。实际 RAM 范围与 DDR 元数据由 SunUEFI 使用本次 ABL 的引导数据动态回填。

从旧配置迁移时，删除 `hardware.xiaomi.piano.memoryGiB` 设置；将旧的 `gnome-24gb-image` 构建名改为 `gnome-image`，`piano-24gb-gnome` 配置名改为 `piano-gnome`。已有 NixOS 分区不需要为此重建。

## 来源

`flake.lock` 只固定 nixpkgs。内核、固件、BSP 和 Mesa 等包在各自定义中获取固定提交与 SHA256 的源码；多个包共用的 SunUEFI 来源统一维护在 `packages/sunuefi-source.nix`：

- nixpkgs 提供 NixOS、GNOME、systemd-boot 和常规用户空间。
- Linux 7.3.3 基线与 SunUEFI 的有序补丁共同组成 Piano 内核；补丁按原 `series.json` 的 SHA256 校验，NixOS 只额外保留默认启用 CPU boost 的 SCMI 策略补丁。
- SunUEFI 提供经过适配的设备树覆盖、BSP 代码、UCM、固件覆盖清单，以及稀疏镜像打包工具。
- debian-piano 提供板级初始化和音频拓扑构建来源；piano-firmware 提供设备固件。
- piano-mesa 提供 A830v1 设备 ID 补丁；AudioReach 提供音频拓扑源码。

本仓库的 Nix 配置使用 MIT 许可。被引用的内核、BSP、字体及固件分别遵循其原许可；专有固件不因通过 Nix 获取而改变许可。包会保留相关许可文件，不将构建产物提交到仓库。

## 启动与硬件边界

启动链为 SunUEFI → systemd-boot → Linux EFI stub：systemd-boot 按标准 BLS 启动项加载匹配的内核、initrd 和设备树，命令行指向对应的 NixOS 系统。设备树输入统一使用工厂基准；SunUEFI 在 SEC 阶段依据本次 ABL 的内存表建立 EFI 描述，并通过标准设备树修正协议回填 RAM 范围、DDR 元数据、面板和 Gunyah 参数。内核 EFI 启动按 EFI 内存图接收 RAM，固件在 `ExitBootServices` 时完成硬件退出。静态设备树和编译检查均不能替代实际容量与高地址内存验证。

ESP 使用 512 MiB FAT32、4096 字节逻辑扇区和 `SUNUEFI_ESP` 标签，目标是已有的 `sunuefi_esp` 分区。`loader/entries/nixos-*.conf` 使用 `linux`、`initrd`、`devicetree` 和 `options`；载荷使用 nixpkgs systemd-boot 模块的 `/EFI/nixos/<store 名称>-<文件名>.efi` 平铺布局。初始离线 ESP 从系统的 `boot.json` 及其设备树扩展生成入口；后续更新、代际选择和清理完全使用 NixOS 自带的 systemd-boot 模块。本项目不构建 UEFI 固件或 Android 模块。

验证镜像统一通过 `gnome-image` 构建，一个 `result/` 只提供 `root.sparse.img` 和 `esp.sparse.img`。root 复用 nixpkgs `make-ext4-fs.nix` 生成的文件系统，按实际内容确定大小，首次启动时扩展到已有分区；打包阶段不再复制 raw root 或二次调整容量。两份镜像统一使用 `img2simg` 转换。启动载荷和读回校验所需清单只作为内部构建输入，ESP raw 文件在临时目录生成。镜像打包保留启动载荷的基本架构和格式检查，读回验证 FAT32 中的启动文件，并将 ESP 稀疏镜像展开后逐字节比较；运行时由标准模块消费每代 bootspec，`nixos-rebuild` 会连同设备树一起更新启动文件。

标准 EFI 启动需要 SunUEFI 提供完整 RAM/保留区的 EFI 内存描述、设备树修正协议和标准内核退出处理，systemd-boot 的音量键导航还需要扩展输入协议。所需核心由固定来源对应的 SunUEFI 引导助手交付，更新 NixOS 源码或 ESP 不会替代固件更新。使用前的固件更新步骤见[安装说明](install.md)。内核、initrd 和 DTB 独立加载，受 FAT32 单文件及 ESP 容量约束；不再使用 Android boot 容器的 16/128 MiB 限制。验证配置保留完整的 nixos-unstable systemd initrd 和 XZ 压缩。

initrd 只包含根文件系统所需驱动及其依赖，由标准 udev coldplug 自动加载；stage2 使用同一套普通 modalias 机制。设备树表达时钟、电源域、GPIO 和 IOMMU 关系，驱动通过延迟探测等待资源。本项目不再修改 `80-drivers.rules`、设置板级模块黑名单或用专用服务加载存储、显示、键盘、声卡和无线模块。未适配设备在共享设备树中禁用；继承的 CoreSight 追踪节点按 Linux AMBA 外设 ID 识别并禁用，避免寄存器探测阻塞启动。媒体节点由共享构建策略选择，保留 SunUEFI 其他发行版已有的媒体能力。

内核在 identity 映射附着前后检查实际 SMMU 路由与上下文；实际 DMA 请求设备的 `iommus` 或 `iommu-map` 配置失败时直接拒绝探测，不降级到无 IOMMU 的 DMA；PCI 主桥本身不使用描述下游请求设备的 `iommu-map`。控制器在启用 PHY 前通过标准 PCI 电源控制接口完成端点供电；供应者未就绪时由延迟探测等待。Adreno 的 GPU、GMU 通过标准延迟附着机制保留初始状态，在驱动分配缓冲区之前同步建立自己的分页域；附着失败会阻止对应驱动初始化。共享设备树归一化会移除 USB3 PHY 的空 `iommus` 列表，将不经过 IOMMU 与映射配置失败区分开。

蓝牙电源序列尚未就绪时保留 `-EPROBE_DEFER`；没有 OF compatible 的 RPMsg 通道使用标准通道别名加载驱动。CPU boost 在 Piano 的 SCMI cpufreq 驱动注册时默认启用，沿用原有 thermal 和 QoS 限制。MCA 是板载电源端点的唯一驱动，内核排除匹配同一 GLINK 端点的 BATTMGR；充电参数通过标准 modprobe 配置提供。

默认启用 MiPPS 认证与 SC8541 电荷泵直充，由内核按 PPS 电源能力、电芯温度和电压决定是否进入直充。直充输入电流目标上限为 4 A，两电芯合计充电电流目标上限为 8 A，仍受温控和电源能力限制。挂起先确认电荷泵停止，恢复后重新检查充电条件；拔线会清除固件认证状态。内核同时提供电荷泵硬件看门狗和软件超时保护，无需额外用户态服务。

ASoC 处理声卡组件的延迟探测，DRM 管理显示、面板和背光，键盘驱动自行完成上电、固件与 HID 注册。保留的 `piano-adsp` 只在 native DSI 完成接管后启动 remoteproc，避免当前 ADSP 固件影响 bootloader 留下的显示电源；驱动和下游 GLINK/GPR 服务仍自动加载。手指触摸由内核直接提供标准输入事件，不安装或启动 THP 用户空间读取者。只有 `hardware.xiaomi.piano.pen.enable = true` 时，才构建笔程序并由 SPI 绑定事件启动笔输入服务；服务保留校准解码与蓝牙配置，udev 将原生触屏和虚拟笔归入同一 libinput 设备组。蓝牙使用内核注册的本机地址，USB configfs 与 Type-C 插拔继续由原有服务处理。

相机和视频设备沿用普通 modalias 与延迟探测。CAMSS 和 Iris 在内核中选择 DMA 映射域；不再由启动脚本修改 IOMMU group。`v4l2loopback` 随同一代内核构建，常驻 C 程序 `piano-camerad` 负责传感器曝光、白平衡、对焦和 ISP 输出，向 PipeWire 发布前后摄像头；应用关闭后停止采集。服务以 root/video 运行，控制 socket 只供 video 组访问。WirePlumber 隐藏内部 CAMSS 入口，避免同时出现原始 ISP 与对外摄像头。

相机包直接构建共享的 C/Make 与 Rust 全幅转换代码。后摄支持 3840×2160/60 fps；8160×6120 全幅 RAW10 经软件转换输出，当前平板约 0.4 fps。`piano-camera-ctl capture rear --flash --output photo.jpg` 提供后摄 PIX 模式的同步 JPEG 拍照；前摄和全幅 RDI 不接受闪光请求，普通视频应用不会自动调用该功能。完整模式表与时序限制见[共享相机说明](https://github.com/Cryolitia-Forks/Project-SunUEFI/blob/main/docs/devel/hardware/camera-controls.md)。

SM8750 的 TFE PIX 驱动按 256 字节对齐行跨度，保证 Y、UV 平面和硬件地址单位一致；虚拟摄像头报告当前画面的裁剪边界和默认尺寸。独立 PipeWire 包回补首选格式转换、稳定重协商及缓冲区回收锁顺序修复，并在交给 GStreamer 下游前复制借用的 `MemPtr` 数据，避免格式切换移除映射后仍访问旧帧；FD-backed 缓冲区保留共享路径。设备模块通过标准 `GST_PLUGIN_PATH_1_0` 选用修复后的 GStreamer 插件，系统 PipeWire、GTK 和应用仍使用 nixpkgs 的原始包。

带硬件编解码补丁的 FFmpeg 作为独立包导出，用 `nix build .#ffmpeg` 构建，或用 `nix shell .#ffmpeg` 临时调用。本项目不将它加入系统环境，也不覆盖 nixpkgs 的 FFmpeg；其他应用沿用原版依赖。当前媒体设备树会同时启用 CAMCC、CAMBIST；同 SoC 的显示灭屏复位报告尚无确定驱动修复，不能用仅枚举出摄像头来代替采集与灭屏恢复验证。[上游原始报告](https://lists.openwall.net/linux-kernel/2026/10/12/599)

## 显示、传感器与无线身份

GNOME 的内屏 HDR 使用标准 DRM 输出路径。Mutter 根据内核的 EDID／DisplayID、BT.2020 色彩空间和 HDR metadata 属性选择 PQ 输出，负责应用色彩转换、线性合成与面板峰值范围内的色调映射。DPU 使用 IGCv5 解码 PQ 或 Gamma 2.2，经 Gamut v4.3 完成 BT.2020 到 P3-D65 及原厂面板校准，再用 GCv2 转成面板的原生编码；DSI／DSC 保持十位传输。

两份面板校准由 SunUEFI 的 `vendor/firmware/piano-display/manifest.json` 固定来源和摘要，通过固件包安装到 `lib/firmware/qcom/sm8750/piano-{boe,csot}-display.bin`。内核按实际面板 compatible 加载并校验数据，成功后才开放 HDR 属性；缺失或无效时继续普通 SDR 显示。峰值和黑位来自原厂模型，不是逐台光度测量。

GNOME 沿用 nixpkgs 的 Mutter 和显示设置，不再安装面板专用 ICC 或覆盖其输出转换。显示亮度、HDR 参考白和 SDR 内容亮度使用标准 Mutter 策略；硬件输出校准不会接管合成器的色调映射。切换内核后应检查 HDR 开关、灰阶与彩色图、窗口和全屏切换、亮度及参考白调整，并保存活动 DRM 属性和日志；旧软件转换路径的测试结果不代表当前路径已通过同样检查。

设备树将遗留 MMSS 节点转换为标准 SM8750 interconnect provider，并为 MDSS 提供 `mdp0-mem` 和 `cpu-cfg` 路径。DPU 沿父 MDSS 取得这些路径，通过现有 RPMh/BCM 驱动申请显示带宽。显示仍提供七档固定刷新率。连续 VRR 还需要面板允许的逐帧周期范围、双 DSI AVR 同步及 DRM 驱动实现；原厂 P81 的固定 DFPS 列表不能替代这些条件：原厂 120/60、90/50/48/30、144 分属三组时序和 DDIC 配置，不能把全局最低的 30 Hz 当作 120 Hz 时序的连续下限。[原厂 P81 配置](https://github.com/MiCode/vendor_qcom_opensource_display-devicetree/blob/cc4e65ad4bd54e26b60f5a8ee76bbc3cca6821b9/display/dsi-panel-p81-35-02-0b-dualdsi-dsc-lcd-video.dtsi)

GNOME 的节能、平衡、性能三档由 NixOS 原生的 TuneD 服务及其 PPD 兼容服务提供，CPU/GPU 策略直接复用锁定 SunUEFI 源码中的 `piano-*` profile。没有已保存选择时回退到平衡，后续保留用户选择。三档调整 CPU/GPU 频率上限，不代替系统挂起。

设备模块通过 `/etc/machine-info` 声明真实 `CHASSIS=tablet`，保留 Gunyah 的虚拟化信息，避免 GNOME 把平板按虚拟机电源策略关机。`modules/piano/gnome.nix` 将用户会话和 GDM 登录页的电源键动作设为 GNOME 原生的 `suspend`。短按电源键通过 logind 挂起系统；仅熄屏而系统仍运行时也执行这一动作。成功恢复后，GNOME 会暂时忽略电源键，避免唤醒时上报的同次按键再次触发挂起。

同一模块按外部供电区分自动挂起策略：插电时 `sleep-inactive-ac-type=nothing`，保留原有的自动熄屏和锁屏时间；电池供电时 `sleep-inactive-battery-type=suspend`。logind 的 `HandleLidSwitchExternalPower=lock` 让插电合盖只锁屏，`HandleLidSwitch=suspend` 保留电池合盖挂起。`MemorySleepMode=deep` 指定真正挂起时的内存休眠方式；电源键和菜单发起的显式挂起仍然有效。

合盖使用 GNOME 和 logind 的标准路径。启动或显示配置变化后的短暂保护窗口，以及连接外接显示器时的合盖抑制均保持原样。GDM 登录页不接收 logind 的合盖锁屏广播，插电合盖后仍按其普通闲置时间熄屏。

系统挂起独立于屏幕灭屏。PCIe 在 PHY 和控制器时钟均已开启后完成 RC／PHY 复位，再启动 PHY 并配置 PARF。挂起时先停止 PHY，再撤销控制器、PHY 和端点资源；PMIC GLINK altmode worker 使用上游的 freezable workqueue 修复，避免在设备恢复前访问 Type-C 硬件。该修复不覆盖 UCSI 到 DWC3 的同步角色通知路径。调试闹钟应按 `/sys/class/rtc/rtc*/name` 选择 `rtc-pm8xxx` 对应设备；清醒状态的闹钟中断不能证明 deep 挂起能恢复。[上游 GLINK 修复](https://github.com/torvalds/linux/commit/c7c56b6ec077cb96657494b8c18c2c78625035b1)

传感器使用 FastRPC、libssc 和标准 SensorProxy。导入程序读取 GPT 活动槽位，通过 liblp 校验 super 元数据，再建立只读 ODM/vendor 映射、只读挂载 persist 并复制同机配置与校准数据。服务按 ADSP、配置导入、sensors PD、SensorProxy 的顺序启动。`hardware.sensor.iio.enable = false` 关闭整条 SSC 服务链；板载 SSC 不使用内核未提供的 `hid-sensor-hub`，只对该 initrd 模块作逐项排除，其余缺失模块仍会阻止构建。

GNOME 负责旋转显示和触控、笔输入坐标；不另设旋转守护程序。自动旋转需要未锁定方向、有效加速度计和内置屏幕，并遵循 GNOME 的触摸模式策略：Nanosic 键盘 MCU 的持久输入设备把 `keyboard_attached` 转为标准 `SW_TABLET_MODE`，取下键盘为平板模式，装回后退出。键盘和触控板的 HID 设备移除时，这个模式开关仍保留。

键盘背光和麦克风指示灯通过 LED class 随键盘连接状态注册和移除，驱动保留请求亮度，包括关闭状态。GNOME 设置守护进程 50.1 回补标准 UPower 键盘背光能力的热插拔刷新：设备消失时把背光标为不可用，接回后重新读取实际范围和亮度，由 GNOME Shell 的现有控件更新显示。

指纹通过原生 QTEE 客户端和 libfprint 平台驱动接入标准 fprintd、GNOME 账户设置及 PAM，支持 Linux 独立录入、持久保存、验证、删除和取消。签名 TA 与模型按共享清单校验，供客户端读取的副本保留未压缩形式。原生实现使用独立的 Gatekeeper UID、凭据和模板，状态保存在 `/var/lib/piano-goodix/<LinuxUID>/`，不读取或复制 Android 指纹模板。独立凭据的建立与授权录入使用原厂 Keymaster 和真实 HAT；RPMB 与 Android 共用，Linux UID 隔离不代表独立的物理安全存储。硬件访问由标准 fprintd 管理，GNOME 验证配置关闭 SSH 的指纹认证，保留密码登录。协议和存储边界见[共享指纹实现说明](https://github.com/Cryolitia-Forks/Project-SunUEFI/blob/main/docs/devel/hardware/led-ir-fingerprint.md)。

板载无线驱动没有取得有效 MAC 时会随机生成地址。启用 NetworkManager 的系统默认使用其标准 `stable` 地址策略，让同一连接配置在保留 NetworkManager 身份数据时跨重启保持地址；连接配置中明确填写的原厂地址优先。蓝牙公共地址由 UEFI 从只读原厂数据取得，经标准 `local-bd-address` 设备树属性交给内核；原厂地址不可用时，固件可从 SoC 身份派生稳定地址。内核通过标准接口将地址提供给 BlueZ，Linux 不再读取 persist 或通过 MGMT 改写控制器地址。

## 验证镜像的日志采集

`configurations/diagnostics.nix` 只由 GNOME 验证配置导入，集中设置无线调试、日志保存与 USB 采集；单独导入硬件模块不启用这些服务。ath12k 发送修复与 DMA 池、IOMMU 附着检查、蓝牙电源延迟探测、RPMsg 别名、PCIe 复位和 GLINK 挂起修复均由 SunUEFI 的有序内核补丁提供。NixOS 的 `packages/kernel/patches/` 只保留 `cpufreq-scmi-piano-boost-default.patch`，用于默认启用 CPU boost。内核构建只引用真正使用的补丁与配置片段，设备树和 UEFI 改动不触发无关重编。

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
nix eval .#nixosConfigurations.piano-gnome.config.system.build.pianoImage.drvPath
nix build .#kernel
nix build .#gnome-image
```

完整镜像构建需要原生或远端 `aarch64-linux` builder。x86_64 主机上的评估通过，不能替代 ARM64 编译或实机启动。首次上机应确认显示、触摸、键盘、无线、蓝牙、音频、充电及挂起恢复，并保存实际镜像 SHA256 和日志。

升级 nixpkgs 时更新 `flake.lock`；升级其他来源时修改对应软件包的 fetch 定义，SunUEFI 共用来源只改一处。随后核对内核版本、补丁摘要、设备树处理、固件协议版本和 BSP 源码转换。所有配置都从同一包集取得内核和模块，不能混用旧 ESP 的内核与新 root 中的模块。
