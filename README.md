# Xiaomi Pad 8 Pro / piano — NixOS

为小米平板 8 Pro（`piano`）提供可导入的 NixOS 硬件模块和 GNOME 验证镜像。通用模块不指定桌面、用户、根分区或引导器，内存容量通过一个选项指定。

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
    { hardware.xiaomi.piano.memoryGiB = 16; }
    ./configuration.nix
  ];
};
```

固件包含专有二进制，需要在自己的配置中允许该固件包：

```nix
nixpkgs.config.allowUnfreePredicate = pkg:
  builtins.elem (lib.getName pkg) [ "piano-firmware" "piano-fingerprint" ];
```

当前改装机将 `hardware.xiaomi.piano.memoryGiB` 设为 `24`。目前提供 16 GB 原厂基准和当前实机已核对的 24 GB 布局；8 GB、12 GB 及其他未取得设备树依据的容量会被拒绝，避免套用错误的内存范围。此选项不修改分区大小。

触摸屏默认只启用手指输入。需要使用笔时，设置 `hardware.xiaomi.piano.pen.enable = true;`，同时启用笔输入和笔的蓝牙配置；默认值为 `false`。

## 构建 GNOME 验证镜像

项目使用 `nixos-unstable`，精确提交由 `flake.lock` 固定。在 ARM64 Linux 构建机上，按内存容量选择一个构建命令：

```sh
nix build .#gnome-image
# 24 GB 改装机：
nix build .#gnome-24gb-image
```

从其他架构的机器连接已配置的 ARM64 Nix builder 时，使用完整输出名：

```sh
nix build .#packages.aarch64-linux.gnome-24gb-image
```

镜像固定为 `aarch64-linux`；仅评估配置不需要 ARM64 构建机：

```sh
nix flake check --all-systems --no-build
nix eval .#nixosConfigurations.piano-gnome.config.system.build.toplevel.drvPath
```

验证系统使用 GNOME、中文界面、Chromium、NetworkManager 和 IBus 拼音，自动登录 `nixos`，初始密码为 `nixos`，并启用 SSH。这些设置只属于验证配置，不会随硬件模块导入自己的系统。

一次构建会在同一个 `result/` 中同时生成 `root.ext4.img`、`root.sparse.img`、`esp.img` 和 `esp.sparse.img`，并提供统一的 `manifest.json` 和 `SHA256SUMS`。root 系统镜像与 512 MiB 的 ESP 启动镜像来自同一系统配置，可通过原厂 Fastboot 写入已有分区。ESP 包含 systemd-boot、匹配的 EFI-stub 内核、initrd 和设备树，复用支持标准 EFI 启动的 SunUEFI。安装后通过标准 `nixos-rebuild` 更新系统和启动文件，匹配的设备树随每代一起安装。刷写步骤与启动前提见 [安装](docs/install.md)。

## 目录

```text
flake.nix / flake.lock       导出接口和固定来源
modules/piano/              设备模块、启动顺序、音频与传感器
packages/                   内核、固件、设备树、BSP、Mesa 适配
configurations/gnome.nix     GNOME 验证环境
images/                     root、ESP 镜像和 Linux 启动文件打包
```

来源、维护边界和验证方法见 [开发说明](docs/development.md)。
