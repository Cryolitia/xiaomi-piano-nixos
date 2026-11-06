#!/usr/bin/env python3
"""Build and read back a complete SunUEFI ESP without accessing a device."""

import argparse
import filecmp
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


CAPACITY = 512 * 1024**2
SECTOR = 4096
EPOCH = 315532800  # FAT timestamps start in 1980.


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def check_efi(path):
    with path.open("rb") as stream:
        header = stream.read(64)
        require(len(header) == 64 and header[:2] == b"MZ", f"Invalid EFI image: {path}")
        stream.seek(struct.unpack_from("<I", header, 60)[0])
        pe = stream.read(94)
    require(
        len(pe) == 94
        and pe[:4] == b"PE\0\0"
        and struct.unpack_from("<H", pe, 4)[0] == 0xAA64
        and struct.unpack_from("<H", pe, 24)[0] == 0x20B
        and struct.unpack_from("<H", pe, 92)[0] == 10,
        f"Expected an AArch64 PE32+ EFI application: {path}",
    )


def stage_boot_files(boot_files, tree):
    tree.mkdir()
    for directory in ("EFI", "loader"):
        shutil.copytree(boot_files / directory, tree / directory)

    # Store directories are read-only. Only the staging copy is made writable
    # so the boot manager can be added without changing the input derivation.
    tree.chmod(0o755)
    for path in tree.rglob("*"):
        if path.is_dir():
            path.chmod(0o755)


def install_boot_manager(tree, source):
    destination = tree / "EFI/BOOT/BOOTAA64.EFI"
    destination.parent.mkdir(parents=True)
    shutil.copyfile(source, destination)
    require(
        destination.stat().st_size <= 4 * 1024**2,
        "systemd-boot exceeds the resident core's 4 MiB application limit.",
    )
    check_efi(destination)


def create_filesystem(raw):
    """Create FAT32 with the device's 4 KiB logical sector geometry."""
    with raw.open("xb") as stream:
        stream.truncate(CAPACITY)
    run(
        "mkfs.vfat",
        "--invariant",
        "-S",
        SECTOR,
        "-s",
        1,
        "-F",
        32,
        "-n",
        "SUNUEFI_ESP",
        raw,
    )

    with raw.open("rb") as stream:
        bpb = stream.read(SECTOR)
    sectors = struct.unpack_from("<I", bpb, 32)[0]
    reserved = struct.unpack_from("<H", bpb, 14)[0]
    fats, cluster = bpb[16], bpb[13]
    fat_sectors = struct.unpack_from("<I", bpb, 36)[0]
    require(
        struct.unpack_from("<H", bpb, 11)[0] == SECTOR
        and cluster == 1
        and sectors * SECTOR == CAPACITY
        and bpb[510:512] == b"\x55\xaa"
        and bpb[82:90] == b"FAT32   "
        and bpb[71:82] == b"SUNUEFI_ESP"
        and struct.unpack_from("<H", bpb, 17)[0] == 0
        and (sectors - reserved - fats * fat_sectors) // cluster >= 0xFFF5,
        "ESP FAT32 geometry is incompatible with Piano's 4 KiB storage.",
    )


def populate_filesystem(raw, tree, files, boot_files, work):
    directories = sorted(
        (path for path in tree.rglob("*") if path.is_dir()),
        key=lambda path: (len(path.parts), str(path)),
    )
    for path in directories:
        run("mmd", "-i", raw, "::/" + path.relative_to(tree).as_posix())

    readback = work / "readback"
    for path in files:
        name = path.relative_to(tree).as_posix()
        # The boot-files derivation already hashed its payloads. Compare the
        # FAT readback with that manifest instead of rereading each source.
        info = boot_files.get(name)
        if info is None:
            info = {"bytes": path.stat().st_size, "sha256": digest(path)}
        os.utime(path, (EPOCH, EPOCH))
        run("mcopy", "-m", "-i", raw, path, "::/" + name)
        run("mcopy", "-i", raw, "::/" + name, readback)
        require(
            readback.stat().st_size == info["bytes"]
            and digest(readback) == info["sha256"],
            f"ESP readback differs: {name}",
        )
        readback.unlink()

    # Read every file back before accepting the filesystem or producing the
    # sparse image; successful mcopy alone does not prove the stored bytes.
    run("fsck.fat", "-n", raw)


def create_sparse_image(raw, sparse_path, work):
    run("img2simg", raw, sparse_path, SECTOR)
    expanded = work / "expanded.img"
    run("simg2img", sparse_path, expanded)
    require(
        expanded.stat().st_size == CAPACITY
        and filecmp.cmp(raw, expanded, shallow=False),
        "Sparse ESP roundtrip differs from the raw image.",
    )


def build(args):
    boot = json.loads((args.boot_files / "manifest.json").read_text())

    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        tree = work / "tree"
        stage_boot_files(args.boot_files, tree)
        install_boot_manager(tree, args.systemd_boot)

        files = sorted(path for path in tree.rglob("*") if path.is_file())
        require(
            sum(path.stat().st_size for path in files) + 2 * 1024**2 < CAPACITY,
            "Linux boot files exceed the 512 MiB ESP capacity.",
        )
        raw = work / "esp.img"
        create_filesystem(raw)
        populate_filesystem(raw, tree, files, boot["files"], work)
        create_sparse_image(raw, args.output, work)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot-files", type=Path, required=True)
    parser.add_argument("--systemd-boot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
