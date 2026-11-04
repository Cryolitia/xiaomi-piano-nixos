set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo 'Usage: piano-make-boot-files SYSTEM DEVICE_TREE OUTPUT_DIRECTORY' >&2
  exit 2
fi

system=$(readlink -f -- "$1")
dtb=$(readlink -f -- "$2")
output=$3
payload="$output/EFI/Piano/stable"
test -x "$system/init"
test -f "$system/kernel"
test -f "$system/initrd"
test -f "$system/kernel-params"
test -f "$dtb"
mkdir -p -- "$payload" "$output/loader/entries"
cp -L -- "$system/kernel" "$payload/Image"
cp -L -- "$system/initrd" "$payload/initramfs"
cp -- "$dtb" "$payload/board.dtb"
printf 'title NixOS\nefi /EFI/Piano/LinuxBoot.efi\n' > "$output/loader/entries/debian.conf"

# SunUEFI's existing raw Linux loader starts /init in the initramfs. NixOS
# stage 1 then uses init= to select this exact generation of stage 2.
command_line="init=$system/init rdinit=/init $(cat "$system/kernel-params")"
if [ "${#command_line}" -gt 1535 ]; then
  echo 'Kernel command line exceeds the SunUEFI boot-image limit (1535 bytes).' >&2
  exit 1
fi
mkbootimg --header_version 2 --pagesize 4096 \
  --kernel "$payload/Image" --ramdisk "$payload/initramfs" \
  --dtb "$payload/board.dtb" --cmdline "$command_line" \
  -o "$payload/boot.img"

python3 - "$output" "$system" "$command_line" <<'PY'
import hashlib
import json
from pathlib import Path
import struct
import sys

output, system, command_line = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
payload = output / 'EFI/Piano/stable'
image = (payload / 'Image').read_bytes()
initrd = payload / 'initramfs'
dtb = (payload / 'board.dtb').read_bytes()
boot = (payload / 'boot.img').read_bytes()

def require(ok, reason):
    if not ok:
        raise SystemExit(reason)

require(len(image) >= 64 and image[56:60] == b'ARMd', 'Expected an uncompressed AArch64 Image.')
offset, span, flags = struct.unpack_from('<QQQ', image, 8)
require(offset <= 0x100000 and offset % 4096 == 0 and not flags & 1,
        'Unsupported AArch64 placement or endianness.')
require(len(image) <= span <= 0x8000000 - offset,
        'Kernel Image exceeds the reserved SunUEFI kernel window.')
require(0 < initrd.stat().st_size <= 16 * 1024**2,
        f'Initramfs is {initrd.stat().st_size} bytes; existing SunUEFI accepts at most 16 MiB.')
require(len(dtb) >= 40 and struct.unpack_from('>I', dtb)[0] == 0xd00dfeed
        and struct.unpack_from('>I', dtb, 4)[0] == len(dtb), 'Invalid flattened device tree.')
require(len(dtb) <= 0x200000 - 0x10000,
        'Device tree exceeds the existing SunUEFI handoff window.')
require(len(boot) <= 128 * 1024**2,
        f'Linux boot image is {len(boot)} bytes; SunUEFI with 128 MiB payload support is required; boot image exceeds 128 MiB.')
require(boot[:8] == b'ANDROID!' and struct.unpack_from('<I', boot, 40)[0] == 2
        and struct.unpack_from('<I', boot, 36)[0] == 4096, 'Expected Android boot header v2 with 4 KiB pages.')
require(struct.unpack_from('<I', boot, 8)[0] == len(image)
        and struct.unpack_from('<I', boot, 16)[0] == initrd.stat().st_size
        and struct.unpack_from('<I', boot, 1648)[0] == len(dtb), 'Boot header component sizes differ.')
require((boot[64:576] + boot[608:1632]).split(b'\0', 1)[0] == command_line.encode(),
        'Boot header command line differs from the selected NixOS generation.')
align = lambda n: (n + 4095) // 4096 * 4096
ramdisk_offset = 4096 + align(len(image))
dtb_offset = ramdisk_offset + align(initrd.stat().st_size)
require(boot[4096:4096 + len(image)] == image
        and boot[ramdisk_offset:ramdisk_offset + initrd.stat().st_size] == initrd.read_bytes()
        and boot[dtb_offset:dtb_offset + len(dtb)] == dtb,
        'Boot container component readback differs.')

files = {}
for name in ('EFI/Piano/stable/Image', 'EFI/Piano/stable/initramfs',
             'EFI/Piano/stable/board.dtb', 'EFI/Piano/stable/boot.img',
             'loader/entries/debian.conf'):
    data = (output / name).read_bytes()
    files[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
(output / 'manifest.json').write_text(json.dumps({
    'schemaVersion': 1,
    'system': system,
    'commandLine': command_line,
    'destination': '/EFI/Piano/stable',
    'files': files,
}, indent=2) + '\n')
PY
(
  cd -- "$output"
  sha256sum EFI/Piano/stable/{Image,initramfs,board.dtb,boot.img} \
    loader/entries/debian.conf manifest.json > SHA256SUMS
)
