"""Build and read back a complete SunUEFI ESP without accessing a device."""

import argparse
import hashlib
import importlib.util
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


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def check_efi(path):
    data = path.read_bytes()
    require(data[:2] == b"MZ" and len(data) >= 64, f"Invalid EFI image: {path}")
    pe = struct.unpack_from("<I", data, 60)[0]
    require(pe + 264 <= len(data) and data[pe:pe + 4] == b"PE\0\0",
            f"Invalid PE header: {path}")
    require(struct.unpack_from("<H", data, pe + 4)[0] == 0xAA64
            and struct.unpack_from("<H", data, pe + 24)[0] == 0x20B
            and struct.unpack_from("<H", data, pe + 92)[0] == 10,
            f"Expected an AArch64 PE32+ EFI application: {path}")
    require(struct.unpack_from("<II", data, pe + 144) == (0, 0),
            f"EFI application must not import Windows libraries: {path}")


def build(args):
    output = args.output
    output.mkdir()
    spec = importlib.util.spec_from_file_location("sunuefi_sparse", args.sparse_tool)
    sparse = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sparse)
    boot = json.loads((args.boot_files / "manifest.json").read_text())
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        tree = work / "tree"
        tree.mkdir()
        for directory in ("EFI", "loader"):
            shutil.copytree(args.boot_files / directory, tree / directory)
        # Nix store directories are read-only; the staging copy must accept EFI files.
        tree.chmod(0o755)
        for path in tree.rglob("*"):
            if path.is_dir():
                path.chmod(0o755)
        for name, info in boot["files"].items():
            path = tree / name
            require(path.is_file() and path.stat().st_size == info["bytes"]
                    and digest(path) == info["sha256"], f"Boot file differs: {name}")
        (tree / "EFI/BOOT").mkdir(parents=True)
        shutil.copyfile(args.systemd_boot, tree / "EFI/BOOT/BOOTAA64.EFI")
        shutil.copyfile(args.linux_loader, tree / "EFI/Piano/LinuxBoot.efi")
        require((tree / "EFI/BOOT/BOOTAA64.EFI").stat().st_size <= 4 * 1024**2,
                "systemd-boot exceeds the resident core's 4 MiB application limit.")
        for path in (tree / "EFI/BOOT/BOOTAA64.EFI", tree / "EFI/Piano/LinuxBoot.efi"):
            check_efi(path)
        (tree / "loader/loader.conf").write_text(
            "default debian.conf\ntimeout 0\neditor no\nauto-entries no\n"
            "auto-firmware no\nconsole-mode keep\n")
        files = sorted(path for path in tree.rglob("*") if path.is_file())
        require(sum(path.stat().st_size for path in files) + 2 * 1024**2 < CAPACITY,
                "Linux boot files exceed the 512 MiB ESP capacity.")
        raw = output / "esp.img"
        with raw.open("xb") as stream:
            stream.truncate(CAPACITY)
        run("mkfs.vfat", "--invariant", "-S", SECTOR, "-s", 1, "-F", 32,
            "-n", "SUNUEFI_ESP", raw)
        with raw.open("rb") as stream:
            bpb = stream.read(SECTOR)
        sectors = struct.unpack_from("<I", bpb, 32)[0]
        reserved = struct.unpack_from("<H", bpb, 14)[0]
        fats, cluster = bpb[16], bpb[13]
        fat_sectors = struct.unpack_from("<I", bpb, 36)[0]
        require(struct.unpack_from("<H", bpb, 11)[0] == SECTOR and cluster == 1
                and sectors * SECTOR == CAPACITY and bpb[510:512] == b"\x55\xaa"
                and bpb[82:90] == b"FAT32   " and bpb[71:82] == b"SUNUEFI_ESP"
                and struct.unpack_from("<H", bpb, 17)[0] == 0
                and (sectors - reserved - fats * fat_sectors) // cluster >= 0xFFF5,
                "ESP FAT32 geometry is incompatible with Piano's 4 KiB storage.")
        directories = sorted((path for path in tree.rglob("*") if path.is_dir()),
                             key=lambda path: (len(path.parts), str(path)))
        for path in directories:
            run("mmd", "-i", raw, "::/" + path.relative_to(tree).as_posix())
        esp_files = {}
        readback = work / "readback"
        for path in files:
            name = path.relative_to(tree).as_posix()
            os.utime(path, (EPOCH, EPOCH))
            run("mcopy", "-m", "-i", raw, path, "::/" + name)
            run("mcopy", "-i", raw, "::/" + name, readback)
            require(digest(readback) == digest(path), f"ESP readback differs: {name}")
            readback.unlink()
            esp_files[name] = {"bytes": path.stat().st_size, "sha256": digest(path)}
        run("fsck.fat", "-n", raw)
        sparse_path = output / "esp.sparse.img"
        info = sparse.convert(raw, sparse_path, SECTOR)
        require(info["expanded_bytes"] == CAPACITY and info["expanded_sha256"] == digest(raw),
                "Sparse ESP differs from the raw image.")
        expanded = work / "expanded.img"
        run("simg2img", sparse_path, expanded)
        require(expanded.stat().st_size == CAPACITY and digest(expanded) == digest(raw),
                "Sparse ESP roundtrip differs from the raw image.")
    manifest = {
        "schemaVersion": 1,
        "system": boot["system"],
        "espPartition": "sunuefi_esp",
        "espLabel": "SUNUEFI_ESP",
        "sectorBytes": SECTOR,
        "expandedEspBytes": CAPACITY,
        "espFiles": esp_files,
        "files": {
            "esp.img": {"format": "raw-fat32", "bytes": CAPACITY,
                        "sha256": digest(raw)},
            "esp.sparse.img": {"format": "android-sparse", "bytes": info["bytes"],
                               "sha256": info["sha256"], "expandedBytes": CAPACITY},
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "SHA256SUMS").write_text("".join(
        f"{digest(output / name)}  {name}\n"
        for name in ("esp.img", "esp.sparse.img", "manifest.json")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot-files", type=Path, required=True)
    parser.add_argument("--systemd-boot", type=Path, required=True)
    parser.add_argument("--linux-loader", type=Path, required=True)
    parser.add_argument("--sparse-tool", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    build(parser.parse_args())
