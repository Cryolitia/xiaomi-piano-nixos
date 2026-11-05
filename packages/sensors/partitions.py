"""Supply the existing sensor importer with the tablet's active Android slot.

util-linux validates the GPT; liblp validates Android's logical-partition
metadata. Neither reader opens an Android partition for writing. Only the
upstream importer creates read-only mappings and copies calibration data.
"""

import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess

from liblp import GetPartitionName, LP_SECTOR_SIZE, LP_TARGET_TYPE_LINEAR, ReadMetadata


def block_sysfs(device):
    """Resolve a real partition without relying on a fixed UFS disk name."""
    info = device.stat()
    if not stat.S_ISBLK(info.st_mode):
        raise ValueError(f'{device} is not a block device')

    node = Path('/sys/dev/block') / f'{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}'
    node = node.resolve(strict=True)
    if not (node / 'partition').is_file():
        raise ValueError(f'{device} is not a partition')
    return node


def active_slot():
    """Read Qualcomm's active-slot GPT attributes through standard sfdisk."""
    devices = {slot: Path(f'/dev/disk/by-partlabel/boot_{slot}') for slot in 'ab'}
    parents = {block_sysfs(device).parent for device in devices.values()}
    if len(parents) != 1:
        raise ValueError('Android boot partitions are not on the same disk')

    parent = parents.pop()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', parent.name):
        raise ValueError('Invalid Android boot disk name')
    result = subprocess.run(
        ['sfdisk', '--json', f'/dev/{parent.name}'],
        check=True,
        text=True,
        capture_output=True,
        env=os.environ | {'LC_ALL': 'C'},
    )
    partitions = json.loads(result.stdout)['partitiontable']['partitions']
    candidates = []

    for slot, device in devices.items():
        matches = [
            p for p in partitions if Path(p['node']).resolve() == device.resolve()
        ]
        if len(matches) != 1:
            raise ValueError(f'No unique GPT entry for {device}')

        match = re.search(r'GUID:([0-9,]+)', matches[0].get('attrs', ''))
        bits = {int(bit) for bit in match[1].split(',')} if match else set()
        attributes = sum(1 << bit for bit in bits)
        priority = attributes >> 48 & 3

        # Qualcomm: priority 48..49, active 50, retries 51..53,
        # successful 54, unbootable 55. This never changes the selected slot.
        if (
            priority
            and attributes & (1 << 50)
            and not attributes & (1 << 55)
            and (attributes & (1 << 54) or attributes >> 51 & 7)
        ):
            candidates.append((priority, slot))

    candidates.sort(reverse=True)
    if not candidates or (len(candidates) > 1 and candidates[0][0] == candidates[1][0]):
        raise ValueError('GPT does not identify one bootable active Android slot')
    return candidates[0][1]


def import_configuration(importer):
    """Keep slot selection in the process environment, not a state file."""
    slot = active_slot()
    environment = os.environ | {
        'PIANO_SENSORS_ODM_NAME': f'odm_{slot}',
        'PIANO_SENSORS_VENDOR_NAME': f'vendor_{slot}',
        'PIANO_SENSORS_METADATA_SLOT': str('ab'.index(slot)),
    }
    os.execve(importer, [importer], environment)


def linear_table(device, name):
    """Emit only bounded linear extents from this tablet's single super device."""
    slot = int(os.environ['PIANO_SENSORS_METADATA_SLOT'])
    if slot not in (0, 1):
        raise ValueError('Invalid Android metadata slot')

    metadata = ReadMetadata(str(device), slot)
    if slot >= metadata.geometry.metadata_slot_count:
        raise ValueError('Android metadata slot is outside the device geometry')
    matches = [p for p in metadata.partitions if GetPartitionName(p) == name]
    if len(matches) != 1 or len(metadata.block_devices) != 1:
        raise ValueError(f'No unique single-device logical partition {name}')

    partition = matches[0]
    block = metadata.block_devices[0]
    capacity = int((block_sysfs(device) / 'size').read_text()) * 512
    if block.size > capacity:
        raise ValueError('Logical partition metadata exceeds the super partition')

    start = 0
    rows = []
    for index in range(
        partition.first_extent_index,
        partition.first_extent_index + partition.num_extents,
    ):
        extent = metadata.extents[index]
        if (
            extent.target_type != LP_TARGET_TYPE_LINEAR
            or extent.target_source != 0
            or not extent.num_sectors
            or extent.target_data < block.first_logical_sector
            or (extent.target_data + extent.num_sectors) * LP_SECTOR_SIZE > block.size
        ):
            raise ValueError(f'Invalid or unsupported extent in {name}')
        rows.append(
            f'{start} {extent.num_sectors} linear {device} {extent.target_data}'
        )
        start += extent.num_sectors

    if not rows:
        raise ValueError(f'Logical partition {name} is empty')
    print('\n'.join(rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    importer = commands.add_parser('import')
    importer.add_argument('--importer', required=True)
    table = commands.add_parser('table')
    table.add_argument('device', type=Path)
    table.add_argument('name')
    args = parser.parse_args()

    if args.command == 'import':
        import_configuration(args.importer)
    else:
        linear_table(args.device, args.name)


if __name__ == '__main__':
    main()
