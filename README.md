# Xiaomi Pad 8 Pro / piano — NixOS

为小米平板 8 Pro（`piano`）提供可导入的 NixOS 硬件模块和 GNOME 验证镜像。通用模块不指定桌面、用户、根分区或引导器。

项目复用已锁定的 Piano Linux 驱动、固件和板级初始化代码，保留显示、触摸、无线及音频的启动顺序和 DMA 检查。nixpkgs 由 `flake.lock` 固定；其他源码由使用它的软件包以提交和 SHA256 固定，多个包共用的 SunUEFI 来源放在 `packages/sunuefi-source.nix`。不构建 UEFI 固件或 Android 模块。

## 导入设备模块

在自己的 flake 中添加输入：

```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
inputs.piano.url = "path:/home/cryolitia/xiaomi-piano-nixos";
inputs.piano.inputs.nixpkgs.follows = "nixpkgs";
```

把模块加入目标系统：

```nix
nixosConfigurations.tablet = nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    piano.nixosModules.piano
    ./configuration.nix
  ];
};
```

固件和面板校准包含专有数据，需要在自己的配置中允许这些包：

```nix
nixpkgs.config.allowUnfreePredicate = pkg:
  builtins.elem (lib.getName pkg) [ "piano-firmware" "piano-fingerprint" ];
```

设备树使用统一的工厂基准，实际 RAM 范围和 DDR 信息由 SunUEFI 根据本次 ABL 引导数据回填。使用前先按[安装说明](docs/install.md)更新具备完整 EFI 内存图和标准设备树内存修正的 UEFI 核心；更新 NixOS 源码或 ESP 不会替代固件更新。

触摸屏默认只启用手指输入。需要使用笔时，设置 `hardware.xiaomi.piano.pen.enable = true;`，同时启用笔输入和笔的蓝牙配置；默认值为 `false`。

启用 GNOME 后，可在“设置 → 显示”开启 HDR。Mutter 使用标准 DRM 的 PQ／BT.2020 输出，内核按面板加载随固件包提供的原厂校准并完成十位输出转换；合成与色调映射由 Mutter 处理。实现与亮度边界见[开发说明](docs/development.md#显示传感器与无线身份)。

## 构建 GNOME 验证镜像

项目使用 `nixos-unstable`，精确提交由 `flake.lock` 固定。在 ARM64 Linux 构建机上运行：

```sh
nix build .#gnome-image
```

从其他架构的机器连接已配置的 ARM64 Nix builder 时，使用完整输出名：

```sh
nix build .#packages.aarch64-linux.gnome-image
```

镜像固定为 `aarch64-linux`；仅评估配置不需要 ARM64 构建机：

```sh
nix flake check --all-systems --no-build
nix eval .#nixosConfigurations.piano-gnome.config.system.build.toplevel.drvPath
```

验证系统使用 GNOME、中文界面、Chromium、NetworkManager 和 IBus 拼音，自动登录 `nixos`，初始密码为 `nixos`，并启用 SSH。这些设置只属于验证配置，不会随硬件模块导入自己的系统。

一次构建在同一个 `result/` 中生成 `root.sparse.img` 和 `esp.sparse.img` 两个稀疏镜像，可通过 SunUEFI 引导助手或原厂 Fastboot 写入已有分区。ESP 为 512 MiB，包含 systemd-boot、匹配的 EFI-stub 内核、initrd 和设备树；root 按系统实际大小生成，首次启动时自动扩展到现有分区大小。两份镜像来自同一系统配置，复用支持标准 EFI 启动的 SunUEFI。安装后通过标准 `nixos-rebuild` 更新系统和启动文件，匹配的设备树随每代一起安装。刷写步骤与启动前提见 [安装](docs/install.md)。

## 目录

```text
flake.nix / flake.lock       导出接口和固定来源
modules/piano/              设备模块、启动顺序、音频与传感器
packages/                   内核、固件、设备树、BSP、Mesa 适配
configurations/gnome.nix     GNOME 验证环境
images/                     root、ESP 镜像和 Linux 启动文件打包
```

来源、维护边界和验证方法见 [开发说明](docs/development.md)。
