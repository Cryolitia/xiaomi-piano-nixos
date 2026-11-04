# 安装 GNOME 验证系统

验证镜像用于已经安装 SunUEFI、已有 `sunuefi_esp` 和 `sunuefi_root` 的 piano。启动镜像（ESP）包含 systemd-boot、Linux 启动应用、内核、initrd 和设备树；系统镜像（root）包含 NixOS。首次安装需要写入同一次构建的两份镜像。

设备树按 `hardware.xiaomi.piano.memoryGiB` 选择已有依据的内存布局。16 GB 使用原厂基准，24 GB 使用当前实机已核对的改装布局；SunUEFI 只修正运行时面板和 Gunyah 参数，不会替换内存表。以下步骤写入已有的两个独立分区，不创建或调整分区，不刷写 Android 启动分区。

## 构建与校验

在 ARM64 Linux 构建机的项目目录运行：

```sh
nix build .#gnome-image
# 24 GB 改装机使用 .#gnome-24gb-image
(cd result && sha256sum -c SHA256SUMS)
```

其他架构的电脑需要配置 ARM64 Nix builder，并使用完整输出名，例如 `nix build .#packages.aarch64-linux.gnome-24gb-image`。

| 文件 | 用途 |
| --- | --- |
| `esp.sparse.img` | 用原厂 Fastboot 写入 `sunuefi_esp` |
| `esp.img` | 同一启动文件系统的原始 FAT32 镜像 |
| `root.sparse.img` | 用原厂 Fastboot 写入 `sunuefi_root` |
| `root.ext4.img` | 系统分区的原始 ext4 镜像 |
| `boot-files.tar` / `boot-files/` | 更新已有 ESP 中的 Linux 载荷 |
| `manifest.json` / `SHA256SUMS` | 构建身份、容量和文件摘要 |

ESP 镜像为 512 MiB，使用 4096 字节逻辑扇区和 `SUNUEFI_ESP` 标签。root 镜像默认 16 GiB。目标分区分别至少需要相同容量；容量不足时应先停止，不能将镜像截短。

只构建启动镜像时，可运行 `nix build .#esp-image` 或 `nix build .#esp-24gb-image`，输出为两种 ESP 镜像及清单、摘要。它们必须与已经安装的 root 使用相同的 NixOS generation；从 Debian 首次切换时应使用上面的整套输出。

## 备份现有系统

刷写会覆盖整个 ESP 和 root，包括原有 Linux 系统、文件和启动配置。先在 Android 中确认这两个分区均未挂载，把整分区备份到电脑，并另行保存需要保留的个人文件。电脑需要能容纳两个分区的完整备份。

以下命令在电脑执行，需要 Android 已有 root。先用 `adb devices` 查到序列号，将所有命令中的 `SERIAL` 替换为真实序列号：

```sh
adb devices
adb -s SERIAL shell 'su -c "blockdev --getsize64 /dev/block/by-name/sunuefi_esp"'
adb -s SERIAL shell 'su -c "blockdev --getsize64 /dev/block/by-name/sunuefi_root"'
adb -s SERIAL exec-out 'su -c "dd if=/dev/block/by-name/sunuefi_esp bs=4194304 2>/dev/null"' > piano-esp-backup.img
adb -s SERIAL exec-out 'su -c "dd if=/dev/block/by-name/sunuefi_root bs=4194304 2>/dev/null"' > piano-root-backup.img
stat -c '%n %s' piano-esp-backup.img piano-root-backup.img
sha256sum piano-esp-backup.img piano-root-backup.img > piano-backup.SHA256SUMS
```

核对 `stat` 显示的备份字节数分别等于先前 `blockdev` 输出的分区容量。备份不完整时不要继续刷写。

## 写入启动镜像和系统镜像

从 Android 进入原厂 Fastboot，确认型号和两个目标分区的容量。不要使用设备名为 `SunUEFI-piano` 的 UEFI Fastboot。

```sh
adb -s SERIAL reboot bootloader
fastboot devices
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar partition-size:sunuefi_esp
fastboot -s SERIAL getvar partition-size:sunuefi_root
```

`product` 应为 `piano`。ESP 至少需要 `0x20000000` 字节（512 MiB）；默认 root 至少需要 `0x400000000` 字节（16 GiB）。确认后，在项目目录写入同一 `result` 中的两份镜像，全部成功后再重启：

```sh
fastboot -s SERIAL -S 128M flash sunuefi_root result/root.sparse.img
fastboot -s SERIAL -S 128M flash sunuefi_esp result/esp.sparse.img
fastboot -s SERIAL reboot
```

在早期选择页进入 UEFI，再启动 Linux。系统自动登录 `piano`，密码为 `piano123456`。initrd 在检查、挂载和扩容文件系统前，会核对 ext4 类型、`PIANOROOT` 标签和 `sunuefi_root` 分区名；首次启动只扩大该 ext4 文件系统，不修改 GPT。

启动失败时，长按电源重启，在早期选择页按音量上回 Android。恢复原 Linux 系统需要通过原厂 Fastboot 分别恢复完整 root 备份和 ESP 备份；只恢复 ESP 不能恢复已经覆盖的 root 数据。

## 后续更新

验证配置安装了外部启动文件更新钩子。在 NixOS 内执行 `nixos-rebuild boot` 时，钩子核对 `/boot` 确实是现有 SunUEFI ESP，再生成并校验 Linux 启动文件，最后替换 `boot.img`。它不更新 UEFI 固件、systemd-boot 或 Android 启动分区。

需要从其他 Linux 手工更新时，`boot-files` 提供 `EFI/Piano/stable/` 中的四个 Linux 载荷文件及启动条目 `loader/entries/debian.conf`。将这些文件更新到已挂载的 ESP，保留现有 `EFI/BOOT/BOOTAA64.EFI`、`EFI/Piano/LinuxBoot.efi` 和其他文件，最后替换 `boot.img`；更新后核对摘要并卸载 ESP。新的启动文件必须与已安装或即将写入的 root 匹配。
