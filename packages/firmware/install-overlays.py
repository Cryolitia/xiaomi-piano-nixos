"""Check and install complete firmware sets with their original notices."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil


def install_files(manifest_path, manifest, output):
    """Verify every blob before placing it under the kernel firmware path."""
    for name, identity in manifest["files"].items():
        source = manifest_path.parent / name
        data = source.read_bytes()

        if (
            len(data) != identity["bytes"]
            or hashlib.sha256(data).hexdigest() != identity["sha256"]
        ):
            raise ValueError("Firmware content differs from manifest: " + str(source))

        target = output / "lib/firmware" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o644)


def install_notices(manifest_path, output):
    # Keep each overlay's provenance alongside the firmware, including any
    # redistribution terms supplied by its source directory.
    notices = output / "share/doc/piano-firmware" / manifest_path.parent.name
    notices.mkdir(parents=True)

    for name in ("manifest.json", "README.md"):
        source = manifest_path.parent / name

        if source.is_file():
            shutil.copyfile(source, notices / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    policy = json.loads((args.source / "config/release.json").read_text())["firmware"]

    for relative in policy["overlays"]:
        manifest_path = args.source / relative
        manifest = json.loads(manifest_path.read_text())

        install_files(manifest_path, manifest, args.output)
        install_notices(manifest_path, args.output)


if __name__ == "__main__":
    main()
