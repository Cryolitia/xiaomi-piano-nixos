"""Apply the pinned Linux board overlays using their existing exact-path logic."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

source, panel = Path(sys.argv[1]), sys.argv[2]
custom_board = sys.argv[3] if len(sys.argv) > 3 else "-"
memory_path = sys.argv[4] if len(sys.argv) > 4 else "-"
sys.path.insert(0, str(source / "tools"))
from compose_piano_dtb import read_fdt, write_fdt
from package_release import (
    apply_cpu_model_overlay,
    normalize_mainline_bindings,
    select_panel_vendor,
)

policy = json.loads((source / "config/release.json").read_text())["kernel"]
board_source = (source / "vendor/piano-linux/board.dtb"
                if custom_board == "-" else Path(custom_board))
original_hash = hashlib.sha256(board_source.read_bytes()).hexdigest()
if custom_board == "-":
    manifest = json.loads((board_source.parent / "manifest.json").read_text())
    if original_hash != manifest["sha256"]:
        raise ValueError("Piano board DTB differs from its source manifest")
else:
    manifest = {"source": "Explicit device-specific Linux board DTB",
                "sha256": original_hash}
board = Path("piano.dtb")
shutil.copyfile(board_source, board)
board.chmod(0o644)
memory = None
if memory_path != "-":
    memory = json.loads(Path(memory_path).read_text())
    if original_hash != memory["baseSha256"]:
        raise ValueError("The selected RAM profile does not match the base DTB")
    properties = memory["properties"]
    if set(properties) != {"/memory", "/ddr-regions"} or \
            set(properties["/memory"]) != {"reg", "ddr_size", "ddr_manufacturer_id"} or \
            set(properties["/ddr-regions"]) != {"region2"}:
        raise ValueError("RAM profiles may replace only the four verified DDR properties")
    parsed = read_fdt(board.read_bytes())
    for node, values in properties.items():
        if node not in parsed["tree"]:
            raise ValueError("RAM profile target is missing: " + node)
        for key, value in values.items():
            parsed["tree"][node][key] = bytes.fromhex(value)
    board.write_bytes(write_fdt(parsed))
    if hashlib.sha256(board.read_bytes()).hexdigest() != memory["resultSha256"]:
        raise ValueError("The selected RAM profile did not produce its verified DTB")
work = Path("overlays")
work.mkdir()
overlays = [apply_cpu_model_overlay(board, source / policy["cpu_model_overlay"], work)]
for overlay in policy["additional_dtb_overlays"]:
    overlays.append(apply_cpu_model_overlay(board, source / overlay, work, cpu_only=False))
normalization = normalize_mainline_bindings(board)
selection = select_panel_vendor(board, panel)
Path("manifest.json").write_text(json.dumps({
    "source": manifest,
    "memory": memory,
    "overlays": overlays,
    "normalization": normalization,
    "panel": selection,
    "sha256": hashlib.sha256(board.read_bytes()).hexdigest(),
    "handoff": "Existing SunUEFI supplies panel and Gunyah runtime data; RAM addresses must already match the device in this DTB",
    "device_write_performed": False,
}, indent=2) + "\n")
