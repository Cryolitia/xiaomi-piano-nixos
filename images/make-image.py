#!/usr/bin/env python3
"""Assemble matching root and ESP images into one checked build result."""

import argparse
import hashlib
import json
from pathlib import Path
import stat
import subprocess


IMAGE_FILES = (
    "root.ext4.img",
    "root.sparse.img",
    "esp.img",
    "esp.sparse.img",
    "boot-files.tar",
)


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def copy_inputs(args):
    output = args.output
    boot_directory = output / "boot-files"
    boot_directory.mkdir(parents=True, exist_ok=True)
    run("cp", "-rL", str(args.boot_files) + "/.", boot_directory)

    # Keep holes in raw files while copying out of the immutable store. The
    # root copy must be writable before resize2fs changes its metadata.
    run("cp", "--sparse=always", args.esp_image / "esp.img", output / "esp.img")
    run("cp", args.esp_image / "esp.sparse.img", output / "esp.sparse.img")
    root = output / "root.ext4.img"
    run("cp", "--sparse=always", args.root_filesystem, root)
    root.chmod(stat.S_IMODE(root.stat().st_mode) | stat.S_IWUSR)


def prepare_root(output, target_bytes):
    root = output / "root.ext4.img"
    if root.stat().st_size > target_bytes:
        raise SystemExit(
            "The NixOS closure exceeds piano.image.rootSizeMiB; increase the image size."
        )

    run("truncate", "-s", target_bytes, root)
    run("resize2fs", "-f", root)
    run("e2fsck", "-f", "-n", root)
    label = subprocess.check_output(
        ["blkid", "-p", "-s", "LABEL", "-o", "value", str(root)], text=True
    ).rstrip("\n")
    if label != "PIANOROOT":
        raise SystemExit("The root filesystem label is not PIANOROOT.")
    run("img2simg", root, output / "root.sparse.img", 4096)


def archive_boot_files(output):
    # Fix archive metadata so rebuilding the same system produces the same
    # offline recovery payload, regardless of builder user or wall clock.
    run(
        "tar",
        "--sort=name",
        "--mtime=@1",
        "--owner=0",
        "--group=0",
        "--numeric-owner",
        "-C",
        output / "boot-files",
        "-cf",
        output / "boot-files.tar",
        "EFI",
        "loader",
    )


def write_manifest(args, target_bytes):
    esp = json.loads((args.esp_image / "manifest.json").read_text())
    files = {}
    for name in IMAGE_FILES:
        path = args.output / name
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        files[name] = {"bytes": path.stat().st_size, "sha256": digest}

    manifest = {
        "schemaVersion": 1,
        "system": args.system,
        "rootPartition": "sunuefi_root",
        "rootLabel": "PIANOROOT",
        "expandedRootBytes": target_bytes,
        "espPartition": esp["espPartition"],
        "espLabel": esp["espLabel"],
        "expandedEspBytes": esp["expandedEspBytes"],
        "espSectorBytes": esp["sectorBytes"],
        "bootFilesDirectory": "/EFI/nixos",
        "files": files,
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    # The common checksum list covers both filesystems and the metadata that
    # binds them to this system, so installers need only one build result.
    with (args.output / "SHA256SUMS").open("w") as stream:
        run(
            "sha256sum",
            *IMAGE_FILES,
            "manifest.json",
            cwd=args.output,
            stdout=stream,
        )


def build(args):
    target_bytes = args.root_size_mib * 1024**2
    copy_inputs(args)
    prepare_root(args.output, target_bytes)
    archive_boot_files(args.output)
    write_manifest(args, target_bytes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot-files", type=Path, required=True)
    parser.add_argument("--esp-image", type=Path, required=True)
    parser.add_argument("--root-filesystem", type=Path, required=True)
    parser.add_argument("--root-size-mib", type=int, required=True)
    parser.add_argument("--system", required=True)
    parser.add_argument("--output", type=Path, required=True)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
