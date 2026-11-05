# 安装 GNOME 验证系统

验证镜像用于已经安装 SunUEFI、已有 `sunuefi_esp` 和 `sunuefi_root` 的 piano。启动镜像（ESP）包含 systemd-boot、EFI-stub 内核、initrd 和设备树；系统镜像（root）包含 NixOS。首次安装需要写入同一次构建的两份镜像。

设备树按 `hardware.xiaomi.piano.memoryGiB` 选择已有依据的内存布局。16 GB 使用原厂基准，24 GB 使用当前实机已核对的改装布局；systemd-boot 加载这份设备树，SunUEFI 通过标准修正协议补充本次启动的面板和 Gunyah 参数。启动前需安装支持标准 EFI 内存图、设备树修正和内核退出流程的 SunUEFI；只有 128 MiB raw 启动支持的旧固件仍需更新。以下步骤写入已有的两个独立分区，不创建或调整分区，不刷写 Android 启动分区。

## 构建与校验

在 ARM64 Linux 构建机的项目目录运行：

```sh
nix build .#gnome-image
# 24 GB 改装机使用 .#gnome-24gb-image
(cd result && sha256sum -c SHA256SUMS)
```

其他架构的电脑需要配置 ARM64 Nix builder，并使用完整输出名，例如 `nix build .#packages.aarch64-linux.gnome-24gb-image`。

选择一个镜像入口运行一次 `nix build`，同一个 `result/` 中会同时得到下列文件；`manifest.json` 和 `SHA256SUMS` 统一记录这套配对的 root、ESP 镜像。

| 文件 | 用途 |
| --- | --- |
| `esp.sparse.img` | 用原厂 Fastboot 写入 `sunuefi_esp` |
| `esp.img` | 同一启动文件系统的原始 FAT32 镜像 |
| `root.sparse.img` | 用原厂 Fastboot 写入 `sunuefi_root` |
| `root.ext4.img` | 系统分区的原始 ext4 镜像 |
| `boot-files.tar` / `boot-files/` | 同套镜像的 Linux 载荷，用于更新已有 ESP |
| `manifest.json` / `SHA256SUMS` | 构建身份、容量和文件摘要 |

ESP 镜像为 512 MiB，使用 4096 字节逻辑扇区和 `SUNUEFI_ESP` 标签。root 镜像默认 16 GiB。目标分区分别至少需要相同容量；容量不足时应先停止，不能将镜像截短。

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

在早期选择页进入 UEFI，再启动 Linux。systemd-boot 菜单等待 15 秒；通过 `nixos-rebuild` 安装多个版本后，可在此选择旧版本回退。 音量键选择、短按电源确认需要 SunUEFI 0.5.10 或更新版本；旧版固件的扩展输入协议缺失，可能在按音量键后使菜单停止响应。系统自动登录 `nixos`，初始密码为 `nixos`。initrd 在检查、挂载和扩容文件系统前，会核对 ext4 类型、`PIANOROOT` 标签和 `sunuefi_root` 分区名；首次启动只扩大该 ext4 文件系统，不修改 GPT。

连接 Wi-Fi 后，在网络设置中查看平板的 IP 地址。同一网络的电脑可通过 SSH 登录，命令中的 `TABLET_IP` 替换为该地址：

```sh
ssh nixos@TABLET_IP
```

启动失败时，长按电源重启，在早期选择页按音量上回 Android。恢复原 Linux 系统需要通过原厂 Fastboot 分别恢复完整 root 备份和 ESP 备份；只恢复 ESP 不能恢复已经覆盖的 root 数据。

## 通过 USB 采集故障

验证镜像通过同一根 USB 数据线提供内核串口和有线网络。电脑作为 USB 主机，串口通常是 `/dev/ttyACM0`，网络接口名可用 `ip -brief link` 查看。平板的 USB 地址为 `10.42.0.2/24`，SSH 用户和初始密码仍为 `nixos`。

先接好数据线，在电脑打开一个终端等待串口出现并保存输出，再启动平板。下例假设本次平板串口为 `/dev/ttyACM0`；电脑已有其他 ACM 设备时，改成对应的实际设备路径。

```sh
while [ ! -e /dev/ttyACM0 ]; do sleep 1; done
sudo stty -F /dev/ttyACM0 raw -echo -hupcl
sudo cat /dev/ttyACM0 | tee piano-kernel-usb.log
```

在另一个终端配置电脑侧 USB 网络。将 `USB_IFACE` 替换为本次出现的 USB 网络接口名：

```sh
sudo ip link set USB_IFACE up
sudo ip address replace 10.42.0.1/24 dev USB_IFACE
ssh nixos@10.42.0.2 'sudo journalctl --boot --follow --output=short-monotonic --no-pager' | tee piano-journal-usb.log
```

确认电脑已经持续收到日志后，再复现 Wi-Fi 故障。串口输出停止后保留电脑上的两个日志文件；设备重新枚举后需要重新打开串口。无线不等待 USB，USB 建立后可通过 SSH 读取从启动开始保存的完整 journal。

内核启用 ath12k 调试接口、trace 能力和固件崩溃转储，默认记录 PCI、QMI、固件启动、MAC 和 WMI，不自动开启逐包 trace。固件生成的 `devcoredump` 会保存到 `/var/lib/piano-diagnostics/firmware/`；Linux 日志持久化到 journal，每秒同步一次，磁盘占用上限为 256 MiB。

USB 串口在控制器和主机枚举完成后才开始传输；其缓冲和工作队列可能在整机硬锁死时停止。USB 网络建立后，可另外执行 `ssh nixos@10.42.0.2 'sudo dmesg' > piano-dmesg.txt` 补采内核环中仍保留的启动记录。
