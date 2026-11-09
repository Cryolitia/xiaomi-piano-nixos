"""Apply the pinned board overlays for the SunUEFI runtime handoff."""

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

    return board, manifest


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
    args = parser.parse_args()

    release_tools = load_tools(args.source)
    policy = json.loads((args.source / "config/release.json").read_text())["kernel"]

    board, manifest = copy_board(args.source, args.custom_board)
    overlays = apply_overlays(board, args.source, policy, release_tools)

    # Board bindings and optional media-device policy live in the shared source.
    normalization = release_tools.normalize_mainline_bindings(board)
    selection = release_tools.select_panel_vendor(board, args.panel)

    Path("manifest.json").write_text(
        json.dumps(
            {
                "source": manifest,
                "overlays": overlays,
                "normalization": normalization,
                "panel": selection,
                "sha256": hashlib.sha256(board.read_bytes()).hexdigest(),
                "handoff": "SunUEFI fills RAM ranges and DDR metadata from this boot's ABL device tree and supplies panel, Gunyah, Bluetooth and RTC data.",
                "device_write_performed": False,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
