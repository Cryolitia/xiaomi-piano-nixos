set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo 'Usage: piano-make-boot-files SYSTEM OUTPUT_DIRECTORY' >&2
  exit 2
fi

python3 - "$1" "$2" <<'PYTHON'
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys

system = Path(sys.argv[1]).resolve(strict=True)
output = Path(sys.argv[2])

def require(ok, reason):
    if not ok:
        raise SystemExit(reason)

require(re.fullmatch(r'[0-9a-z]{32}-[A-Za-z0-9+._=-]+', system.name),
        'Expected a Nix store system name.')
bootspec = json.loads((system / 'boot.json').read_text())
boot = bootspec['org.nixos.bootspec.v1']
extension = bootspec['org.nixos.systemd-boot']
require(boot['toplevel'] == str(system) and boot['init'] == str(system / 'init')
        and (system / 'init').is_file(), 'The bootspec does not match its NixOS system.')
require(extension.get('devicetree'), 'The systemd-boot bootspec must include a device tree.')
require(not boot.get('initrdSecrets') and not bootspec.get('org.nixos.extra-initrd.v1', {}).get('paths'),
        'Offline Piano images require a self-contained initrd without external secrets or extra initrds.')
require(isinstance(boot['kernelParams'], list)
        and all(isinstance(param, str) for param in boot['kernelParams']),
        'Expected bootspec kernelParams to be a list of strings.')
command_line = ' '.join([f"init={boot['init']}"] + boot['kernelParams'])
require(all(32 <= ord(c) < 127 for c in command_line),
        'Kernel options must be one printable ASCII line.')
require(len(command_line.encode()) < 2048,
        'Kernel options exceed the AArch64 Linux 2047-byte limit.')
sort_key = extension.get('sortKey', 'nixos')
require(isinstance(sort_key, str) and re.fullmatch(r'[A-Za-z0-9._+-]+', sort_key),
        'Invalid systemd-boot sort key.')

# Match nixpkgs systemd-boot's boot_path so its updater can reuse and GC these
# files. Entries consume the public bootspec; no running profile or bootctl is
# needed to construct the initial, offline ESP.
def boot_path(source):
    source = Path(source).resolve(strict=True)
    relative = source.relative_to('/nix/store')
    store_name = relative.parts[0]
    require(re.fullmatch(r'[0-9a-z]{32}-[A-Za-z0-9+._=-]+', store_name),
            f'Invalid Nix store boot file: {source}')
    suffix = source.name
    name = suffix if suffix == store_name else f'{store_name}-{suffix}'
    return source, 'EFI/nixos/' + name + '.efi'

(output / 'EFI/nixos').mkdir(parents=True)
(output / 'loader/entries').mkdir(parents=True)
payloads = {}
for key, source in (('linux', boot['kernel']), ('initrd', boot['initrd']),
                    ('devicetree', extension['devicetree'])):
    source, target = boot_path(source)
    require(source.is_file() and 0 < source.stat().st_size <= 0xFFFFFFFF,
            f'{key} is empty or exceeds the FAT32 file size limit.')
    shutil.copyfile(source, output / target)
    payloads[key] = target
image = (output / payloads['linux']).read_bytes()
require(len(image) >= 64 and image[:2] == b'MZ' and image[56:60] == b'ARMd',
        'Expected an AArch64 Linux EFI-stub Image, not an ELF vmlinux.')
pe = struct.unpack_from('<I', image, 60)[0]
require(pe + 24 <= len(image) and image[pe:pe + 4] == b'PE\0\0',
        'The kernel has no complete PE header.')
machine, sections = struct.unpack_from('<HH', image, pe + 4)
optional_bytes = struct.unpack_from('<H', image, pe + 20)[0]
optional = pe + 24
require(machine == 0xAA64 and sections > 0 and optional_bytes >= 112
        and optional + optional_bytes + sections * 40 <= len(image),
        'The kernel has an invalid AArch64 PE section table.')
require(struct.unpack_from('<H', image, optional)[0] == 0x20B
        and struct.unpack_from('<H', image, optional + 68)[0] == 10,
        'The kernel must be a PE32+ EFI application.')
entry, = struct.unpack_from('<I', image, optional + 16)
loaded_bytes, = struct.unpack_from('<I', image, optional + 56)
require(0 < entry < loaded_bytes, 'The kernel PE entry point is outside its image.')
for index in range(sections):
    offset = optional + optional_bytes + index * 40
    virtual_bytes, virtual_address, raw_bytes, raw_offset = struct.unpack_from('<IIII', image, offset + 8)
    require(virtual_address + max(virtual_bytes, raw_bytes) <= loaded_bytes
            and raw_offset + raw_bytes <= len(image), 'The kernel PE section is out of bounds.')
directories = struct.unpack_from('<I', image, optional + 108)[0]
if directories >= 2:
    require(optional_bytes >= 128 and struct.unpack_from('<II', image, optional + 120) == (0, 0),
            'The EFI kernel must not import Windows libraries.')

initrd = output / payloads['initrd']
with initrd.open('rb') as stream:
    prefix = stream.read(6)
require(initrd.stat().st_size > 0 and (
    prefix.startswith(b'\x1f\x8b') or prefix == b'\xfd7zXZ\x00'
    or prefix.startswith(b'\x28\xb5\x2f\xfd') or prefix in (b'070701', b'070702')),
    'Expected a nonempty NixOS initrd in cpio, gzip, xz or zstd format.')
dtb = (output / payloads['devicetree']).read_bytes()
require(len(dtb) >= 40, 'The device tree header is incomplete.')
magic, size, structure, strings, reservations, version, compatible, _, strings_bytes, structure_bytes = struct.unpack_from('>10I', dtb)
require(magic == 0xD00DFEED and size == len(dtb) and version >= 17 and compatible <= 17
        and structure >= 40 and structure % 4 == 0 and structure + structure_bytes <= size
        and strings >= 40 and strings + strings_bytes <= size
        and reservations >= 40 and reservations % 8 == 0,
        'The flattened device tree has invalid block boundaries.')
position = reservations
while True:
    require(position + 16 <= size, 'The device tree reservation map is unterminated.')
    address, length = struct.unpack_from('>QQ', dtb, position)
    position += 16
    if address == length == 0:
        break

contents = (f'title NixOS\nlinux /{payloads["linux"]}\n'
            f'initrd /{payloads["initrd"]}\ndevicetree /{payloads["devicetree"]}\n'
            f'options {command_line}\nsort-key {sort_key}\n')
entry_name = 'nixos-' + hashlib.sha256(contents.encode()).hexdigest() + '.conf'
entry_path = 'loader/entries/' + entry_name
(output / entry_path).write_text(contents)
(output / 'loader/loader.conf').write_text(
    'default nixos-*\ntimeout 0\neditor no\nauto-entries no\n'
    'auto-firmware no\nconsole-mode keep\n')
files = {}
for path in sorted(output.rglob('*')):
    if path.is_file():
        with path.open('rb') as stream:
            files[path.relative_to(output).as_posix()] = {
                'bytes': path.stat().st_size,
                'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
(output / 'manifest.json').write_text(json.dumps({
    'schemaVersion': 1, 'system': str(system), 'entry': entry_path,
    'payloads': payloads, 'commandLine': command_line, 'files': files,
}, indent=2) + '\n')
with (output / 'manifest.json').open('rb') as stream:
    files['manifest.json'] = {'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
(output / 'SHA256SUMS').write_text(''.join(
    f"{info['sha256']}  {name}\n" for name, info in files.items()))
PYTHON
