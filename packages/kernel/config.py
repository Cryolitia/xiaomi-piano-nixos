"""Merge Piano hardware fragments into the NixOS kernel defconfig."""

import argparse
from pathlib import Path
import re


HARDWARE_FRAGMENTS = (
    "piano-bluetooth.config",
    "piano-flash.config",
    "piano-pen-dock.config",
    "piano-ir.config",
    "piano-cpucp-early.config",
    "piano-userspace-security.config",
    "piano-sleep.config",
    "piano-platform.config",
)


def config_fragments(kernel, sunuefi):
    """Keep the upstream fragment order: later settings replace earlier ones."""
    return [
        kernel / "arch/arm64/configs/piano_defconfig",
        kernel / "arch/arm64/configs/piano_rootfs.config",
        *(sunuefi / "linux/configs" / name for name in HARDWARE_FRAGMENTS),
    ]


def read_settings(fragments):
    settings = {}

    for fragment in fragments:
        for line in fragment.read_text().splitlines():
            enabled = re.fullmatch(r"(CONFIG_[A-Z0-9_]+)=(.*)", line)
            disabled = re.fullmatch(r"# (CONFIG_[A-Z0-9_]+) is not set", line)

            if enabled:
                settings[enabled[1]] = line
            elif disabled:
                settings[disabled[1]] = line

    return settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("sunuefi", type=Path)
    args = parser.parse_args()

    settings = read_settings(config_fragments(args.kernel, args.sunuefi))
    output = args.kernel / "arch/arm64/configs/piano_nixos_defconfig"
    output.write_text("\n".join(settings[name] for name in sorted(settings)) + "\n")


if __name__ == "__main__":
    main()
