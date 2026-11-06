#!/usr/bin/env python3
"""Create offline systemd-boot files from one NixOS system's bootspec."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct


def require(condition, reason):
    if not condition:
        raise SystemExit(reason)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_bootspec(system):
    """Reject bootspecs that would need state outside the offline image."""
    require(
        re.fullmatch(r"[0-9a-z]{32}-[A-Za-z0-9+._=-]+", system.name),
        "Expected a Nix store system name.",
    )
    bootspec = json.loads((system / "boot.json").read_text())
    boot = bootspec["org.nixos.bootspec.v1"]
    extension = bootspec["org.nixos.systemd-boot"]

    require(
        boot["toplevel"] == str(system)
        and boot["init"] == str(system / "init")
        and (system / "init").is_file(),
        "The bootspec does not match its NixOS system.",
    )
    require(
        extension.get("devicetree"),
        "The systemd-boot bootspec must include a device tree.",
    )
    require(
        not boot.get("initrdSecrets")
        and not bootspec.get("org.nixos.extra-initrd.v1", {}).get("paths"),
        "Offline Piano images require a self-contained initrd without external secrets or extra initrds.",
    )
    return boot, extension


def kernel_options(boot):
    require(
        isinstance(boot["kernelParams"], list)
        and all(isinstance(param, str) for param in boot["kernelParams"]),
        "Expected bootspec kernelParams to be a list of strings.",
    )
    options = " ".join([f"init={boot['init']}"] + boot["kernelParams"])
    require(
        all(32 <= ord(character) < 127 for character in options),
        "Kernel options must be one printable ASCII line.",
    )
    require(
        len(options.encode()) < 2048,
        "Kernel options exceed the AArch64 Linux 2047-byte limit.",
    )
    return options


def boot_path(source):
    """Match nixpkgs boot_path so its updater can reuse and collect our files."""
    source = Path(source).resolve(strict=True)
    relative = source.relative_to("/nix/store")
    store_name = relative.parts[0]
    require(
        re.fullmatch(r"[0-9a-z]{32}-[A-Za-z0-9+._=-]+", store_name),
        f"Invalid Nix store boot file: {source}",
    )
    suffix = source.name
    name = suffix if suffix == store_name else f"{store_name}-{suffix}"
    return source, "EFI/nixos/" + name + ".efi"


def copy_payloads(boot, extension, output):
    payloads = {}
    sources = (
        ("linux", boot["kernel"]),
        ("initrd", boot["initrd"]),
        ("devicetree", extension["devicetree"]),
    )
    for key, source in sources:
        source, target = boot_path(source)
        require(
            source.is_file() and 0 < source.stat().st_size <= 0xFFFFFFFF,
            f"{key} is empty or exceeds the FAT32 file size limit.",
        )
        shutil.copyfile(source, output / target)
        payloads[key] = target
    return payloads


def validate_kernel(path):
    """Check that the Linux Image carries an AArch64 EFI application header."""
    with path.open("rb") as stream:
        image = stream.read(64)
        require(
            len(image) == 64 and image[:2] == b"MZ" and image[56:60] == b"ARMd",
            "Expected an AArch64 Linux EFI-stub Image, not an ELF vmlinux.",
        )
        stream.seek(struct.unpack_from("<I", image, 60)[0])
        pe = stream.read(94)
    require(
        len(pe) == 94
        and pe[:4] == b"PE\0\0"
        and struct.unpack_from("<H", pe, 4)[0] == 0xAA64
        and struct.unpack_from("<H", pe, 24)[0] == 0x20B
        and struct.unpack_from("<H", pe, 92)[0] == 10,
        "The kernel must be an AArch64 PE32+ EFI application.",
    )


def validate_initrd(path):
    with path.open("rb") as stream:
        prefix = stream.read(6)
    require(
        path.stat().st_size > 0
        and (
            prefix.startswith(b"\x1f\x8b")
            or prefix == b"\xfd7zXZ\x00"
            or prefix.startswith(b"\x28\xb5\x2f\xfd")
            or prefix in (b"070701", b"070702")
        ),
        "Expected a nonempty NixOS initrd in cpio, gzip, xz or zstd format.",
    )


def validate_device_tree(path):
    with path.open("rb") as stream:
        header = stream.read(40)
    require(len(header) == 40, "The device tree header is incomplete.")
    magic, size, _, _, _, version, compatible, _, _, _ = struct.unpack(">10I", header)
    require(
        magic == 0xD00DFEED
        and size == path.stat().st_size
        and version >= 17
        and compatible <= 17,
        "Expected a complete flattened device tree compatible with version 17.",
    )


def write_entries(output, payloads, command_line, sort_key, timeout):
    # The content hash lets the standard updater identify this initial entry
    # without inventing a generation number before a system profile exists.
    contents = (
        f'title NixOS\nlinux /{payloads["linux"]}\n'
        f'initrd /{payloads["initrd"]}\ndevicetree /{payloads["devicetree"]}\n'
        f"options {command_line}\nsort-key {sort_key}\n"
    )
    entry_name = "nixos-" + hashlib.sha256(contents.encode()).hexdigest() + ".conf"
    entry_path = "loader/entries/" + entry_name
    (output / entry_path).write_text(contents)
    (output / "loader/loader.conf").write_text(
        f"default nixos-*\ntimeout {timeout}\neditor no\nauto-entries no\n"
        "auto-firmware no\nconsole-mode keep\n"
    )


def write_manifest(output):
    files = {}
    for path in sorted(output.rglob("*")):
        if path.is_file():
            files[path.relative_to(output).as_posix()] = {
                "bytes": path.stat().st_size,
                "sha256": digest(path),
            }

    # This internal manifest is used only for FAT readback verification.
    (output / "manifest.json").write_text(json.dumps({"files": files}, indent=2) + "\n")


def build(system, output, timeout):
    system = system.resolve(strict=True)
    boot, extension = read_bootspec(system)
    command_line = kernel_options(boot)
    sort_key = extension.get("sortKey", "nixos")
    require(
        isinstance(sort_key, str) and re.fullmatch(r"[A-Za-z0-9._+-]+", sort_key),
        "Invalid systemd-boot sort key.",
    )

    (output / "EFI/nixos").mkdir(parents=True)
    (output / "loader/entries").mkdir(parents=True)
    payloads = copy_payloads(boot, extension, output)
    validate_kernel(output / payloads["linux"])
    validate_initrd(output / payloads["initrd"])
    validate_device_tree(output / payloads["devicetree"])

    write_entries(output, payloads, command_line, sort_key, timeout)
    write_manifest(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("system", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--timeout", required=True)
    args = parser.parse_args()
    build(args.system, args.output, args.timeout)


if __name__ == "__main__":
    main()
