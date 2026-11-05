"""Apply the pinned board overlays and the selected Piano RAM layout."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import shutil
import sys


def load_tools(source):
    # These helpers and their overlay policy are pinned together in SunUEFI.
    # Import them only after the explicit source directory is known.
    sys.path.insert(0, str(source / "tools"))
    return (
        importlib.import_module("compose_piano_dtb"),
        importlib.import_module("package_release"),
    )


def copy_board(source, custom_board):
    board_source = (
        source / "vendor/piano-linux/board.dtb"
        if custom_board == "-"
        else Path(custom_board)
    )
    original_hash = hashlib.sha256(board_source.read_bytes()).hexdigest()

    if custom_board == "-":
        manifest = json.loads((board_source.parent / "manifest.json").read_text())

        if original_hash != manifest["sha256"]:
            raise ValueError("Piano board DTB differs from its source manifest")
    else:
        manifest = {
            "source": "Explicit device-specific Linux board DTB",
            "sha256": original_hash,
        }

    board = Path("piano.dtb")
    shutil.copyfile(board_source, board)
    board.chmod(0o644)

    return board, original_hash, manifest


def apply_memory_layout(board, original_hash, memory_path, tree_tools):
    if memory_path == "-":
        return None

    memory = json.loads(Path(memory_path).read_text())

    if original_hash != memory["baseSha256"]:
        raise ValueError("The selected RAM profile does not match the base DTB")

    # A capacity selection may change only the four reviewed DDR properties.
    # It must not replace unrelated devices or carveouts in the source tree.
    properties = memory["properties"]

    if (
        set(properties) != {"/memory", "/ddr-regions"}
        or set(properties["/memory"]) != {"reg", "ddr_size", "ddr_manufacturer_id"}
        or set(properties["/ddr-regions"]) != {"region2"}
    ):
        raise ValueError(
            "RAM profiles may replace only the four verified DDR properties"
        )

    parsed = tree_tools.read_fdt(board.read_bytes())

    for node, values in properties.items():
        if node not in parsed["tree"]:
            raise ValueError("RAM profile target is missing: " + node)

        for key, value in values.items():
            parsed["tree"][node][key] = bytes.fromhex(value)

    board.write_bytes(tree_tools.write_fdt(parsed))

    if hashlib.sha256(board.read_bytes()).hexdigest() != memory["resultSha256"]:
        raise ValueError("The selected RAM profile did not produce its verified DTB")

    return memory


def apply_overlays(board, source, policy, release_tools):
    work = Path("overlays")
    work.mkdir()
    overlays = [
        release_tools.apply_cpu_model_overlay(
            board, source / policy["cpu_model_overlay"], work
        )
    ]

    for overlay in policy["additional_dtb_overlays"]:
        overlays.append(
            release_tools.apply_cpu_model_overlay(
                board, source / overlay, work, cpu_only=False
            )
        )

    return overlays


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("panel")
    parser.add_argument("custom_board", nargs="?", default="-")
    parser.add_argument("memory_path", nargs="?", default="-")
    args = parser.parse_args()

    tree_tools, release_tools = load_tools(args.source)
    policy = json.loads((args.source / "config/release.json").read_text())["kernel"]

    board, original_hash, manifest = copy_board(args.source, args.custom_board)
    memory = apply_memory_layout(board, original_hash, args.memory_path, tree_tools)
    overlays = apply_overlays(board, args.source, policy, release_tools)

    # Remove downstream-only consumers before converting the shared MMSS
    # provider to the standard two-cell binding. DPU inherits its bandwidth
    # paths from MDSS; panel selection then records the final shipped tree.
    normalization = release_tools.normalize_mainline_bindings(board)
    for name in ("display-interconnects.dtso", "wifi-memory.dtso"):
        overlays.append(
            release_tools.apply_cpu_model_overlay(
                board,
                Path(__file__).with_name(name),
                Path("overlays"),
                cpu_only=False,
            )
        )
    selection = release_tools.select_panel_vendor(board, args.panel)

    Path("manifest.json").write_text(
        json.dumps(
            {
                "source": manifest,
                "memory": memory,
                "overlays": overlays,
                "normalization": normalization,
                "panel": selection,
                "sha256": hashlib.sha256(board.read_bytes()).hexdigest(),
                "handoff": "Existing SunUEFI supplies panel and Gunyah runtime data; RAM addresses must already match the device in this DTB",
                "device_write_performed": False,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
