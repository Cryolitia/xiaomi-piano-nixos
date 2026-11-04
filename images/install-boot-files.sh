set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo 'Usage: piano-install-boot-files SYSTEM' >&2
  exit 2
fi
system=$(readlink -f -- "$1")
test -x "$system/init"
fail() { echo "Piano boot update: $*" >&2; exit 1; }
esp=/boot
device=$(findmnt --noheadings --raw --output SOURCE --mountpoint "$esp") || fail 'Mount the existing SunUEFI ESP at /boot before updating.'
test -b "$device" || fail '/boot is not a block-device filesystem.'
test "$(blkid -p -s PART_ENTRY_NAME -o value "$device")" = sunuefi_esp || fail '/boot is not the sunuefi_esp partition.'
test "$(blkid -p -s LABEL -o value "$device")" = SUNUEFI_ESP || fail 'The ESP filesystem label is not SUNUEFI_ESP.'
test "$(findmnt --noheadings --raw --output FSTYPE --mountpoint "$esp")" = vfat || fail 'The ESP must use FAT32.'
root_device=$(findmnt --noheadings --raw --output SOURCE --mountpoint /)
test -b "$root_device" || fail 'The NixOS root is not a block-device filesystem.'
test "$(blkid -p -s PART_ENTRY_NAME -o value "$root_device")" = sunuefi_root || fail 'The NixOS root is not sunuefi_root.'
test "$(lsblk --noheadings --raw --output PKNAME "$root_device")" = "$(lsblk --noheadings --raw --output PKNAME "$device")" || fail 'The ESP and NixOS root must belong to the same disk.'
# The separately installed firmware and EFI manager remain prerequisites.
test -f "$esp/EFI/BOOT/BOOTAA64.EFI" || fail 'The existing systemd-boot application is missing.'
test -f "$esp/EFI/Piano/LinuxBoot.efi" || fail 'The existing SunUEFI LinuxBoot application is missing.'
test -f "$esp/loader/entries/debian.conf" || fail 'The existing SunUEFI loader entry is missing.'
test -d "$esp/EFI/Piano/stable" || fail 'The existing SunUEFI Linux boot directory is missing.'

work=$(mktemp -d "$esp/EFI/Piano/.nixos-update.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
piano-make-boot-files "$system" "$system/dtbs/piano.dtb" "$work"
(
  cd "$work"
  sha256sum -c SHA256SUMS
)
sync -f "$work/EFI/Piano/stable/boot.img"
for file in Image initramfs board.dtb; do
  mv -f -- "$work/EFI/Piano/stable/$file" "$esp/EFI/Piano/stable/$file"
done
mv -f -- "$work/loader/entries/debian.conf" "$esp/loader/entries/debian.conf"
# boot.img contains all three components; replace it last, within one FAT
# filesystem, so a failed build never replaces a working boot container.
mv -f -- "$work/EFI/Piano/stable/boot.img" "$esp/EFI/Piano/stable/boot.img"
sync -f "$esp"
