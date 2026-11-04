# 安装 GNOME 验证系统

验证镜像用于已经安装 SunUEFI、已有 `sunuefi_esp` 和 `sunuefi_root` 的 piano。已有 ESP 必须保留 systemd-boot（`EFI/BOOT/BOOTAA64.EFI`）和 Debian 启动应用（`EFI/Piano/LinuxBoot.efi`）；后者会调用驻留核心加载 `EFI/Piano/stable/boot.img`，不要求实际系统是 Debian。

设备树按 `hardware.xiaomi.piano.memoryGiB` 选择已有依据的内存布局；SunUEFI 只修正运行时面板和 Gunyah 参数，不会替换内存表。16 GB 使用原厂基准，24 GB 使用当前实机已核对的改装布局。这里不更新固件、不创建或调整分区。

刷写 `sunuefi_root` 会替换该分区中的现有 Linux 系统和数据。先把要保留的文件备份到其他设备。Android 分区不在以下操作的写入范围内。

## 构建与校验

在 ARM64 Linux 构建机上，在项目目录运行：

```sh
nix build .#gnome-image
# 改装机可改用 .#gnome-24gb-image
(cd result && sha256sum -c SHA256SUMS)
```

输出：

| 文件 | 用途 |
| --- | --- |
| `root.sparse.img` | 用原厂 Fastboot 写入独立 root 分区 |
| `root.ext4.img` | 同一文件系统的原始 ext4 镜像 |
| `boot-files.tar` / `boot-files/` | 写入已有 ESP 的 Linux 内核、initrd、设备树和 `boot.img` |
| `manifest.json` / `SHA256SUMS` | 构建身份、容量和文件摘要 |

root 镜像默认 16 GiB，目标分区至少需要相同容量。initrd 在检查、挂载和扩容文件系统前，会核对 ext4 类型、`PIANOROOT` 标签和 `sunuefi_root` 分区名。首次启动只扩大这个独立 ext4 文件系统，不修改 GPT。

## 更新 Linux 启动文件

旧 Debian initramfs 不能直接启动 NixOS。必须把 root 镜像与本次构建的启动文件一起更新，保留 ESP 中其他文件。

在现有 Linux 中确认 ESP 的设备、分区名和文件系统标签：

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
sudo blkid /dev/disk/by-partlabel/sunuefi_esp
```

确认它是标签为 `SUNUEFI_ESP` 的 FAT 分区。将它挂载到 `/mnt/piano-esp`；如果已挂载，使用其现有挂载点。先把整个 `EFI/Piano/stable` 目录备份到平板之外，再复制本次构建的文件：

```sh
sudo mkdir -p /mnt/piano-esp
sudo mount /dev/disk/by-partlabel/sunuefi_esp /mnt/piano-esp
sudo test -f /mnt/piano-esp/EFI/BOOT/BOOTAA64.EFI
sudo test -f /mnt/piano-esp/EFI/Piano/LinuxBoot.efi
sudo cp -L result/boot-files/EFI/Piano/stable/{Image,initramfs,board.dtb} /mnt/piano-esp/EFI/Piano/stable/
sudo cp -L result/boot-files/EFI/Piano/stable/boot.img /mnt/piano-esp/EFI/Piano/stable/boot.img
sudo cp -L result/boot-files/{manifest.json,SHA256SUMS} /mnt/piano-esp/
sudo cp -L result/boot-files/loader/entries/debian.conf /mnt/piano-esp/loader/entries/debian.conf
sudo sync
sudo sh -c 'cd /mnt/piano-esp && sha256sum -c SHA256SUMS'
sudo umount /mnt/piano-esp
```

这些命令在项目目录执行。更新启动文件后，下一次选择 Linux 前还必须写入对应 root 镜像。

## 写入 root 镜像

回到 Android，从电脑通过 ADB 进入原厂 Fastboot。确认真实设备序列号、型号和目标分区容量后执行；不要使用设备名为 `SunUEFI-piano` 的 UEFI Fastboot：

```sh
adb devices
adb -s SERIAL reboot bootloader
fastboot devices
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar partition-size:sunuefi_root
fastboot -s SERIAL -S 128M flash sunuefi_root result/root.sparse.img
fastboot -s SERIAL reboot
```

将 `SERIAL` 替换为对应命令列出的真实序列号。在早期选择页进入 UEFI，再启动 Linux。登录账号为 `piano`，密码为 `piano123456`。

启动失败时，长按电源重启，在早期选择页按音量上回 Android。恢复原系统需要同时恢复它的 root 备份和配套启动文件；只还原 ESP 不能恢复已经覆盖的 root 数据。

## 后续更新

验证配置安装了外部启动文件更新钩子。正常在 NixOS 内执行 `nixos-rebuild boot` 时，钩子核对 `/boot` 确实是现有 SunUEFI ESP，再生成并校验 Linux 启动文件，最后替换 `boot.img`。它不安装或更新 UEFI、systemd-boot，也不修改 Android 启动分区。
