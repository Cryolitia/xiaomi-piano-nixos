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
    return importlib.import_module("package_release")


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
    parser.add_argument("memory_gib", nargs="?", type=int, choices=(16, 24), default=16)
    args = parser.parse_args()

    release_tools = load_tools(args.source)
    policy = json.loads((args.source / "config/release.json").read_text())["kernel"]

    board, original_hash, manifest = copy_board(args.source, args.custom_board)
    memory = release_tools.apply_memory_layout(board, args.memory_gib)
    overlays = apply_overlays(board, args.source, policy, release_tools)

    # Board bindings and optional media-device policy live in the shared source.
    normalization = release_tools.normalize_mainline_bindings(board)
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
                "handoff": "SunUEFI supplies panel and Gunyah data at runtime; current firmware also replaces RAM and DDR metadata from this boot. The static RAM map supports older firmware.",
                "device_write_performed": False,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
