"""Check and install complete firmware sets, retaining their original notices."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
policy = json.loads((source / "config/release.json").read_text())["firmware"]
for relative in policy["overlays"]:
    manifest_path = source / relative
    manifest = json.loads(manifest_path.read_text())
    for name, identity in manifest["files"].items():
        path = manifest_path.parent / name
        data = path.read_bytes()
        if len(data) != identity["bytes"] or hashlib.sha256(data).hexdigest() != identity["sha256"]:
            raise ValueError("Firmware content differs from manifest: " + str(path))
        target = output / "lib/firmware" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        target.chmod(0o644)
    notices = output / "share/doc/piano-firmware" / manifest_path.parent.name
    notices.mkdir(parents=True)
    for name in ("manifest.json", "README.md"):
        path = manifest_path.parent / name
        if path.is_file():
            shutil.copyfile(path, notices / name)
